import AppKit
import CoreAudio
import Foundation
import Observation

@Observable
final class Controller {
    /// The driver's output device, the one call apps pick.
    static let callsUID = "CallLane_UID"
    /// Its hidden input twin, the one the engine reads.
    static let tapUID = "CallLane_2_UID"
    /// The v0.1 aggregate device. Destroyed on sight.
    static let legacyUID = "dev.rav4nn.calllane.calls"
    private static let ownUIDs: Set<String> = [callsUID, tapUID, legacyUID]
    static let microphoneDenied = "Microphone access denied. CallLane reads its hidden tap like a mic. Allow CallLane under System Settings → Privacy & Security → Microphone."
    static let lockPaused = "Lock input paused: another app keeps changing the microphone. Turn Lock input off and on to resume."

    private let audio: AudioSystem
    private let engine: EngineControl
    private let defaults: UserDefaults
    private let appVersion: String
    /// Monotonic: a clock that jumps backwards must not extend the heal's window.
    private let now: () -> ContinuousClock.Instant
    private var tokens: [ListenerToken] = []
    private var runningToken: ListenerToken?
    private var runningWatched: AudioObjectID?
    private var pending: DispatchWorkItem?
    /// The last real output the user had; where the system output goes back to when CallLane
    /// must not stay the system output.
    private var lastRealOutput: AudioObjectID?
    /// Its UID. A coreaudiod restart can hand the same device a new id; the UID survives.
    private var lastRealOutputUID: String?
    /// Armed by a coreaudiod restart: the output to put back when it re-registers, and the
    /// moment we stop waiting for it.
    private var healOutputUID: String?
    private var healDeadline = ContinuousClock.now   // only read while `healOutputUID` is set
    private var tapID: AudioObjectID?
    private var driverVersion: String?
    private var microphoneRequested = false
    /// Set when coreaudiod restarted or the Mac woke: our AudioUnits and the listener we hold
    /// on the CallLane device are stale. The system-object listeners survive — that object is
    /// always id 1 and the HAL re-applies their registrations itself.
    private var restarted = false
    private var wakeToken: NSObjectProtocol?
    /// When the lock had to revert the default input, most recent last.
    private var lockReverts: [Date] = []

    private(set) var devices: [AudioDevice] = []
    private(set) var defaultOutputID: AudioObjectID?
    private(set) var defaultInputID: AudioObjectID?
    private(set) var outputVolume: Float?
    private(set) var callsInUse = false
    private(set) var status = ""

    init(audio: AudioSystem, engine: EngineControl, defaults: UserDefaults = .standard,
         appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
         now: @escaping () -> ContinuousClock.Instant = { .now }) {
        self.audio = audio
        self.engine = engine
        self.defaults = defaults
        self.appVersion = appVersion
        self.now = now
    }

    // MARK: derived

    var outputs: [AudioDevice] { devices.filter { $0.hasOutput && !Self.ownUIDs.contains($0.uid) } }
    var inputs: [AudioDevice] { devices.filter { $0.hasInput && !Self.ownUIDs.contains($0.uid) } }
    var callsDevice: AudioDevice? { devices.first { $0.uid == Self.callsUID } }
    var defaultOutputDevice: AudioDevice? { devices.first { $0.id == defaultOutputID } }

    /// Non-nil when the driver is absent or older than the app. The panel shows it in place of
    /// the CallLane status row.
    var driverStatus: String? {
        if callsDevice == nil || tapID == nil {
            return "Driver not installed. Run `make install-driver` or reinstall the cask."
        }
        if let v = driverVersion, v.compare(appVersion, options: .numeric) == .orderedAscending {
            return "Driver is v\(v), app is v\(appVersion). Reinstall the cask."
        }
        return nil
    }

