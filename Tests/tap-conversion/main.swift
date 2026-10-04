import CoreAudio
import Foundation

func format(planar: Bool) -> AudioStreamBasicDescription {
    AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | (planar ? kAudioFormatFlagIsNonInterleaved : 0),
        mBytesPerPacket: planar ? 4 : 8, mFramesPerPacket: 1, mBytesPerFrame: planar ? 4 : 8,
        mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
}

func convert(_ samples: [[Float]], planar: Bool,
             mutate: (UnsafeMutableAudioBufferListPointer) -> Void = { _ in }) throws -> [Float] {
    let list = AudioBufferList.allocate(maximumBuffers: samples.count)
    defer { free(list.unsafeMutablePointer) }
    var allocations: [UnsafeMutablePointer<Float>] = []
    defer { allocations.forEach { $0.deallocate() } }
    for (index, values) in samples.enumerated() {
        let memory = UnsafeMutablePointer<Float>.allocate(capacity: max(1, values.count))
        memory.initialize(from: values, count: values.count)
        allocations.append(memory)
        list[index] = AudioBuffer(mNumberChannels: planar ? 1 : 2,
                                 mDataByteSize: UInt32(values.count * 4), mData: memory)
    }
    mutate(list)
    return try TapAudioConversion.mono(list.unsafePointer, format: format(planar: planar))
}

func rejects(_ action: () throws -> [Float]) {
    do { _ = try action(); fatalError("Expected malformed block rejection") }
    catch { }
}
let interleaved = try convert([[1, 0, -1, 0, 0.25, 0.75]], planar: false)
let planar = try convert([[1, -1, 0.25], [0, 0, 0.75]], planar: true)
precondition(interleaved == [0.5, -0.5, 0.5] && planar == interleaved)
let silence = try convert([[0, 0]], planar: false)
precondition(silence == [0])
rejects { try convert([[1, 0, 1]], planar: false) }
rejects { try convert([[1, 0], [0]], planar: true) }
rejects { try convert([[1, 0]], planar: true) }
rejects { try convert([[]], planar: false) }
rejects { try convert([[1, 0]], planar: false) { $0[0].mData = nil } }
rejects { try convert([[1, 0]], planar: false) { $0[0].mNumberChannels = 1 } }
rejects { try convert([[1, 0]], planar: false) { $0[0].mDataByteSize = 3 } }
rejects { try convert([[1, 0]], planar: false) { $0[0].mDataByteSize = UInt32((TapAudioConversion.maximumFrames + 1) * 8) } }
for bad: Float in [.nan, .infinity, -.infinity] {
    rejects { try convert([[0, bad]], planar: false) }
    rejects { try convert([[0], [bad]], planar: true) }
}
let largest = try convert([[Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude]], planar: false)
precondition(largest[0] == Float.greatestFiniteMagnitude)
print("Tap audio conversion checks passed")

// HAL timestamps must advertise both clocks and have a lossless Int64 position.
var timestamp = AudioTimeStamp()
timestamp.mFlags = [.sampleTimeValid, .hostTimeValid]
timestamp.mSampleTime = 4096
timestamp.mHostTime = 1
precondition(try! TapAudioConversion.samplePosition(timestamp) == 4096)
for invalid in [Double.nan, Double.infinity, -Double.infinity, 0.5, Double(Int64.max), Double(Int64.min) - 2048] {
    timestamp.mSampleTime = invalid
    do {
        _ = try TapAudioConversion.samplePosition(timestamp)
        preconditionFailure("Unsafe sample position accepted")
    } catch { }
}
timestamp.mSampleTime = 0
for flags: AudioTimeStampFlags in [[], .sampleTimeValid, .hostTimeValid] {
    timestamp.mFlags = flags
    do {
        _ = try TapAudioConversion.samplePosition(timestamp)
        preconditionFailure("Missing timestamp validity flag accepted")
    } catch { }
}
print("Tap timestamp checks passed")
