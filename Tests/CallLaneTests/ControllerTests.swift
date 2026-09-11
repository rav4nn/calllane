import Testing
import Foundation
import CoreAudio
@testable import CallLane

@Suite struct ControllerTests {
    let fake = FakeAudioSystem()
    let defaults: UserDefaults
    let speakers: AudioObjectID
    let airpods: AudioObjectID
    let mic: AudioObjectID

    init() {
        let suite = "dev.rav4nn.calllane.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        speakers = fake.addDevice("Speakers", uid: "spk")
        airpods = fake.addDevice("AirPods", uid: "ap:out")
        mic = fake.addDevice("Mac Mic", uid: "mic", input: true, output: false)
        fake.defaultOut = airpods
        fake.defaultIn = mic
        fake.inputVolumes[mic] = 1.0
    }

    func makeController() -> Controller {
        let c = Controller(audio: fake, defaults: defaults)
        c.reconcile()
        return c
    }

    @Test func createsCallsAroundDefaultOutput() {
        let c = makeController()
        #expect(c.callsDevice?.name == "Calls")
        #expect(c.callsWraps?.id == airpods)
        #expect(!c.outputs.contains { $0.uid == Controller.callsUID }, "Calls is hidden from the output picker")
    }

    @Test func callsFollowsDefaultOutput() {
        let c = makeController()
        fake.defaultOut = speakers
        c.reconcile()
        #expect(c.callsWraps?.id == speakers)
    }

    @Test func callsAsDefaultOutputReverts() {
        let c = makeController()
        let calls = c.callsDevice!.id
        fake.defaultOut = calls
        c.reconcile()
        #expect(fake.defaultOut == airpods)
        #expect(c.status.contains("call apps only"))
    }

    @Test func inputLockRevertsAndRestoresVolume() {
        let c = makeController()
        c.inputLocked = true
        let btMic = fake.addDevice("AirPods", uid: "ap:in", input: true, output: false)
        fake.defaultIn = btMic
        fake.inputVolumes[mic] = 0.3
        c.reconcile()
        #expect(fake.defaultIn == mic)
        #expect(fake.inputVolumes[mic] == 1.0)
    }

    @Test func inputLockIgnoresAbsentDevice() {
        let c = makeController()
        c.inputLocked = true
        let usb = fake.addDevice("USB", uid: "usb", input: true, output: false)
        fake.remove(mic)
        fake.defaultIn = usb
        c.reconcile()
        #expect(fake.defaultIn == usb)
    }

    @Test func staleCallsAsDefaultFallsBackToAnyRealOutput() {
        let c = makeController()
        let calls = c.callsDevice!.id
        fake.remove(airpods)                 // wrapped device unplugged
        fake.defaultOut = calls              // and Calls became the system output
        c.reconcile()
        #expect(fake.defaultOut == speakers)
        #expect(c.status.contains("call apps only"))
    }

    @Test func inputLockFailureIsVisible() {
        let c = makeController()
        c.inputLocked = true
        let btMic = fake.addDevice("AirPods", uid: "ap:in", input: true, output: false)
        fake.defaultIn = btMic
        fake.failSetDefaultInput = true
        c.reconcile()
        #expect(fake.defaultIn == btMic)
        #expect(c.status.contains("Could not lock input"))
    }

    @Test func removeCallsDeviceWhileDefaultRestoresRealOutput() {
        let c = makeController()
        fake.defaultOut = c.callsDevice!.id
        #expect(c.removeCallsDevice())
        #expect(fake.defaultOut == airpods)
        #expect(fake.list.first { $0.uid == Controller.callsUID } == nil)
    }

    @Test func removeCallsDevice() {
        let c = makeController()
        c.removeCallsDevice()
        #expect(fake.list.first { $0.uid == Controller.callsUID } == nil)
    }

    @Test func callStartFlipsInUseWithoutPanelOpen() {
        let c = makeController()
        c.start()
        let calls = c.callsDevice!.id
        let fire = fake.handlers[calls]?[kAudioDevicePropertyDeviceIsRunningSomewhere]
        #expect(fire != nil, "running listener is registered on the Calls device itself")
        #expect(!c.callsInUse)
        fake.running.insert(calls)
        fire?()
        #expect(c.callsInUse)
        fake.running.remove(calls)
        fire?()
        #expect(!c.callsInUse)
    }

    @Test func recreatedCallsGetsAFreshRunningListener() {
        let c = makeController()
        c.start()
        let old = c.callsDevice!.id
        fake.aggregates[old] = nil
        fake.remove(old)
        c.reconcile()
        let new = c.callsDevice!.id
        #expect(new != old)
        #expect(fake.handlers[new]?[kAudioDevicePropertyDeviceIsRunningSomewhere] != nil)
    }
}
