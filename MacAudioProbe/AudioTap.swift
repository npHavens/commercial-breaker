import AVFoundation
import CoreAudio
import Foundation

/// Validates HAL Float32 layouts before averaging channels. A rejected block is
/// omitted entirely; it must never be mistaken for measured silence.
enum TapAudioConversion {
    static let maximumFrames = 65_536
    static let maximumChannels = 32

    static func samplePosition(_ timestamp: AudioTimeStamp) throws -> Int64 {
        guard timestamp.mFlags.contains(.sampleTimeValid),
              timestamp.mFlags.contains(.hostTimeValid),
              let position = Int64(exactly: timestamp.mSampleTime) else {
            throw AudioSampleClock.ClockError.invalidTimestamp
        }
        return position
    }

    static func mono(_ list: UnsafePointer<AudioBufferList>,
                     format: AudioStreamBasicDescription) throws -> [Float] {
        func invalid(_ detail: String) -> NSError {
            NSError(domain: "CommercialBreakerAudio", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Audio block rejected: \(detail)"])
        }
        let channels = Int(format.mChannelsPerFrame)
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mFormatFlags & kAudioFormatFlagIsPacked != 0,
              format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
              format.mBitsPerChannel == 32,
              format.mSampleRate.isFinite, format.mSampleRate > 0,
              channels > 0, channels <= maximumChannels else {
            throw invalid("unsupported format")
        }
        let planar = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let bufferCount = planar ? channels : 1
        guard Int(list.pointee.mNumberBuffers) == bufferCount else {
            throw invalid("buffer count does not match channel layout")
        }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        let bufferChannels = planar ? 1 : channels
        let bytesPerFrame = bufferChannels * MemoryLayout<Float>.size
        guard Int(format.mBytesPerFrame) == bytesPerFrame else {
            throw invalid("unexpected frame stride")
        }
        var frameCount: Int?
        for buffer in buffers {
            let bytes = Int(buffer.mDataByteSize)
            guard Int(buffer.mNumberChannels) == bufferChannels,
                  bytes > 0, bytes % bytesPerFrame == 0,
                  bytes / bytesPerFrame <= maximumFrames,
                  let data = buffer.mData,
                  Int(bitPattern: data) % MemoryLayout<Float>.alignment == 0 else {
                throw invalid("missing, oversized, or malformed channel data")
            }
            let frames = bytes / bytesPerFrame
            guard frameCount == nil || frameCount == frames else {
                throw invalid("channel lengths differ")
            }
            frameCount = frames
        }
        guard let count = frameCount else { throw invalid("empty block") }
        var output = [Float](repeating: 0, count: count)
        for frame in 0..<count {
            var sum = 0.0
            for channel in 0..<channels {
                let buffer = buffers[planar ? channel : 0]
                let pointer = buffer.mData!.assumingMemoryBound(to: Float.self)
                let value = pointer[planar ? frame : frame * channels + channel]
                guard value.isFinite else { throw invalid("nonfinite sample") }
                sum += Double(value)
            }
            output[frame] = Float(sum / Double(channels))
        }
        return output
    }
}

struct MeterReading {
    let callbacks: UInt64
    let samples: UInt64
    let invalidSamples: UInt64
    let malformedBuffers: UInt64
    let levels: AudioLevels?
}

private final class MeterBuffer {
    // Only accessed on AudioTap's serial audio queue.
    var accumulator = AudioLevelAccumulator()
    var callbacks: UInt64 = 0
    var malformedBuffers: UInt64 = 0

    func consume(_ list: UnsafePointer<AudioBufferList>) {
        callbacks += 1
        for buffer in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list)) {
            guard buffer.mDataByteSize > 0 else { continue }
            guard let data = buffer.mData,
                  buffer.mDataByteSize % UInt32(MemoryLayout<Float>.size) == 0 else {
                malformedBuffers += 1
                continue
            }
            let samples = UnsafeBufferPointer(
                start: data.assumingMemoryBound(to: Float.self),
                count: Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            )
            for sample in samples { accumulator.add(sample) }
        }
    }

    func takeReading() -> MeterReading {
        let reading = MeterReading(callbacks: callbacks, samples: accumulator.sampleCount,
                                   invalidSamples: accumulator.invalidSamples,
                                   malformedBuffers: malformedBuffers, levels: accumulator.levels)
        accumulator = AudioLevelAccumulator()
        callbacks = 0
        malformedBuffers = 0
        return reading
    }
}

struct AudioTapError: LocalizedError {
    let operation: String
    let status: OSStatus
    var errorDescription: String? { "\(operation) failed (Core Audio status \(status))." }
}