    var inputLocked: Bool {
        get { defaults.string(forKey: "lockedInputUID") != nil }
        set {
            if newValue, let id = audio.defaultInput(), let dev = devices.first(where: { $0.id == id }) {
                defaults.set(dev.uid, forKey: "lockedInputUID")
                defaults.set(audio.volume(id, scope: .input) ?? 1, forKey: "lockedInputVolume")
                // What the user had before CallLane ever touched the input. Kept across
                // re-locks, so quit restores the original, not the last locked device.
                if defaults.string(forKey: "previousInputUID") == nil {
                    defaults.set(dev.uid, forKey: "previousInputUID")
                    defaults.set(audio.volume(id, scope: .input) ?? 1, forKey: "previousInputVolume")
                }
            } else {
                defaults.removeObject(forKey: "lockedInputUID")
                if !newValue {
                    restorePreviousInput()
                    defaults.removeObject(forKey: "previousInputUID")
                    defaults.removeObject(forKey: "previousInputVolume")
                }
            }
            clearLockFight()
            reconcile()
        }
    }

    // MARK: lifecycle

    func start() {
        reconcile()
        requestMicrophoneIfNeeded()   // ask at launch, not in the middle of the first call
        for sel in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice] {
            if let t = audio.listen(AudioObjectID(kAudioObjectSystemObject), sel, { [weak self] in self?.scheduleReconcile() }) {
                tokens.append(t)
            }
        }
        // Every install, upgrade and uninstall runs `killall coreaudiod`. This is the property
        // that fires when it comes back, and the only reliable signal: the device ids often
        // come back identical, so nothing else tells us our listeners and units are dead.
        if let t = audio.listen(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyServiceRestarted, { [weak self] in self?.handleServiceRestart() }) {
            tokens.append(t)
        }
        // Sleep/wake can re-create the devices behind our units without a restart event.
        wakeToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.handleRestart() }
    }

    deinit {
        if let t = wakeToken { NSWorkspace.shared.notificationCenter.removeObserver(t) }
    }

    /// coreaudiod came back. Same teardown as a wake, plus: a Bluetooth headset re-registers late
    /// and macOS lands the default output on the built-in speaker meanwhile, so arm the heal.
    /// Only this path arms it — after a wake macOS's own Bluetooth auto-switch is in charge.
    private func handleServiceRestart() {
        healOutputUID = lastRealOutputUID
        // A headset takes 2-10 s to come back after coreaudiod restarts.
        healDeadline = now().advanced(by: .seconds(15))
        handleRestart()
    }

    /// The units and the device listener are stale; `reconcile` rebuilds them on the next pass.
    /// Not private: the wake notification cannot be delivered synchronously in tests.
    func handleRestart() {
        restarted = true
        scheduleReconcile()
    }

    /// Puts the input back where the user had it before the lock ever moved it.
    /// Runs on unlock and on quit — a force-kill (SIGKILL) cannot be handled, so nothing runs then.
    func shutdown() {
        engine.stop()
        refresh()
        restorePreviousInput()   // the keys stay: on the next launch the lock is still on
    }

    private func restorePreviousInput() {
        guard let uid = defaults.string(forKey: "previousInputUID"),
              let dev = devices.first(where: { $0.uid == uid && $0.hasInput }) else { return }
        attempt("Could not restore the previous input", { try audio.setDefaultInput(dev.id) })
        if let level = defaults.object(forKey: "previousInputVolume") as? Float {
            attempt("Could not restore the previous input volume", { try audio.setVolume(dev.id, scope: .input, level) })
        }
    }

    /// A user decision about the lock ends any pause from a fight with another app.
    private func clearLockFight() {
        lockReverts = []
        if status == Self.lockPaused { status = "" }
    }

    // Bluetooth connects fire a burst of events; run once after the burst.
    private func scheduleReconcile() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.reconcile() }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
    }

    // MARK: rules — idempotent, safe to call at any time

    func reconcile() {
        if restarted {
            restarted = false
            engine.stop()          // the units point at devices that no longer exist
            runningToken = nil
            runningWatched = nil   // force a fresh registration even on an unchanged id
        }
        refresh()
        trackRealOutput()
        healOutputAfterRestart()
        migrateLegacy()
        keepCallsOffSystemOutput()
        reconcileInputLock()
        refresh()
        outputVolume = defaultOutputID.flatMap { audio.volume($0, scope: .output) }
        callsInUse = callsDevice.map { audio.isRunningSomewhere($0.id) } ?? false
        reconcileEngine()
        watchRunning()
    }

    /// A call app opening CallLane fires no system-level event, so watch the device itself.
    /// A coreaudiod restart is NOT guaranteed to change the device id, so the id alone cannot
    /// tell us the listener died: `reconcile` clears `runningWatched` on the restart event.
    private func watchRunning() {
        guard callsDevice?.id != runningWatched else { return }
        // This may run inside the old token's own listener block; CoreAudio deadlocks if the
        // block is removed from within itself, so let it return first.
        if let old = runningToken { DispatchQueue.main.async { _ = old } }
        runningToken = nil
        runningWatched = nil
        guard let calls = callsDevice else { return }
        runningToken = audio.listen(calls.id, kAudioDevicePropertyDeviceIsRunningSomewhere) { [weak self] in self?.reconcile() }
        if runningToken != nil { runningWatched = calls.id }   // a failed registration retries next reconcile
    }

    private func refresh() {
        devices = audio.devices()
        defaultOutputID = audio.defaultOutput()
        defaultInputID = audio.defaultInput()
        tapID = audio.deviceID(forUID: Self.tapUID)   // hidden: never trust the device list for it
        driverVersion = audio.driverVersion()
    }

    /// Remembers the user's real output. A change of real output also clears any old message:
    /// that is when the user has acted on it.
    private func trackRealOutput() {
        // Both halves matter: a restart can move a device to a new id, and it can hand an old id
        // to a different device.
        guard let id = defaultOutputID, let dev = outputs.first(where: { $0.id == id }),
              id != lastRealOutput || dev.uid != lastRealOutputUID else { return }
        // The first change after a restart is macOS landing on the speaker — that is what we heal.
        // A second one is a person, in the menu or in System Settings; their pick wins.
        if let heal = healOutputUID, lastRealOutputUID != heal { healOutputUID = nil }
        lastRealOutput = id
        lastRealOutputUID = dev.uid
        status = ""
    }

    /// Puts the user's output back once, after a coreaudiod restart moved it. `healOutputUID` was
    /// captured at restart time, before the pass that saw the built-in speaker, so this never
    /// re-arms itself. Absent device: still waiting — the devices listener brings us back.
    private func healOutputAfterRestart() {
        guard let uid = healOutputUID else { return }
        guard now() <= healDeadline else { healOutputUID = nil; return }   // by now the user may have picked something else
        guard let dev = outputs.first(where: { $0.uid == uid }) else { return }
        guard defaultOutputID != dev.id else { healOutputUID = nil; return }   // macOS put it back itself
        // A write that failed keeps its turn: CoreAudio is flaky right after a restart. Nothing
        // else guarantees another event, so drive the retry from here; the deadline bounds it.
        guard attempt("Could not restore output after restart", { try audio.setDefaultOutput(dev.id) }) else {
            scheduleReconcile()
            return
        }
        healOutputUID = nil
        // This IS the user's real output now; without it the next pass reads our own write as a
        // change of output and wipes the message.
        lastRealOutput = dev.id
        lastRealOutputUID = dev.uid
        status = "Output put back to \(dev.name) after an audio restart."
    }

    /// Runs one CoreAudio write that enforces an app invariant. A failure is never silent:
    /// it lands in `status` for the menu and in the log.
    @discardableResult
    private func attempt(_ what: String, _ op: () throws -> Void) -> Bool {
        do { try op(); return true } catch {
            status = "\(what): \(error)"
            log.error("\(what): \(String(describing: error))")
            return false
        }
    }

    private var fallbackOutput: AudioDevice? {
        outputs.first { $0.id == lastRealOutput } ?? outputs.first
    }

    /// v0.1 created an aggregate device with this UID. Next to the driver's device it would
    /// only confuse the pickers, so destroy it. Move the system output off it first.
    private func migrateLegacy() {
        guard let old = devices.first(where: { $0.uid == Self.legacyUID && $0.isAggregate }) else { return }
        if defaultOutputID == old.id {
            guard let real = fallbackOutput,
                  attempt("Could not leave the old CallLane device", { try audio.setDefaultOutput(real.id) }) else { return }
        }
        attempt("Could not remove the old CallLane device", { try audio.destroyAggregate(old.id) })
    }

    /// CallLane must never be the system output: the engine would copy the device into itself.
    private func keepCallsOffSystemOutput() {
        guard let calls = callsDevice, defaultOutputID == calls.id else { return }
        guard let real = fallbackOutput else {
            status = "CallLane is the system output and no other output exists."
            return
        }
        if attempt("Could not leave CallLane", { try audio.setDefaultOutput(real.id) }) {
            status = "CallLane is for call apps only. Output set back to \(real.name)."
        }
    }

    private func requestMicrophoneIfNeeded() {
        guard audio.microphoneAllowed() == nil, !microphoneRequested else { return }
        microphoneRequested = true
        audio.requestMicrophone { [weak self] in self?.reconcile() }
    }

    /// Copies the tap onto the real output while a call app uses CallLane; stops when idle,
    /// when the route is not usable, or when microphone access is missing. The engine
    /// restarts on its own when the destination changes.
    private func reconcileEngine() {
        guard let route = engineRoute() else {
            engine.stop()
            return
        }
        let what = "Could not start the audio engine"
        if attempt(what, { try engine.start(tap: route.tap, destination: route.destination) }),
           status.hasPrefix(what) || status == Self.microphoneDenied {
            status = ""
        }
    }

    /// The pair the engine should run on right now, or nil when it must be stopped.
    private func engineRoute() -> (tap: AudioObjectID, destination: AudioObjectID)? {
        guard callsInUse, let tap = tapID, let out = defaultOutputID, out != callsDevice?.id else { return nil }
        switch audio.microphoneAllowed() {
        case true?: return (tap, out)
        case false?: status = Self.microphoneDenied; return nil
        case nil: requestMicrophoneIfNeeded(); return nil
        }
    }

    private func reconcileInputLock() {
        guard let uid = defaults.string(forKey: "lockedInputUID"),
              let locked = devices.first(where: { $0.uid == uid && $0.hasInput }) else { return }
        // Already right: leave the volume alone so the user can set the gain in System Settings.
        guard defaultInputID != locked.id else { return }
        // Teams and Zoom re-pick the input on every call start; without a cap the two of us
        // ping-pong forever. More than 3 reverts within 5 s means a fight, not a user.
        lockReverts.removeAll { Date().timeIntervalSince($0) > 5 }
        guard lockReverts.count < 3 else {
            status = Self.lockPaused
            return
        }
        // Only a revert that landed counts as a round of the fight: a CoreAudio write that
        // failed must keep retrying with its own error visible, not hide behind the pause.
        guard attempt("Could not lock input to \(locked.name)", { try audio.setDefaultInput(locked.id) }) else { return }
        lockReverts.append(Date())
        // The app that took the device usually took its gain too; put that back in the same pass.
        let level = defaults.object(forKey: "lockedInputVolume") as? Float ?? 1
        if let current = audio.volume(locked.id, scope: .input), abs(current - level) > 0.01 {
            attempt("Could not restore input volume", { try audio.setVolume(locked.id, scope: .input, level) })
        }
    }

    // MARK: user actions

    func selectOutput(_ id: AudioObjectID) {
        healOutputUID = nil   // an explicit pick outranks any restart still waiting for its device
        try? audio.setDefaultOutput(id)
        reconcile()
    }

    func selectInput(_ id: AudioObjectID) {
        try? audio.setDefaultInput(id)
        if inputLocked, let dev = devices.first(where: { $0.id == id }) {
            defaults.set(dev.uid, forKey: "lockedInputUID")
            defaults.set(audio.volume(id, scope: .input) ?? 1, forKey: "lockedInputVolume")
        }
        clearLockFight()
        reconcile()
    }

    func setOutputVolume(_ value: Float) {
        guard let id = defaultOutputID else { return }
        try? audio.setVolume(id, scope: .output, value)
        outputVolume = audio.volume(id, scope: .output)
    }
}
