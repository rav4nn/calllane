import CoreAudio
@testable import CallLane

final class FakeAudioSystem: AudioSystem {
    var list: [AudioDevice] = []
    var defaultOut: AudioObjectID?
    var defaultIn: AudioObjectID?
    var volumes: [AudioObjectID: Float] = [:]
    var inputVolumes: [AudioObjectID: Float] = [:]
    var running: Set<AudioObjectID> = []
    var aggregates: [AudioObjectID: String] = [:]   // agg id -> sub-device uid
    var nextID: AudioObjectID = 1000
    var handlers: [AudioObjectID: [AudioObjectPropertySelector: () -> Void]] = [:]
    var failSetDefaultInput = false

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
    func createAggregate(name: String, uid: String, subDeviceUID: String) throws -> AudioObjectID {
        let id = addDevice(name, uid: uid, transport: kAudioDeviceTransportTypeAggregate)
        aggregates[id] = subDeviceUID
        return id
    }
    func aggregateSubDeviceUID(_ id: AudioObjectID) -> String? { aggregates[id] }
    func setAggregateSubDevice(_ id: AudioObjectID, uid: String) throws { aggregates[id] = uid }
    func destroyAggregate(_ id: AudioObjectID) throws { aggregates[id] = nil; remove(id) }
    func listen(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ handler: @escaping () -> Void) -> ListenerToken? {
        handlers[object, default: [:]][selector] = handler
        return ListenerToken.fake()
    }
}
