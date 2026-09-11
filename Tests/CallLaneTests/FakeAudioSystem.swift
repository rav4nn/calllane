import CoreAudio
@testable import CallLane

final class FakeAudioSystem: AudioSystem {
    var list: [AudioDevice] = []
    var defaultOut: AudioObjectID?
    var defaultIn: AudioObjectID?
    var volumes: [AudioObjectID: Float] = [:]
    var inputVolumes: [AudioObjectID: Float] = [:]
    var running: Set<AudioObjectID> = []
    var nextID: AudioObjectID = 1000
    var handlers: [AudioObjectID: [AudioObjectPropertySelector: () -> Void]] = [:]
    var failSetDefaultInput = false
    var installedDriverVersion: String? = "0.2.0"

    @discardableResult
    func addDevice(_ name: String, uid: String, input: Bool = false, output: Bool = true, transport: UInt32 = 0) -> AudioObjectID {
        nextID += 1
        list.append(AudioDevice(id: nextID, uid: uid, name: name, transport: transport, hasInput: input, hasOutput: output))
        return nextID
    }
    func remove(_ id: AudioObjectID) { list.removeAll { $0.id == id } }

    func devices() -> [AudioDevice] { list }
    func defaultOutput() -> AudioObjectID? { defaultOut }
    func defaultInput() -> AudioObjectID? { defaultIn }
    func setDefaultOutput(_ id: AudioObjectID) throws { defaultOut = id }
    func setDefaultInput(_ id: AudioObjectID) throws {
        if failSetDefaultInput { throw AudioError(what: "set default input", status: -1) }
        defaultIn = id
    }
    func volume(_ id: AudioObjectID, scope: AudioScope) -> Float? {
        scope == .output ? volumes[id] : inputVolumes[id]
    }
    func setVolume(_ id: AudioObjectID, scope: AudioScope, _ value: Float) throws {
        if scope == .output { volumes[id] = value } else { inputVolumes[id] = value }
    }
    func isRunningSomewhere(_ id: AudioObjectID) -> Bool { running.contains(id) }
    func deviceID(forUID uid: String) -> AudioObjectID? { list.first { $0.uid == uid }?.id }
    func driverVersion() -> String? { installedDriverVersion }
    func destroyAggregate(_ id: AudioObjectID) throws { remove(id) }
    func listen(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ handler: @escaping () -> Void) -> ListenerToken? {
        handlers[object, default: [:]][selector] = handler
        return ListenerToken.fake()
    }
}
