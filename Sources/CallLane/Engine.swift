import AudioToolbox
import CoreAudio
import Foundation

protocol EngineControl: AnyObject {
    /// Copies `tap` onto `destination`. A second call with the same pair is a no-op; a
    /// different pair stops the current copy first.
    func start(tap: AudioObjectID, destination: AudioObjectID) throws
    func stop()
}

/// Single-producer single-consumer ring of interleaved stereo Float32 frames.
/// The producer is the tap's input callback, the consumer the destination's render callback.
/// ponytail: NSLock around a copy of at most 512 floats; a lock-free ring needs the
/// Synchronization module (macOS 15) or a C atomics shim. Upgrade if a glitch is ever traced here.
final class Ring {
    let capacity: Int
    let dropAbove: Int
    let dropTo: Int
    private let buf: UnsafeMutablePointer<Float>
    private let lock = NSLock()
    private var head = 0     // next frame to write
    private var count = 0    // frames waiting to be read
    private var peakValue: Float = 0

    init(capacity: Int = 4096, dropAbove: Int = 512, dropTo: Int = 256) {
        self.capacity = capacity
        self.dropAbove = dropAbove
        self.dropTo = dropTo
        buf = .allocate(capacity: capacity * 2)
        buf.initialize(repeating: 0, count: capacity * 2)
    }

    deinit { buf.deallocate() }

    var available: Int { lock.lock(); defer { lock.unlock() }; return count }
    /// Loudest sample seen since the last `reset()`. Read under the lock: the capture callback
    /// writes it from the IO thread.
    var peak: Float { lock.lock(); defer { lock.unlock() }; return peakValue }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        head = 0; count = 0; peakValue = 0
    }

    /// Appends frames. When the ring is full the oldest frames are overwritten.
    func push(_ p: UnsafePointer<Float>, frames: Int) {
        lock.lock(); defer { lock.unlock() }
        for i in 0..<frames {
            let f = (head + i) % capacity
            buf[f * 2] = p[i * 2]
            buf[f * 2 + 1] = p[i * 2 + 1]
            peakValue = max(peakValue, abs(p[i * 2]), abs(p[i * 2 + 1]))
        }
        head = (head + frames) % capacity
        count = min(capacity, count + frames)
    }

    /// Fills `frames` frames: the oldest waiting frames first, zeros for the rest.
    /// A backlog above `dropAbove` is cut to `dropTo` first, so the added delay stays bounded.
    /// Returns the number of real frames written.
    @discardableResult
    func pop(into p: UnsafeMutablePointer<Float>, frames: Int) -> Int {
        lock.lock(); defer { lock.unlock() }
        if count > dropAbove { count = dropTo }
        let got = min(count, frames)
        var tail = (head - count + capacity) % capacity
        for i in 0..<got {
            p[i * 2] = buf[tail * 2]
            p[i * 2 + 1] = buf[tail * 2 + 1]
            tail = (tail + 1) % capacity
        }
        for i in got..<frames {
            p[i * 2] = 0
            p[i * 2 + 1] = 0
        }
        count -= got
        return got
    }
}

/// Copies audio from the hidden CallLane tap device onto the real output.
/// Two HAL output units: the input unit reads the tap, the output unit writes the destination.
/// AVAudioEngine cannot do this on macOS: it owns one I/O unit for both directions.
final class Engine: EngineControl {
    static let bufferFrames: UInt32 = 128
    static let maxFrames = 4096
    static let format = AudioStreamBasicDescription(
        mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
        mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8,
        mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)

    let ring = Ring()
    private(set) var current: (tap: AudioObjectID, destination: AudioObjectID)?
    private var inUnit: AudioUnit?
    private var outUnit: AudioUnit?
    private let inBuf = UnsafeMutablePointer<Float>.allocate(capacity: Engine.maxFrames * 2)

    deinit {
        stop()
        inBuf.deallocate()
    }

