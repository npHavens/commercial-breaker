import AVFoundation
import Foundation

/// A bounded, continuous audio window. Capture callbacks only validate and retain
/// chunks; conversion runs on the observer's background snapshot caller.
final class GeminiAudioBuffer: @unchecked Sendable {
    struct Snapshot: Sendable {
        let wavData: Data
        let startUptime: Double
        let endUptime: Double
    }

    private struct Chunk {
        let samples: [Float]
        let end: Double
    }
    private let lock = NSLock()
    private var chunks: [Chunk] = []
    private var sampleRate: Double?
    private var count = 0
    private var generation: UInt64 = 0

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        clear()
    }

    private func clear() {
        chunks.removeAll()
        sampleRate = nil
        count = 0
        generation &+= 1
    }

    /// At most ten seconds at 192 kHz, with each incoming block <= two seconds.
    /// Invalid input invalidates context, so a missing block cannot be concealed.
    func ingest(_ samples: [Float], sampleRate rate: Double, endedAt: Double) {
        lock.lock()
        defer { lock.unlock() }
        guard rate.isFinite, (8_000...192_000).contains(rate),
              endedAt.isFinite, endedAt >= 0, endedAt < 1e12,
              !samples.isEmpty, samples.count <= Int(rate * 2),
              samples.allSatisfy(\.isFinite) else {
            clear()
            return
        }
        let start = endedAt - Double(samples.count) / rate
        guard start >= 0 else { clear(); return }
        if let previous = chunks.last {
            // Permit rounding noise, but never stitch gaps or overlapping blocks.
            let tolerance = max(0.25 / rate, endedAt.ulp * 8)
            if sampleRate != rate || abs(start - previous.end) > tolerance {
                clear()
            }
        }
        sampleRate = rate
        chunks.append(Chunk(samples: samples, end: endedAt))
        count += samples.count
        let maximum = Int(rate * 10)
        while chunks.count > 2_048 || count > maximum {
            let excess = count - maximum
            if chunks.count <= 2_048, excess > 0, excess < chunks[0].samples.count {
                let first = chunks[0]
                chunks[0] = Chunk(samples: Array(first.samples.dropFirst(excess)), end: first.end)
                count -= excess
            } else {
                count -= chunks.removeFirst().samples.count
            }
        }
    }

    /// Call from a background queue. Audio more than two seconds old is unusable.
    func snapshot(now: Double = ProcessInfo.processInfo.systemUptime) -> Snapshot? {
        lock.lock()
        guard let rate = sampleRate, let end = chunks.last?.end,
              now.isFinite, now >= end, now - end <= 2,
              count >= Int((rate * 8).rounded()) else {
            lock.unlock()
            return nil
        }
        let capturedGeneration = generation
        let needed = Int((rate * 8).rounded())
        let retained = chunks
        lock.unlock()

        var samples = [Float]()
        samples.reserveCapacity(needed)
        var skip = retained.reduce(0) { $0 + $1.samples.count } - needed
        for chunk in retained {
            let omitted = min(skip, chunk.samples.count)
            samples.append(contentsOf: chunk.samples.dropFirst(omitted))
            skip -= omitted
        }
        guard let data = Self.wav(samples, rate: rate) else { return nil }
        lock.lock()
        let unchanged = generation == capturedGeneration
        lock.unlock()
        guard unchanged else { return nil }
        return Snapshot(wavData: data, startUptime: end - Double(needed) / rate, endUptime: end)
    }

    private static func wav(_ samples: [Float], rate: Double) -> Data? {
        guard let inputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate,
                                              channels: 1, interleaved: false),
              let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000,
                                               channels: 1, interleaved: false),
              let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 128_000),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat),
              let channel = input.floatChannelData?[0] else { return nil }
        input.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        // This is a complete finite window, not a streaming converter. Disabling
        // priming avoids reporting latency padding as part of the observed window.
        converter.primeMethod = .none
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if supplied { state.pointee = .endOfStream; return nil }
            supplied = true
            state.pointee = .haveData
            return input
        }
        guard status != .error, error == nil, output.frameLength == 128_000,
              let pcm = output.int16ChannelData?[0] else { return nil }
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func word(_ value: UInt16) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        func integer(_ value: UInt32) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        text("RIFF"); integer(36 + 256_000); text("WAVEfmt "); integer(16)
        word(1); word(1); integer(16_000); integer(32_000); word(2); word(16)
        text("data"); integer(256_000)
        for frame in 0..<128_000 { word(UInt16(bitPattern: pcm[frame])) }
        return data
    }
}
