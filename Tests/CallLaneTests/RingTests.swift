import Testing
@testable import CallLane

/// Frames are interleaved stereo; each helper frame carries its index in both channels.
@Suite struct RingTests {
    func frames(_ range: Range<Int>) -> [Float] { range.flatMap { [Float($0), Float($0)] } }

    @Test func popReturnsOldestFirstAndZeroFillsTheRest() {
        let ring = Ring(capacity: 16, dropAbove: 8, dropTo: 4)
        var input = frames(0..<3)
        ring.push(&input, frames: 3)
        var out = [Float](repeating: 9, count: 8)
        #expect(ring.pop(into: &out, frames: 4) == 3)
        #expect(out == [0, 0, 1, 1, 2, 2, 0, 0])
        #expect(ring.available == 0)
    }

    @Test func popDropsBacklogAboveThreshold() {
        let ring = Ring(capacity: 16, dropAbove: 8, dropTo: 4)
        var input = frames(0..<10)
        ring.push(&input, frames: 10)          // 10 > 8: the next pop keeps only the newest 4
        var out = [Float](repeating: 9, count: 4)
        #expect(ring.pop(into: &out, frames: 2) == 2)
        #expect(out == [6, 6, 7, 7])
        #expect(ring.available == 2)
    }

    @Test func pushOverwritesOldestWhenFull() {
        let ring = Ring(capacity: 4, dropAbove: 100, dropTo: 100)
        var input = frames(0..<6)
        ring.push(&input, frames: 6)
        #expect(ring.available == 4)
        var out = [Float](repeating: 9, count: 8)
        #expect(ring.pop(into: &out, frames: 4) == 4)
        #expect(out == [2, 2, 3, 3, 4, 4, 5, 5])
    }

    @Test func peakTracksTheLoudestSampleUntilReset() {
        let ring = Ring()
        var input: [Float] = [0.1, -0.7, 0.2, 0.0]
        ring.push(&input, frames: 2)
        #expect(ring.peak == 0.7)
        ring.reset()
        #expect(ring.peak == 0)
        #expect(ring.available == 0)
    }
}
