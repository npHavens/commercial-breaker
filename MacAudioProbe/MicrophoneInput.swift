import AVFoundation
import Foundation
import Darwin

/// Owns an input-only engine. Stop before changing sources or releasing the recorder.
@MainActor
final class MicrophoneInput {
    private var engine: AVAudioEngine?
    private var delivery: MicrophoneDelivery?
    private var configurationObserver: NSObjectProtocol?
    private var attempt: UUID?

    /// Delivers owned mono Float32 chunks on the main actor. The timestamp is the audio buffer end in monotonic uptime.
    func start(onAudio: @escaping ([Float], Double, Double) -> Void,
               onFailure: @escaping (String) -> Void) async throws {
        guard attempt == nil else { throw failure("Microphone capture is already starting or running.") }
        let id = UUID()
        attempt = id
        do {
            let allowed: Bool
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: allowed = true
            case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .audio)
            default: allowed = false
            }
            // Stop can run while the system permission dialog is open.
            try Task.checkCancellation()
            guard attempt == id else { throw CancellationError() }
            guard allowed else {
                throw failure("Microphone access was denied. Enable Skybox in System Settings → Privacy & Security → Microphone.")
            }

            let engine = AVAudioEngine()
            let input = engine.inputNode
            let hardware = input.inputFormat(forBus: 0)
            let format = input.outputFormat(forBus: 0)
            guard hardware.sampleRate > 0, hardware.channelCount > 0,
                  format.commonFormat == .pcmFormatFloat32,
                  format.sampleRate.isFinite, (8_000...192_000).contains(format.sampleRate),
                  (1...8).contains(Int(format.channelCount)) else {
                throw failure("Microphone has no supported input format (requires Float32 PCM, 8–192 kHz, 1–8 channels).")
            }
            let delivery = MicrophoneDelivery(onAudio: onAudio) { [weak self] message in
                guard let self, self.attempt == id else { return }
                self.stop()
                onFailure(message)
            }
            self.engine = engine
            self.delivery = delivery
            input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, time in
                delivery.consume(buffer, time: time)
            }
            configurationObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.attempt == id else { return }
                    self.stop()
                    onFailure("Microphone configuration changed. Capture stopped; choose the intended input and start again.")
                }
            }
            engine.prepare()
            try engine.start()
        } catch {
            // A newer start must not be stopped by completion of an older permission request.
            if attempt == id { stop() }
            throw error
        }
    }

    func stop() {
        attempt = nil
        delivery?.invalidate()
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        if let engine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        engine = nil
        delivery = nil
    }

    deinit {
        delivery?.invalidate()
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "CommercialBreakerMicrophone", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

/// Bridges the engine callback to the main queue with a bounded backlog. No AVAudioPCMBuffer
/// escapes its callback lifetime. Mutable delivery state is protected by the lock.
private final class MicrophoneDelivery: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    private var failureQueued = false
    private var pending = 0
    private var sampleClock: AudioSampleClock
    private let onAudio: @MainActor ([Float], Double, Double) -> Void
    private let onFailure: @MainActor (String) -> Void
    private let maximumFrames = 16_384
    private let maximumPending = 8

    init(onAudio: @escaping @MainActor ([Float], Double, Double) -> Void,
         onFailure: @escaping @MainActor (String) -> Void) {
        self.onAudio = onAudio
        self.onFailure = onFailure
        sampleClock = AudioSampleClock(
            hostNowSeconds: AVAudioTime.seconds(forHostTime: mach_absolute_time()),
            uptimeNow: ProcessInfo.processInfo.systemUptime)
    }

    func invalidate() {
        lock.lock()
        active = false
        lock.unlock()
    }

    func consume(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        lock.lock()
        guard active, !failureQueued else { lock.unlock(); return }
        guard pending < maximumPending else {
            lock.unlock()
            fail("Microphone processing fell behind. Capture stopped instead of silently losing audio.")
            return
        }
        pending += 1
        lock.unlock()

        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        let rate = buffer.format.sampleRate
        guard frames > 0 else { releasePending(); return }
        guard frames <= maximumFrames, (1...8).contains(channels),
              buffer.format.commonFormat == .pcmFormatFloat32,
              rate.isFinite, (8_000...192_000).contains(rate),
              let data = buffer.floatChannelData else {
            releasePending()
            fail("Microphone supplied an unsupported or oversized audio buffer.")
            return
        }
        guard time.isSampleTimeValid, time.isHostTimeValid,
              time.sampleRate == rate else {
            releasePending()
            fail("Microphone supplied no usable audio sample/host timestamp.")
            return
        }
        let endUptime: Double
        do {
            lock.lock()
            defer { lock.unlock() }
            endUptime = try sampleClock.endUptime(sampleTime: time.sampleTime,
                hostSeconds: AVAudioTime.seconds(forHostTime: time.hostTime),
                frameCount: frames, sampleRate: rate)
        } catch {
            releasePending()
            fail("Microphone supplied an invalid audio timestamp.")
            return
        }
        let stride = buffer.format.isInterleaved ? channels : 1
        var mono = [Float](repeating: 0, count: frames)
        for frame in 0..<frames {
            var sum: Double = 0
            for channel in 0..<channels {
                let sample = buffer.format.isInterleaved
                    ? data[0][frame * stride + channel]
                    : data[channel][frame]
                guard sample.isFinite else {
                    releasePending()
                    fail("Microphone supplied a nonfinite audio sample.")
                    return
                }
                sum += Double(sample)
            }
            let value = Float(sum / Double(channels))
            guard value.isFinite else {
                releasePending()
                fail("Microphone channel mixing produced a nonfinite sample.")
                return
            }
            mono[frame] = value
        }
        DispatchQueue.main.async { [self, mono] in
            lock.lock()
            let shouldDeliver = active && !failureQueued
            pending -= 1
            lock.unlock()
            if shouldDeliver { onAudio(mono, rate, endUptime) }
        }
    }

    private func releasePending() {
        lock.lock()
        pending -= 1
        lock.unlock()
    }

    private func fail(_ message: String) {
        lock.lock()
        guard active, !failureQueued else { lock.unlock(); return }
        failureQueued = true
        lock.unlock()
        DispatchQueue.main.async { [self] in
            lock.lock()
            let shouldDeliver = active
            lock.unlock()
            if shouldDeliver { onFailure(message) }
        }
    }
}