/// Control methods run on the main thread; samples stay on the serial audio queue.
final class AudioTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?
    private var description: CATapDescription?
    private let queue = DispatchQueue(label: "com.nohandsstack.skybox.audio-meter", qos: .userInteractive)
    private let meter = MeterBuffer()

    func start(initiallyMuted: Bool = false,
               onAudio: (([Float], Double, Double) -> Void)? = nil,
               onAudioError: ((String) -> Void)? = nil) throws -> AudioStreamBasicDescription {
        precondition(tapID == kAudioObjectUnknown && deviceID == kAudioObjectUnknown)
        do {
            let tap = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
            tap.name = "Commercial Breaker system audio probe"
            tap.uuid = UUID()
            tap.isPrivate = true
            tap.muteBehavior = initiallyMuted ? .mutedWhenTapped : .unmuted
            description = tap
            try check(AudioHardwareCreateProcessTap(tap, &tapID), "Create system audio tap")

            var format = AudioStreamBasicDescription()
            var address = property(kAudioTapPropertyFormat)
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try check(AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format), "Read tap format")
            guard format.mFormatID == kAudioFormatLinearPCM,
                  format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
                  format.mFormatFlags & kAudioFormatFlagIsPacked != 0,
                  format.mBitsPerChannel == 32,
                  format.mChannelsPerFrame > 0 else {
                throw AudioTapError(operation: "Unsupported tap format (requires native Float32 PCM)", status: kAudio_ParamError)
            }

            let aggregate: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Commercial Breaker private audio meter",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceIsPrivateKey: true,
                // Do not block starting when the source is silent.
                kAudioAggregateDeviceTapAutoStartKey: false,
                kAudioAggregateDeviceTapListKey: [[
                    kAudioSubTapUIDKey: tap.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true
                ]]
            ]
            try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &deviceID), "Create private aggregate")
            queue.sync { _ = self.meter.takeReading() }
            let meter = self.meter
            let captureFormat = format
            // This state, like MeterBuffer, is confined to the callback queue.
            let delivery = TapAudioDelivery(format: captureFormat, onAudio: onAudio, onError: onAudioError)
            try check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, deviceID, queue) { _, input, inputTime, _, _ in
                meter.consume(input)
                delivery.consume(input, timestamp: inputTime.pointee)
            }, "Install audio callback")
            try check(AudioDeviceStart(deviceID, ioProc), "Start audio capture")
            return format
        } catch {
            let cleanup = stop()
            if !cleanup.isEmpty {
                throw NSError(domain: "CommercialBreakerAudio", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "\(error.localizedDescription) Cleanup: \(cleanup.joined(separator: "; "))"
                ])
            }
            throw error
        }
    }

    func setMuted(_ muted: Bool) throws {
        guard tapID != kAudioObjectUnknown, let description else { return }
        description.muteBehavior = muted ? .mutedWhenTapped : .unmuted
        var address = property(kAudioTapPropertyDescription)
        // HAL expects the address of an Objective-C object pointer for this property.
        // The strong description reference keeps it alive for this synchronous call.
        var value = Unmanaged.passUnretained(description).toOpaque()
        try check(AudioObjectSetPropertyData(tapID, &address, 0, nil,
                                            UInt32(MemoryLayout<UnsafeMutableRawPointer>.size), &value), "Change tap mute behavior")
    }

    func takeReading() -> MeterReading { queue.sync { meter.takeReading() } }

    /// Best-effort complete teardown even when an earlier cleanup step fails.
    @discardableResult
    func stop() -> [String] {
        var errors: [String] = []
        func record(_ status: OSStatus, _ operation: String) {
            if status != noErr { errors.append(AudioTapError(operation: operation, status: status).localizedDescription) }
        }
        if tapID != kAudioObjectUnknown {
            do { try setMuted(false) } catch { errors.append(error.localizedDescription) }
        }
        if deviceID != kAudioObjectUnknown, let ioProc {
            record(AudioDeviceStop(deviceID, ioProc), "Stop capture")
            record(AudioDeviceDestroyIOProcID(deviceID, ioProc), "Remove callback")
        }
        ioProc = nil
        if deviceID != kAudioObjectUnknown {
            record(AudioHardwareDestroyAggregateDevice(deviceID), "Destroy aggregate")
            deviceID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            record(AudioHardwareDestroyProcessTap(tapID), "Destroy tap")
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        description = nil
        return errors
    }

    deinit { stop() }

    private func property(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private func check(_ status: OSStatus, _ operation: String) throws {
        if status != noErr { throw AudioTapError(operation: operation, status: status) }
    }
}

/// Optional sample delivery is separate from metering so diagnostics retain their
/// original behavior. Hardware input timestamps place samples on the same uptime
/// clock as microphone samples and user markers, preserving discontinuities.
private final class TapAudioDelivery {
    let format: AudioStreamBasicDescription
    let onAudio: (([Float], Double, Double) -> Void)?
    let onError: ((String) -> Void)?
    private var reportedError = false
    private var sampleClock: AudioSampleClock

    init(format: AudioStreamBasicDescription,
         onAudio: (([Float], Double, Double) -> Void)?, onError: ((String) -> Void)?) {
        self.format = format
        self.onAudio = onAudio
        self.onError = onError
        sampleClock = AudioSampleClock(
            hostNowSeconds: AVAudioTime.seconds(forHostTime: mach_absolute_time()),
            uptimeNow: ProcessInfo.processInfo.systemUptime
        )
    }

    func consume(_ list: UnsafePointer<AudioBufferList>, timestamp: AudioTimeStamp) {
        guard let onAudio else { return }
        do {
            let position = try TapAudioConversion.samplePosition(timestamp)
            let samples = try TapAudioConversion.mono(list, format: format)
            let endTime = try sampleClock.endUptime(
                sampleTime: position,
                hostSeconds: AVAudioTime.seconds(forHostTime: timestamp.mHostTime),
                frameCount: samples.count, sampleRate: format.mSampleRate
            )
            onAudio(samples, format.mSampleRate, endTime)
        } catch {
            if !reportedError {
                reportedError = true
                onError?(error.localizedDescription)
            }
        }
    }
}
