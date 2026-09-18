import Testing
import Foundation
import CoreAudio
@testable import CallLane

@Suite struct ControllerTests {
    let fake = FakeAudioSystem()
    let engine = FakeEngine()
    let defaults: UserDefaults
    let speakers: AudioObjectID
    let airpods: AudioObjectID
    let mic: AudioObjectID
    let calls: AudioObjectID
    let tap: AudioObjectID

    init() {
        let suite = "dev.rav4nn.calllane.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        speakers = fake.addDevice("Speakers", uid: "spk")
        airpods = fake.addDevice("AirPods", uid: "ap:out")
        mic = fake.addDevice("Mac Mic", uid: "mic", input: true, output: false)
        calls = fake.addDevice("CallLane", uid: Controller.callsUID, transport: kAudioDeviceTransportTypeUSB)
        tap = fake.addDevice("CallLane Tap", uid: Controller.tapUID, input: true, output: false, transport: kAudioDeviceTransportTypeUSB)
        fake.defaultOut = airpods
        fake.defaultIn = mic
        fake.inputVolumes[mic] = 1.0
    }

    func makeController(appVersion: String = "0.2.0") -> Controller {
        let c = Controller(audio: fake, engine: engine, defaults: defaults, appVersion: appVersion)
        c.reconcile()
        return c
    }

    // MARK: pickers

    @Test func hidesOwnDevicesFromPickers() {
        let c = makeController()
        #expect(c.callsDevice?.id == calls)
        #expect(!c.outputs.contains { $0.id == calls })
        #expect(!c.inputs.contains { $0.id == tap })
        #expect(c.defaultOutputDevice?.id == airpods)
    }

    // MARK: CallLane must never be the system output

    @Test func callsAsDefaultOutputRevertsToPreviousOutput() {
        let c = makeController()
        fake.defaultOut = calls
        c.reconcile()
        #expect(fake.defaultOut == airpods)
        #expect(c.status.contains("call apps only"))
    }

    @Test func callsAsDefaultFallsBackToAnyRealOutputWhenPreviousIsGone() {
        let c = makeController()
        fake.remove(airpods)
        fake.defaultOut = calls
        c.reconcile()
        #expect(fake.defaultOut == speakers)
    }

    @Test func statusClearsWhenTheUserPicksAnotherOutput() {
        let c = makeController()
        fake.defaultOut = calls
        c.reconcile()
        #expect(!c.status.isEmpty)
        c.selectOutput(speakers)
        #expect(c.status.isEmpty)
    }

    // MARK: migration from the v0.1 aggregate

    @Test func migrationDestroysTheOldAggregate() {
        let old = fake.addDevice("CallLane", uid: Controller.legacyUID, transport: kAudioDeviceTransportTypeAggregate)
        let c = makeController()
        #expect(fake.list.first { $0.id == old } == nil)
        #expect(c.callsDevice?.id == calls)
    }

    @Test func migrationMovesTheOutputOffTheOldAggregateFirst() {
        let old = fake.addDevice("CallLane", uid: Controller.legacyUID, transport: kAudioDeviceTransportTypeAggregate)
        fake.defaultOut = old
        _ = makeController()
        #expect(fake.defaultOut == speakers || fake.defaultOut == airpods)
        #expect(fake.list.first { $0.id == old } == nil)
    }

    @Test func migrationIgnoresAForeignDeviceWithTheOldUID() {
        let usb = fake.addDevice("Odd", uid: Controller.legacyUID, transport: kAudioDeviceTransportTypeUSB)
        _ = makeController()
        #expect(fake.list.first { $0.id == usb } != nil, "only aggregates are destroyed")
    }

    // MARK: driver check

    @Test func driverPresentAndCurrentHasNoDriverStatus() {
        #expect(makeController().driverStatus == nil)
    }

    @Test func missingDriverSetsDriverStatus() {
        fake.remove(calls)
        fake.remove(tap)
        let c = makeController()
        #expect(c.driverStatus?.hasPrefix("Driver not installed.") == true)
        #expect(c.driverStatus?.contains("make install-driver") == true)
    }

    @Test func missingTapAloneCountsAsMissingDriver() {
        fake.remove(tap)
        #expect(makeController().driverStatus?.hasPrefix("Driver not installed.") == true)
    }

