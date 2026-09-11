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

    private let audio: AudioSystem
    private let engine: EngineControl
    private let defaults: UserDefaults
    private let appVersion: String
    private var tokens: [ListenerToken] = []
    private var runningToken: ListenerToken?
    private var runningWatched: AudioObjectID?
    private var pending: DispatchWorkItem?
    /// The last real output the user had; where the system output goes back to when CallLane
    /// must not stay the system output.
    private var lastRealOutput: AudioObjectID?
    private var tapID: AudioObjectID?
    private var driverVersion: String?
    private var microphoneRequested = false

    private(set) var devices: [AudioDevice] = []
    private(set) var defaultOutputID: AudioObjectID?
    private(set) var defaultInputID: AudioObjectID?
    private(set) var outputVolume: Float?
    private(set) var callsInUse = false
    private(set) var status = ""

    init(audio: AudioSystem, engine: EngineControl, defaults: UserDefaults = .standard,
         appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0") {
        self.audio = audio
        self.engine = engine
        self.defaults = defaults
        self.appVersion = appVersion
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
            } else {
                defaults.removeObject(forKey: "lockedInputUID")
            }
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
        refresh()
        trackRealOutput()
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
    /// The device gets a new id whenever coreaudiod restarts; re-register when that happens.
    private func watchRunning() {
        guard callsDevice?.id != runningWatched else { return }
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
        guard let id = defaultOutputID, outputs.contains(where: { $0.id == id }), id != lastRealOutput else { return }
        lastRealOutput = id
        status = ""
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
        if defaultInputID != locked.id {
            attempt("Could not lock input to \(locked.name)", { try audio.setDefaultInput(locked.id) })
        }
        let level = defaults.object(forKey: "lockedInputVolume") as? Float ?? 1
        if let current = audio.volume(locked.id, scope: .input), abs(current - level) > 0.01 {
            attempt("Could not restore input volume", { try audio.setVolume(locked.id, scope: .input, level) })
        }
    }

    // MARK: user actions

    func selectOutput(_ id: AudioObjectID) {
        try? audio.setDefaultOutput(id)
        reconcile()
    }

    func selectInput(_ id: AudioObjectID) {
        try? audio.setDefaultInput(id)
        if inputLocked, let dev = devices.first(where: { $0.id == id }) {
            defaults.set(dev.uid, forKey: "lockedInputUID")
            defaults.set(audio.volume(id, scope: .input) ?? 1, forKey: "lockedInputVolume")
        }
        reconcile()
    }

    func setOutputVolume(_ value: Float) {
        guard let id = defaultOutputID else { return }
        try? audio.setVolume(id, scope: .output, value)
        outputVolume = audio.volume(id, scope: .output)
    }
}
