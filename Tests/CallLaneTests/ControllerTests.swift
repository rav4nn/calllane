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

    // MARK: a muted CallLane device is a silent call

    @Test func unmutesCallsDevice() {
        fake.muted.insert(calls)
        _ = makeController()
        #expect(!fake.muted.contains(calls))
    }

    @Test func unmutesCallsDeviceWhenMutedLater() {
        let c = makeController()
        fake.muted.insert(calls)
        fake.handlers[calls]?[kAudioDevicePropertyMute]?()
        #expect(!fake.muted.contains(calls))
        // The driver changes mute on the output scope; a global listener never fires.
        #expect(fake.listenLog.contains { $0.object == calls && $0.selector == kAudioDevicePropertyMute && $0.scope == kAudioObjectPropertyScopeOutput })
        withExtendedLifetime(c) {}   // the listener holds the controller weakly
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

    // MARK: the output comes back after a coreaudiod restart

    /// Install, upgrade and uninstall all run `killall coreaudiod`: the headset drops off for a
    /// moment and macOS lands the default output on the built-in speaker.
    private func restartWithAirPodsGone(_ c: Controller) {
        c.start()
        fake.remove(airpods)
        fake.defaultOut = speakers
        fake.restartService()
        c.reconcile()
        #expect(fake.outputSets.isEmpty, "nothing to put the output back to while the headset is away")
    }

    @Test func restartPutsTheOutputBackWhenTheHeadsetReturns() {
        let c = makeController()
        restartWithAirPodsGone(c)
        let returned = fake.addDevice("AirPods", uid: "ap:out")   // a new id, as after a real restart
        c.reconcile()
        #expect(fake.outputSets == [returned])
        #expect(fake.defaultOut == returned)
        #expect(c.status.hasPrefix("Output put back"))
        c.reconcile()
        #expect(c.status.hasPrefix("Output put back"), "our own write is not a user output change")
        #expect(fake.outputSets == [returned], "put back once, not on every pass")
    }

    @Test func restartPutsTheOutputBackWhenTheIDIsUnchanged() {
        let c = makeController()
        restartWithAirPodsGone(c)
        fake.reAddOutput("AirPods", uid: "ap:out", id: airpods)
        c.reconcile()
        #expect(fake.outputSets == [airpods])
    }

    @Test func aFailedRestoreKeepsTryingUntilTheDeadline() {
        let c = makeController()
        restartWithAirPodsGone(c)
        fake.failSetDefaultOutput = true
        let returned = fake.addDevice("AirPods", uid: "ap:out")
        c.reconcile()
        #expect(fake.defaultOut == speakers)
        #expect(c.status.hasPrefix("Could not restore output after restart"))
        fake.failSetDefaultOutput = false
        c.reconcile()
        #expect(fake.defaultOut == returned)
        #expect(c.status.hasPrefix("Output put back"))
    }

    @Test func pickingAnOutputDuringTheWaitCancelsTheHeal() {
        let c = makeController()
        restartWithAirPodsGone(c)
        c.selectOutput(speakers)                                  // the user decides, not us
        fake.outputSets = []
        fake.addDevice("AirPods", uid: "ap:out")
        c.reconcile()
        #expect(fake.outputSets.isEmpty)
        #expect(fake.defaultOut == speakers)
    }

    @Test func anOutputPickedOutsideTheAppDuringTheWaitCancelsTheHeal() {
        let c = makeController()
        restartWithAirPodsGone(c)
        let usb = fake.addDevice("USB Speakers", uid: "usb:out")
        fake.defaultOut = usb                                     // picked in System Settings
        c.reconcile()
        fake.addDevice("AirPods", uid: "ap:out")
        c.reconcile()
        #expect(fake.outputSets.isEmpty)
        #expect(fake.defaultOut == usb)
    }

    @Test func aReusedIDWithANewUIDCountsAsANewRealOutput() {
        let c = makeController()
        c.start()
        fake.remove(airpods)
        fake.reAddOutput("USB Speakers", uid: "usb:out", id: airpods)   // coreaudiod reuses the id
        c.reconcile()
        fake.remove(airpods)
        fake.defaultOut = speakers
        fake.restartService()
        c.reconcile()
        fake.addDevice("AirPods", uid: "ap:out")
        c.reconcile()
        #expect(fake.outputSets.isEmpty, "the heal wants the device that was really there, not the one that once had its id")
    }

    @Test func noSwitchWhenMacOSPutsTheOutputBackItself() {
        let c = makeController()
        restartWithAirPodsGone(c)
        fake.defaultOut = fake.addDevice("AirPods", uid: "ap:out")
        c.reconcile()
        #expect(fake.outputSets.isEmpty)
        #expect(c.status.isEmpty)
    }

    @Test func theHealGivesUpAfterFifteenSeconds() {
        var clock = ContinuousClock.now
        let c = Controller(audio: fake, engine: engine, defaults: defaults, appVersion: "0.2.0", now: { clock })
        c.reconcile()
        restartWithAirPodsGone(c)
        clock = clock.advanced(by: .seconds(16))                  // the user has had time to pick something else
        fake.addDevice("AirPods", uid: "ap:out")
        c.reconcile()
        #expect(fake.outputSets.isEmpty)
    }

    @Test func wakeDoesNotPutTheOutputBack() {
        let c = makeController()
        c.start()
        fake.remove(airpods)
        fake.defaultOut = speakers
        c.handleRestart()                                         // the wake path: macOS owns the switch
        c.reconcile()
        fake.addDevice("AirPods", uid: "ap:out")
        c.reconcile()
        #expect(fake.outputSets.isEmpty)
    }

    @Test func restartWithNoKnownRealOutputChangesNothing() {
        fake.defaultOut = nil
        let c = makeController()
        c.start()
        fake.restartService()
        c.reconcile()
        fake.addDevice("AirPods 2", uid: "ap2:out")
        c.reconcile()
        #expect(fake.outputSets.isEmpty)
        #expect(fake.defaultOut == nil)
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
