import AVFoundation
import Foundation

/// Local diagnostic recordings only. Missing audio is described in metadata,
/// never synthesized as silence or mistaken for a continuous recording.
final class AudioClipStore: @unchecked Sendable {
    private struct Chunk {
        let samples: [Float]
        let rate: Double
        let end: Double
        var start: Double { end - Double(samples.count) / rate }
    }
    private struct Pending {
        let label: String
        let marker: Double
        let droppedAtMarker: Int
        var chunks: [Chunk]
    }
    private let queue = DispatchQueue(label: "com.nohandsstack.skybox.audio-clips", qos: .utility)
    private let lock = NSLock()
    private var queued = 0
    private var stopped = false
    private var dropped = 0
    private let directory: URL
    private let source: String
    private let onEvent: @Sendable (String) -> Void
    private let epoch = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
    private var ring: [Chunk] = []
    private var pending: [Pending] = []
    private var rate: Double?
    private var lastEnd: Double?
    private var sequence = 0

    init(directory: URL, source: String,
         onEvent: @escaping @Sendable (String) -> Void = { _ in }) throws {
        self.directory = directory
        self.source = source
        self.onEvent = onEvent
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        queue.async { [self] in event("Capture session started", at: ProcessInfo.processInfo.systemUptime) }
    }

    /// At most eight queued blocks, each at most two seconds at <=192 kHz.
    func ingest(_ samples: [Float], sampleRate: Double, endedAt: Double) {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        guard sampleRate.isFinite, sampleRate >= 8_000, sampleRate <= 192_000,
              endedAt.isFinite, endedAt >= 0, endedAt < 1e12, !samples.isEmpty,
              samples.count <= Int(sampleRate * 2), queued < 8 else {
            dropped += 1
            lock.unlock()
            return
        }
        queued += 1
        queue.async { [self] in
            defer { lock.lock(); queued -= 1; lock.unlock() }
            guard samples.allSatisfy(\.isFinite) else {
                lock.lock(); dropped += 1; lock.unlock()
                event("Rejected nonfinite audio block", at: endedAt)
                return
            }
            consume(Chunk(samples: samples, rate: sampleRate, end: endedAt))
        }
        lock.unlock()
    }

    func mark(_ label: String, at: Double = ProcessInfo.processInfo.systemUptime) {
        lock.lock()
        guard !stopped, at.isFinite, at >= 0, at < 1e12 else { lock.unlock(); return }
        queue.async { [self] in
            if label == "Changed game" || label == "Changed channel" {
                flush(reason: "channel changed")
                ring.removeAll(); lastEnd = nil
                event(label, at: at)
                return
            }
            guard pending.count < 4 else {
                event("Marker skipped: four clips already pending", at: at)
                return
            }
            let chunks = ring.filter { $0.end > at - 20 && $0.start < at + 10 }
            pending.append(Pending(label: label, marker: at, droppedAtMarker: dropCount(), chunks: chunks))
            event("Marked \(label); collecting ten seconds after marker", at: at)
            finishReady(at: lastEnd ?? at)
        }
        lock.unlock()
    }

    /// Synchronous: every accepted block and marker is handled before returning.
    /// Call from the UI/control thread, never from onEvent.
    func stop() {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        stopped = true
        lock.unlock()
        queue.sync {
            flush(reason: "capture stopped")
            event("Capture session stopped", at: ProcessInfo.processInfo.systemUptime)
            ring.removeAll()
            lastEnd = nil
            rate = nil
        }
    }

    private func consume(_ chunk: Chunk) {
        if let rate, rate != chunk.rate {
            flush(reason: "sample rate changed")
            ring.removeAll(); lastEnd = nil
            event("Sample rate changed from \(rate) to \(chunk.rate); context reset", at: chunk.end)
        }
        let firstFormat = rate == nil
        rate = chunk.rate
        if firstFormat { event("Receiving mono audio at \(chunk.rate) Hz", at: chunk.end) }
        if let lastEnd, chunk.start < lastEnd - 0.1 {
            flush(reason: "audio timestamp moved backwards")
            ring.removeAll()
            self.lastEnd = nil
            event("Audio timestamp moved backwards; context reset", at: chunk.end)
        }
        if let lastEnd, chunk.end <= lastEnd {
            event("Nonadvancing audio block omitted", at: chunk.end)
            return
        }
        lastEnd = chunk.end
        ring.append(chunk)
        ring.removeAll { $0.end <= chunk.end - 30 }
        bound(&ring, rate: chunk.rate)
        for index in pending.indices {
            if chunk.end > pending[index].marker - 20 && chunk.start < pending[index].marker + 10 {
                pending[index].chunks.append(chunk)
                bound(&pending[index].chunks, rate: chunk.rate)
            }
        }
        finishReady(at: chunk.end)
    }

