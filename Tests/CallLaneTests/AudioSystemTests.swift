import Testing
import Foundation
@testable import CallLane

@Suite struct AudioSystemTests {
    let uid = "dev.rav4nn.calllane.test-\(ProcessInfo.processInfo.processIdentifier)"

    @Test func aggregateLifecycle() throws {
        let audio = CoreAudioSystem()
        guard let out = audio.defaultOutput(),
              let outDevice = audio.devices().first(where: { $0.id == out }) else {
            Issue.record("no default output device on this Mac"); return
        }
        let agg = try audio.createAggregate(name: "CallLane Test", uid: uid, subDeviceUID: outDevice.uid)
        defer { try? audio.destroyAggregate(agg) }

        #expect(audio.aggregateSubDeviceUID(agg) == outDevice.uid)
        #expect(audio.volume(agg, scope: .output) == nil, "aggregates have no volume control")
        #expect(audio.devices().contains { $0.uid == uid && $0.isAggregate })

        // Rewrite to the same UID: must succeed and read back unchanged.
        try audio.setAggregateSubDevice(agg, uid: outDevice.uid)
        #expect(audio.aggregateSubDeviceUID(agg) == outDevice.uid)
        #expect(!audio.isRunningSomewhere(agg))
    }

    @Test func defaultDevicesResolve() {
        let audio = CoreAudioSystem()
        let ids = Set(audio.devices().map(\.id))
        if let o = audio.defaultOutput() { #expect(ids.contains(o)) }
        if let i = audio.defaultInput() { #expect(ids.contains(i)) }
    }
}
