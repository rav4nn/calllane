import Testing
import AudioToolbox
import CoreAudio
import Foundation
@testable import CallLane

/// Needs the CallLane driver (`make install-driver`). Plays a tone into CallLane, copies the tap
/// onto the built-in speakers at volume zero, and checks that audio arrived.
@Suite(.enabled(if: FileManager.default.fileExists(atPath: CoreAudioSystem.driverPlist)))
struct EngineTests {
    @Test func copiesTapOntoDestination() throws {
        let audio = CoreAudioSystem()
        let calls = try #require(audio.deviceID(forUID: "CallLane_UID"))
        let tap = try #require(audio.deviceID(forUID: "CallLane_2_UID"))
        let speakers = try #require(audio.devices().first { $0.transport == kAudioDeviceTransportTypeBuiltIn && $0.hasOutput })

        let savedVolume = audio.volume(speakers.id, scope: .output)
        try audio.setVolume(speakers.id, scope: .output, 0)
        defer { if let v = savedVolume { try? audio.setVolume(speakers.id, scope: .output, v) } }

        let tone = try Tone(device: calls)
        defer { tone.stop() }
        let engine = Engine()
        defer { engine.stop() }

        try engine.start(tap: tap, destination: speakers.id)
        #expect(engine.current?.destination == speakers.id)
        Thread.sleep(forTimeInterval: 0.5)
        #expect(engine.ring.peak > 0.1, "the tap delivered the tone")

        try engine.start(tap: tap, destination: speakers.id)   // same pair: no restart
        #expect(engine.current != nil)
        engine.stop()
        #expect(engine.current == nil)
    }
}

/// Plays a 440 Hz sine at half scale into one output device. Test support only.
final class Tone {
    private var unit: AudioUnit?
    fileprivate var phase: Float = 0

    init(device: AudioObjectID) throws {
        var desc = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_HALOutput,
                                             componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        var made: AudioUnit?
        AudioComponentInstanceNew(AudioComponentFindNext(nil, &desc)!, &made)
        let unit = try #require(made)
        self.unit = unit
        var dev = device
        var format = Engine.format
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &dev, 4)
        AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        var cb = AURenderCallbackStruct(inputProc: toneRender, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &cb, UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        let initStatus = AudioUnitInitialize(unit)
        #expect(initStatus == noErr)
        let startStatus = AudioOutputUnitStart(unit)
        #expect(startStatus == noErr)
    }

    func stop() {
        if let u = unit { AudioOutputUnitStop(u); AudioUnitUninitialize(u); AudioComponentInstanceDispose(u) }
        unit = nil
    }
}

private func toneRender(_ ref: UnsafeMutableRawPointer, _: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                        _: UnsafePointer<AudioTimeStamp>, _: UInt32, _ frames: UInt32,
                        _ io: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
    let tone = Unmanaged<Tone>.fromOpaque(ref).takeUnretainedValue()
    guard let p = io?.pointee.mBuffers.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
    for i in 0..<Int(frames) {
        let v = 0.5 * sin(tone.phase)
        p[i * 2] = v
        p[i * 2 + 1] = v
        tone.phase += 2 * .pi * 440 / 48000
    }
    return noErr
}