    @Test func olderDriverAsksForReinstall() {
        fake.installedDriverVersion = "0.1.0"
        let c = makeController(appVersion: "0.2.0")
        #expect(c.driverStatus == "Driver is v0.1.0, app is v0.2.0. Reinstall the cask.")
    }

    @Test func newerDriverIsFine() {
        fake.installedDriverVersion = "0.10.0"
        #expect(makeController(appVersion: "0.2.0").driverStatus == nil)
    }

    // MARK: engine lifecycle

    @Test func engineStartsOnInUseAndStopsOnIdle() {
        let c = makeController()
        #expect(engine.running == nil)
        fake.running.insert(calls)
        c.reconcile()
        #expect(c.callsInUse)
        #expect(engine.running?.tap == tap)
        #expect(engine.running?.destination == airpods)
        fake.running.remove(calls)
        c.reconcile()
        #expect(!c.callsInUse)
        #expect(engine.running == nil)
    }

    @Test func engineFollowsTheDefaultOutputWhileInUse() {
        let c = makeController()
        fake.running.insert(calls)
        c.reconcile()
        fake.defaultOut = speakers
        c.reconcile()
        #expect(engine.running?.destination == speakers)
        #expect(engine.starts == 2)
    }

    @Test func engineDoesNotStartWithoutATap() {
        fake.remove(tap)
        let c = makeController()
        fake.running.insert(calls)
        c.reconcile()
        #expect(engine.running == nil)
    }

    @Test func engineFailureIsVisibleAndClearsOnSuccess() {
        let c = makeController()
        engine.failStart = true
        fake.running.insert(calls)
        c.reconcile()
        #expect(c.status.contains("Could not start the audio engine"))
        engine.failStart = false
        c.reconcile()
        #expect(c.status.isEmpty)
        #expect(engine.running != nil)
    }

    // MARK: microphone permission (macOS feeds zeros without it)

    @Test func microphoneIsRequestedOnceAtStartAndEngineWaitsForTheAnswer() {
        fake.micAllowed = nil
        let c = makeController()
        c.start()
        #expect(fake.micRequests == 1)
        fake.running.insert(calls)
        c.reconcile()
        #expect(engine.running == nil, "no engine before the user answers")
        #expect(fake.micRequests == 1, "one prompt, not one per reconcile")
        fake.micAllowed = true
        fake.pendingMic?()
        #expect(engine.running != nil)
    }

    @Test func deniedMicrophoneIsVisibleAndClearsWhenGranted() {
        fake.micAllowed = false
        let c = makeController()
        fake.running.insert(calls)
        c.reconcile()
        #expect(engine.running == nil)
        #expect(c.status == Controller.microphoneDenied)
        fake.micAllowed = true
        c.reconcile()
        #expect(engine.running != nil)
        #expect(c.status.isEmpty)
    }

    @Test func revokedMicrophoneStopsARunningEngine() {
        let c = makeController()
        fake.running.insert(calls)
        c.reconcile()
        #expect(engine.running != nil)
        fake.micAllowed = false
        c.reconcile()
        #expect(engine.running == nil)
        #expect(c.status == Controller.microphoneDenied)
    }

    // MARK: in-use listener

    @Test func callStartFlipsInUseWithoutPanelOpen() {
        let c = makeController()
        c.start()
        let fire = fake.handlers[calls]?[kAudioDevicePropertyDeviceIsRunningSomewhere]
        #expect(fire != nil, "running listener is registered on the CallLane device itself")
        #expect(!c.callsInUse)
        fake.running.insert(calls)
        fire?()
        #expect(c.callsInUse)
        #expect(engine.running != nil)
        fake.running.remove(calls)
        fire?()
        #expect(!c.callsInUse)
        #expect(engine.running == nil)
    }

    @Test func reloadedDriverGetsAFreshRunningListener() {
        let c = makeController()
        c.start()
        fake.remove(calls)                       // coreaudiod restarted: new object ids
        fake.remove(tap)
        let newCalls = fake.addDevice("CallLane", uid: Controller.callsUID, transport: kAudioDeviceTransportTypeUSB)
        fake.addDevice("CallLane Tap", uid: Controller.tapUID, input: true, output: false, transport: kAudioDeviceTransportTypeUSB)
        c.reconcile()
        #expect(newCalls != calls)
        #expect(fake.handlers[newCalls]?[kAudioDevicePropertyDeviceIsRunningSomewhere] != nil)
    }

