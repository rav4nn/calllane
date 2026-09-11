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

        // coreaudiod publishes a new aggregate asynchronously: the create call can return
        // before the device list and the UID table know about it. Wait, up to a second.
        for _ in 0..<40 {
            if audio.deviceID(forUID: uid) != nil, audio.devices().contains(where: { $0.uid == uid }) { break }
            Thread.sleep(forTimeInterval: 0.025)
        }

        #expect(audio.deviceID(forUID: uid) == agg)
        #expect(audio.deviceID(forUID: "dev.rav4nn.calllane.no-such-device") == nil)
        #expect(audio.volume(agg, scope: .output) == nil, "aggregates have no volume control")
        #expect(audio.devices().contains { $0.uid == uid && $0.isAggregate })
        #expect(!audio.isRunningSomewhere(agg))
    }

    @Test func defaultDevicesResolve() {
        let audio = CoreAudioSystem()
        let ids = Set(audio.devices().map(\.id))
        if let o = audio.defaultOutput() { #expect(ids.contains(o)) }
        if let i = audio.defaultInput() { #expect(ids.contains(i)) }
    }

    @Test func driverVersionReadsTheInstalledPlist() throws {
        let plist = FileManager.default.temporaryDirectory.appendingPathComponent("calllane-\(uid).plist")
        defer { try? FileManager.default.removeItem(at: plist) }
        try (["CFBundleShortVersionString": "1.2.3"] as NSDictionary).write(to: plist)
        #expect(CoreAudioSystem(driverPlist: plist.path).driverVersion() == "1.2.3")
        #expect(CoreAudioSystem(driverPlist: "/nonexistent/Info.plist").driverVersion() == nil)
    }
}