    private func bound(_ chunks: inout [Chunk], rate: Double) {
        var samples = chunks.reduce(0) { $0 + $1.samples.count }
        while chunks.count > 2_048 || samples > Int(rate * 32) {
            samples -= chunks.removeFirst().samples.count
        }
    }

    private func finishReady(at time: Double) {
        let ready = pending.filter { time >= $0.marker + 10 }
        pending.removeAll { time >= $0.marker + 10 }
        ready.forEach { save($0, reason: "post-roll complete") }
    }

    private func flush(reason: String) {
        let clips = pending
        pending.removeAll()
        clips.forEach { save($0, reason: reason) }
    }

    private func save(_ clip: Pending, reason: String) {
        let start = clip.marker - 20
        let end = clip.marker + 10
        var selected: [(Chunk, Range<Int>)] = []
        var cursor = start
        var gaps: [[String: Double]] = []
        var frames = 0
        for chunk in clip.chunks {
            // Subtracting large uptime values can put an exact frame boundary a few
            // millionths of a sample past its integer. Avoid dropping that frame.
            let tolerance = min(0.01, max(chunk.start.ulp, start.ulp, cursor.ulp, end.ulp) * chunk.rate * 4)
            func snap(_ position: Double) -> Double {
                let nearest = position.rounded()
                return abs(position - nearest) <= tolerance ? nearest : position
            }
            let first = max(0, Int(ceil(snap((max(start, cursor) - chunk.start) * chunk.rate))))
            let last = min(chunk.samples.count, Int(floor(snap((end - chunk.start) * chunk.rate))))
            guard first < last else { continue }
            let actualStart = chunk.start + Double(first) / chunk.rate
            let actualEnd = chunk.start + Double(last) / chunk.rate
            if actualStart - cursor > 0.02 {
                gaps.append(["startUptime": cursor, "endUptime": actualStart])
            }
            selected.append((chunk, first..<last))
            frames += last - first
            cursor = actualEnd
        }
        if end - cursor > 0.02 { gaps.append(["startUptime": cursor, "endUptime": end]) }
        sequence += 1
        let stem = "clip-\(Int((epoch + clip.marker) * 1000))-\(sequence)"
        let wavURL = directory.appendingPathComponent(stem + ".wav")
        do {
            let sampleRate = selected.first?.0.rate
            if let sampleRate {
                let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
                let file = try AVAudioFile(forWriting: wavURL, settings: format.settings,
                                           commonFormat: .pcmFormatFloat32, interleaved: false)
                for (chunk, range) in selected {
                    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(range.count))!
                    buffer.frameLength = buffer.frameCapacity
                    chunk.samples.withUnsafeBufferPointer { data in
                        buffer.floatChannelData![0].update(from: data.baseAddress! + range.lowerBound, count: range.count)
                    }
                    try file.write(from: buffer)
                }
            }
            let metadata: [String: Any] = [
                "source": source, "label": clip.label, "markerUptime": clip.marker,
                "markerUnixSeconds": epoch + clip.marker, "requestedStartUptime": start,
                "requestedEndUptime": end, "preRollSeconds": 20, "postRollSeconds": 10,
                "sampleRate": sampleRate as Any? ?? NSNull(), "frames": frames,
                "wav": frames > 0 ? stem + ".wav" : NSNull(),
                "completionReason": reason, "partial": !gaps.isEmpty,
                "missingIntervals": gaps, "droppedBlocksTotal": dropCount(),
                "droppedBlocksAtMarker": clip.droppedAtMarker,
                "timingNote": "Microphone timing uses the audio sample clock anchored to host time; system audio uses callback uptime. WAV concatenates available samples; missing intervals are omitted."
            ]
            try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent(stem + ".json"), options: .atomic)
            onEvent("Saved \(clip.label): \(frames) samples\(gaps.isEmpty ? "" : " (partial audio)") · \(stem)")
        } catch { onEvent("Clip save failed: \(error.localizedDescription)") }
    }

    private func dropCount() -> Int {
        lock.lock(); defer { lock.unlock() }; return dropped
    }

    private func event(_ message: String, at time: Double) {
        do {
            let object: [String: Any] = ["message": message, "uptime": time,
                                       "unixSeconds": epoch + time, "source": source,
                                       "droppedBlocksTotal": dropCount(),
                                       "sampleRate": rate as Any? ?? NSNull()]
            var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            data.append(0x0A)
            let url = directory.appendingPathComponent("events.jsonl")
            if !FileManager.default.fileExists(atPath: url.path) { _ = FileManager.default.createFile(atPath: url.path, contents: nil) }
            let file = try FileHandle(forWritingTo: url)
            defer { try? file.close() }
            try file.seekToEnd(); try file.write(contentsOf: data)
        } catch { onEvent("Event save failed: \(error.localizedDescription)") }
        onEvent(message)
    }
}
