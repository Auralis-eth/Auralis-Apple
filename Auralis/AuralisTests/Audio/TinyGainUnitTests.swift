import Testing
@testable import Auralis
import Foundation
import AVFoundation


@Suite("TinyGainUnit render behavior")
struct TinyGainUnitTests {
    private func makeABL(frames: UInt32, channels: UInt32) -> (UnsafeMutablePointer<AudioBufferList>, UnsafeMutablePointer<Float>) {
        let bytes = Int(frames * channels * 4)
        let data = UnsafeMutablePointer<Float>.allocate(capacity: bytes / 4)
        data.initialize(repeating: 1.0, count: bytes / 4)

        let abl = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        abl.pointee.mNumberBuffers = 1
        let buffer = UnsafeMutableAudioBufferListPointer(abl)
        buffer[0].mNumberChannels = channels
        buffer[0].mDataByteSize = UInt32(bytes)
        buffer[0].mData = UnsafeMutableRawPointer(data)
        return (abl, data)
    }

    private func destroyABL(_ abl: UnsafeMutablePointer<AudioBufferList>, data: UnsafeMutablePointer<Float>) {
        data.deallocate()
        abl.deallocate()
    }

    @Test("immediate gain scales samples")
    func testImmediateGain() throws {
        let unit = TinyGainUnit()
        unit.setLinearGain(0.5)
        let au = unit.auAudioUnit
        let block = au.internalRenderBlock

        let frames: UInt32 = 64
        let channels: UInt32 = 1
        let (abl, data) = makeABL(frames: frames, channels: channels)
        defer { destroyABL(abl, data: data) }

        var flags: AudioUnitRenderActionFlags = []
        var ts = AudioTimeStamp()
        ts.mFlags = .init(rawValue: 0)
        ts.mHostTime = 0

        let status = block(&flags, &ts, frames, 0, abl, nil) { _, _, _, _, outData in
            // Fill input with 1.0s
            let buffers = UnsafeMutableAudioBufferListPointer(outData)
            if let ptr = buffers[0].mData?.assumingMemoryBound(to: Float.self) {
                for i in 0..<(Int(frames)) { ptr[i] = 1.0 }
            }
            return noErr
        }
        #expect(status == noErr)
        // Assert scaled
        let count = Int(frames)
        for i in 0..<count { #expect(abs(data[i] - 0.5) < 0.0001) }
    }

    @Test("scheduled ramp reaches target after duration")
    func testScheduledRamp() throws {
        let unit = TinyGainUnit()
        unit.setLinearGain(0.0)
        let au = unit.auAudioUnit
        let block = au.internalRenderBlock

        // Schedule ramp to 1.0 over 0.1s starting at hostTime=1e9 ns
        let startHT: UInt64 = 1_000_000_000
        unit.scheduleLinearRamp(to: 1.0, duration: 0.1, atHostTime: startHT)

        let frames: UInt32 = 64
        let channels: UInt32 = 1
        let (abl, data) = makeABL(frames: frames, channels: channels)
        defer { destroyABL(abl, data: data) }

        var flags: AudioUnitRenderActionFlags = []
        var ts = AudioTimeStamp()
        ts.mFlags = .init(rawValue: 0)

        // First render before start time: expect ~0 gain
        ts.mHostTime = startHT - 100_000_000 // 0.1s before
        _ = block(&flags, &ts, frames, 0, abl, nil) { _, _, _, _, outData in
            let buffers = UnsafeMutableAudioBufferListPointer(outData)
            if let ptr = buffers[0].mData?.assumingMemoryBound(to: Float.self) {
                for i in 0..<(Int(frames)) { ptr[i] = 1.0 }
            }
            return noErr
        }
        for i in 0..<Int(frames) { #expect(abs(data[i] - 0.0) < 0.0001) }

        // Render after end time: expect ~1.0 gain
        ts.mHostTime = startHT + 200_000_000 // 0.2s after
        _ = block(&flags, &ts, frames, 0, abl, nil) { _, _, _, _, outData in
            let buffers = UnsafeMutableAudioBufferListPointer(outData)
            if let ptr = buffers[0].mData?.assumingMemoryBound(to: Float.self) {
                for i in 0..<(Int(frames)) { ptr[i] = 1.0 }
            }
            return noErr
        }
        for i in 0..<Int(frames) { #expect(abs(data[i] - 1.0) < 0.0001) }
    }
}
