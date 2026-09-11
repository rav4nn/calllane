import CoreAudio
import Foundation
import Observation

@Observable
final class Controller {
    static let callsName = "CallLane"
    static let callsUID = "dev.rav4nn.calllane.calls"

    private let audio: AudioSystem
    private let defaults: UserDefaults
    private var tokens: [ListenerToken] = []
    private var runningToken: ListenerToken?
    private var runningWatched: AudioObjectID?
    private var pending: DispatchWorkItem?

    private(set) var devices: [AudioDevice] = []
    private(set) var defaultOutputID: AudioObjectID?
    private(set) var defaultInputID: AudioObjectID?
    private(set) var outputVolume: Float?
    private(set) var callsInUse = false
    private(set) var status = ""

    init(audio: AudioSystem, defaults: UserDefaults = .standard) {
        self.audio = audio
        self.defaults = defaults
    }

    // MARK: derived

    var outputs: [AudioDevice] { devices.filter { $0.hasOutput && $0.uid != Self.callsUID } }
    var inputs: [AudioDevice] { devices.filter { $0.hasInput } }
    var callsDevice: AudioDevice? { devices.first { $0.uid == Self.callsUID } }
    var callsWraps: AudioDevice? {
        guard let calls = callsDevice, let uid = audio.aggregateSubDeviceUID(calls.id) else { return nil }
        return devices.first { $0.uid == uid }
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
        reconcileCalls()
        reconcileInputLock()
        refresh()
        outputVolume = defaultOutputID.flatMap { audio.volume($0, scope: .output) }
        callsInUse = callsDevice.map { audio.isRunningSomewhere($0.id) } ?? false
        watchRunning()
    }

    /// A call app opening CallLane fires no system-level event, so watch the device itself.
    /// CallLane gets a new id whenever it is recreated; re-register when that happens.
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

    /// The real output CallLane should wrap, or the system should fall back to: the wrapped
    /// device when it is still present, else any real output device.
    private func realOutput(for calls: AudioDevice) -> AudioDevice? {
        if let uid = audio.aggregateSubDeviceUID(calls.id), let d = devices.first(where: { $0.uid == uid && $0.hasOutput }) {
            return d
        }
        return outputs.first
    }

    private func reconcileCalls() {
        guard let outID = defaultOutputID, let out = devices.first(where: { $0.id == outID }) else { return }
        guard let calls = callsDevice else {
            if attempt("Could not create CallLane", {
                _ = try audio.createAggregate(name: Self.callsName, uid: Self.callsUID, subDeviceUID: out.uid)
            }) { status = "" }
            return
        }
        if calls.name != Self.callsName {   // device created by an older version
            attempt("Could not rename \(calls.name)", { try audio.setName(calls.id, Self.callsName) })
        }
        if out.uid == Self.callsUID {
            // CallLane must never be the system output: the volume keys stop working.
            guard let real = realOutput(for: calls) else {
                status = "CallLane is the system output and no other output exists."
                return
            }
            if attempt("Could not leave CallLane", { try audio.setDefaultOutput(real.id) }) {
                status = "CallLane is for call apps only. Output set back to \(real.name)."
            }
            return
        }
        if audio.aggregateSubDeviceUID(calls.id) != out.uid {
            if attempt("Could not point CallLane at \(out.name)", { try audio.setAggregateSubDevice(calls.id, uid: out.uid) }) {
                status = ""
            }
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

    /// Moves the system output off CallLane first, then destroys it. Returns false and keeps
    /// CallLane when the output cannot be moved, so macOS never holds a destroyed default.
    @discardableResult
    func removeCallsDevice() -> Bool {
        refresh()
        guard let calls = callsDevice else { return true }
        if defaultOutputID == calls.id {
            guard let real = realOutput(for: calls),
                  attempt("Could not leave CallLane", { try audio.setDefaultOutput(real.id) }) else { return false }
        }
        let ok = attempt("Could not remove CallLane", { try audio.destroyAggregate(calls.id) })
        refresh()
        return ok
    }
}