    func start(tap: AudioObjectID, destination: AudioObjectID) throws {
        if let c = current {
            if c.tap == tap && c.destination == destination { return }
            stop()
        }
        let input = try makeUnit()
        let output = try makeUnit()
        inUnit = input
        outUnit = output
        do {
            var on: UInt32 = 1, off: UInt32 = 0
            var tapID = tap, dstID = destination
            var frames = Self.bufferFrames
            var format = Self.format
            let fmtSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            let cbSize = UInt32(MemoryLayout<AURenderCallbackStruct>.size)
            let me = Unmanaged.passUnretained(self).toOpaque()

            try check(AudioUnitSetProperty(input, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &on, 4), "enable tap input")
            try check(AudioUnitSetProperty(input, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &off, 4), "disable tap output")
            try check(AudioUnitSetProperty(input, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &tapID, 4), "select tap")
            try check(AudioUnitSetProperty(input, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &format, fmtSize), "tap format")
            try check(AudioUnitSetProperty(input, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0, &frames, 4), "tap buffer size")
            var inCB = AURenderCallbackStruct(inputProc: engineCapture, inputProcRefCon: me)
            try check(AudioUnitSetProperty(input, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &inCB, cbSize), "tap callback")

            try check(AudioUnitSetProperty(output, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &dstID, 4), "select output")
            try check(AudioUnitSetProperty(output, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, fmtSize), "output format")
            try check(AudioUnitSetProperty(output, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0, &frames, 4), "output buffer size")
            var outCB = AURenderCallbackStruct(inputProc: engineRender, inputProcRefCon: me)
            try check(AudioUnitSetProperty(output, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &outCB, cbSize), "output callback")

            try check(AudioUnitInitialize(input), "initialise tap unit")
            try check(AudioUnitInitialize(output), "initialise output unit")
            ring.reset()
            try check(AudioOutputUnitStart(output), "start output")
            try check(AudioOutputUnitStart(input), "start tap")
        } catch {
            stop()
            throw error
        }
        current = (tap, destination)
        log.info("engine: \(tap) -> \(destination)")
    }

    func stop() {
        let units = [inUnit, outUnit].compactMap { $0 }
        // Stop both IO procs before disposing either: `AudioOutputUnitStop` blocks until the
        // proc returns, so `capture` can no longer be inside `AudioUnitRender(inUnit)` when the
        // input unit goes away.
        for unit in units { AudioOutputUnitStop(unit) }
        for unit in units {
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
        }
        inUnit = nil
        outUnit = nil
        if current != nil { log.info("engine: stopped") }
        current = nil
    }

    // MARK: callbacks (IO thread)

    fileprivate func capture(_ flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, _ time: UnsafePointer<AudioTimeStamp>, _ bus: UInt32, _ frames: UInt32) -> OSStatus {
        guard let unit = inUnit, frames <= Self.maxFrames else { return noErr }
        var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: frames * 8, mData: inBuf))
        let status = AudioUnitRender(unit, flags, time, bus, frames, &list)
        if status == noErr { ring.push(inBuf, frames: Int(frames)) }
        return status
    }

    fileprivate func render(_ io: UnsafeMutablePointer<AudioBufferList>?, _ frames: UInt32) -> OSStatus {
        guard let data = io?.pointee.mBuffers.mData else { return noErr }
        ring.pop(into: data.assumingMemoryBound(to: Float.self), frames: Int(frames))
        return noErr
    }

    // MARK: helpers

    private func makeUnit() throws -> AudioUnit {
        var desc = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_HALOutput,
                                             componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &desc) else {
            throw AudioError(what: "find HAL output unit", status: kAudioUnitErr_InvalidElement)
        }
        var unit: AudioUnit?
        try check(AudioComponentInstanceNew(component, &unit), "create HAL output unit")
        return unit!
    }

    private func check(_ status: OSStatus, _ what: String) throws {
        if status != noErr { throw AudioError(what: what, status: status) }
    }
}

// C function pointers cannot capture; the engine travels through the refCon.
private func engineCapture(_ ref: UnsafeMutableRawPointer, _ flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                           _ time: UnsafePointer<AudioTimeStamp>, _ bus: UInt32, _ frames: UInt32,
                           _: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
    Unmanaged<Engine>.fromOpaque(ref).takeUnretainedValue().capture(flags, time, bus, frames)
}

private func engineRender(_ ref: UnsafeMutableRawPointer, _: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                          _: UnsafePointer<AudioTimeStamp>, _: UInt32, _ frames: UInt32,
                          _ io: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
    Unmanaged<Engine>.fromOpaque(ref).takeUnretainedValue().render(io, frames)
}
