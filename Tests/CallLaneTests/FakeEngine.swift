import CoreAudio
@testable import CallLane

final class FakeEngine: EngineControl {
    var running: (tap: AudioObjectID, destination: AudioObjectID)?
    var starts = 0
    var stops = 0
    var failStart = false

    func start(tap: AudioObjectID, destination: AudioObjectID) throws {
        if failStart { throw AudioError(what: "start engine", status: -1) }
        if let r = running, r.tap == tap, r.destination == destination { return }
        running = (tap, destination)
        starts += 1
    }

    func stop() { running = nil; stops += 1 }
}