    @Test func coreaudiodRestartRebuildsEverythingEvenWithUnchangedIDs() {
        let c = makeController()
        c.start()
        fake.running.insert(calls)
        c.reconcile()
        #expect(engine.running?.tap == tap)
        let (starts, stops) = (engine.starts, engine.stops)
        let listens = fake.runningListenerRegistrations(calls)

        fake.restartService()   // ids stay exactly as they are
        c.reconcile()           // the debounced pass the restart handler asks for
        #expect(engine.stops == stops + 1, "the old units are torn down")
        #expect(engine.starts == starts + 1, "and rebuilt on the same pair")
        #expect(engine.running?.tap == tap)
        #expect(engine.running?.destination == airpods)
        #expect(fake.runningListenerRegistrations(calls) == listens + 1)

        // the flag clears: a plain reconcile does not tear the engine down again
        let after = engine.stops
        c.reconcile()
        #expect(engine.stops == after)
    }

    // MARK: input lock

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

    @Test func inputLockFailureIsVisible() {
        let c = makeController()
        c.inputLocked = true
        let btMic = fake.addDevice("AirPods", uid: "ap:in", input: true, output: false)
        fake.defaultIn = btMic
        fake.failSetDefaultInput = true
        for _ in 0..<4 { c.reconcile() }
        #expect(fake.defaultIn == btMic)
        #expect(c.status.contains("Could not lock input"), "a failing write keeps retrying, it is not a fight")
    }

    @Test func inputLockPausesWhenAnotherAppFightsBack() {
        let c = makeController()
        c.inputLocked = true
        let btMic = fake.addDevice("AirPods", uid: "ap:in", input: true, output: false)
        var reverts = 0
        for _ in 0..<4 {                       // a call app grabbing the input, four times over
            fake.defaultIn = btMic
            c.reconcile()
            if fake.defaultIn == mic { reverts += 1 }
        }
        #expect(reverts == 3)
        #expect(fake.defaultIn == btMic, "the fourth deviation stands")
        #expect(c.status.hasPrefix("Lock input paused"))

        c.inputLocked = false                  // off/on is the documented way out
        c.inputLocked = true
        #expect(c.status.isEmpty)
        fake.defaultIn = btMic
        c.reconcile()
        #expect(fake.defaultIn == mic, "reverts resume after the toggle")
    }

    @Test func inputLockLeavesTheGainAloneWhileTheDeviceIsRight() {
        let c = makeController()
        c.inputLocked = true                   // saves mic at 1.0
        fake.inputVolumes[mic] = 0.4           // the user turns it down in System Settings
        c.reconcile()
        #expect(fake.inputVolumes[mic] == 0.4)

        let btMic = fake.addDevice("AirPods", uid: "ap:in", input: true, output: false)
        fake.defaultIn = btMic                 // now an app takes the device and its gain
        fake.inputVolumes[mic] = 0.1
        c.reconcile()
        #expect(fake.defaultIn == mic)
        #expect(fake.inputVolumes[mic] == 1.0)
    }

    // MARK: quit and unlock restore what the user had

    @Test func shutdownRestoresThePreviousInputAndVolume() {
        fake.inputVolumes[mic] = 0.7
        let c = makeController()
        c.inputLocked = true
        let usb = fake.addDevice("USB Mic", uid: "usb", input: true, output: false)
        fake.inputVolumes[usb] = 0.2
        c.reconcile()                          // the picker only offers devices the app has seen
        c.selectInput(usb)
        #expect(fake.defaultIn == usb)

        c.shutdown()
        #expect(fake.defaultIn == mic)
        #expect(fake.inputVolumes[mic] == 0.7)
        #expect(defaults.string(forKey: "previousInputUID") == "mic", "the lock is still on next launch")

        c.inputLocked = false
        #expect(defaults.string(forKey: "previousInputUID") == nil)
        #expect(defaults.object(forKey: "previousInputVolume") as? Float == nil)
    }
}
