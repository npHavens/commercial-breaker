import AVFoundation
import Foundation
import SoundAnalysis

struct LiveCueReading: Sendable {
    let music: Double
    let speech: Double
    /// Maximum of crowd, cheering, and applause. This is a cue, not a probability of football.
    let crowd: Double
    let startUptime: Double
    let endUptime: Double
}

/// Local observation only. Callbacks run on a private queue; dispatch UI updates to MainActor.
/// Classification failure stops this service without touching the audio recorder.
final class LiveAudioCues: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.nohandsstack.skybox.live-cues", qos: .utility)
    private let queueKey = DispatchSpecificKey<Bool>()
    private let lock = NSLock()
    private var stopped = false
    private var generation = 0
    private var queued = 0
    private let file: FileHandle
    private let onUpdate: @Sendable (LiveCueReading) -> Void
    private let onStatus: @Sendable (String) -> Void
    private let onCandidate: @Sendable (BreakCueCandidate) -> Void
    private var detector = BreakCueDetector()
    // Analyzer and file state below are used only on queue.
    private var analyzer: SNAudioStreamAnalyzer?
    private var observer: CueObserver?
    private var rate: Double?
    private var origin = 0.0
    private var position: AVAudioFramePosition = 0
    private var previousEnd: Double?
    private var contextGeneration = 0
    private var logFailed = false

    init(directory: URL, onUpdate: @escaping @Sendable (LiveCueReading) -> Void,
         onStatus: @escaping @Sendable (String) -> Void,
         onCandidate: @escaping @Sendable (BreakCueCandidate) -> Void = { _ in }) throws {
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        let labels = Set(request.knownClassifications)
        guard Set(["music", "speech", "crowd", "cheering", "applause"]).isSubset(of: labels) else {
            throw NSError(domain: "SkyboxCues", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Built-in classifier lacks required audio cue labels."])
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("live-cues.jsonl")
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        file = try FileHandle(forWritingTo: url)
        self.onUpdate = onUpdate
        self.onStatus = onStatus
        self.onCandidate = onCandidate
        queue.setSpecific(key: queueKey, value: true)
        queue.sync {
            write(["event": "classifier", "classifier": "Apple SoundAnalysis version1",
                   "windowSecondsRequested": 3, "overlapFactor": 0.5,
                   "crowdAggregation": "max(crowd, cheering, applause)",
                   "mode": "observation only; scores are not commercial decisions",
                   "breakRuleVersion": BreakCueDetector.ruleVersion, "breakRule": BreakCueDetector.rule])
        }
        if logFailed {
            throw NSError(domain: "SkyboxCues", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to write classifier metadata."])
        }
    }

    func ingest(samples: [Float], sampleRate: Double, endedAt: Double) {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        guard sampleRate.isFinite, (8_000...192_000).contains(sampleRate), endedAt.isFinite,
              !samples.isEmpty, samples.count <= Int(sampleRate * 2), queued < 8 else {
            stopped = true
            generation += 1
            lock.unlock()
            queue.async { [self] in fail("Invalid audio or analysis backlog exceeded eight buffers; cue analysis stopped. Recording continues.") }
            return
        }
        let acceptedGeneration = generation
        queued += 1
        queue.async { [self] in
            defer { lock.lock(); queued -= 1; lock.unlock() }
            guard isCurrent(acceptedGeneration) else { return }
            guard samples.allSatisfy(\.isFinite) else {
                fail("Nonfinite audio sample; cue analysis stopped. Recording continues.")
                return
            }
            process(samples, rate: sampleRate, end: endedAt, generation: acceptedGeneration)
        }
        lock.unlock()
    }

    func reset(reason: String) {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        generation += 1
        let next = generation
        queue.async { [self] in
            guard isCurrent(next) else { return }
            clearContext()
            contextGeneration = next
            write(["event": "reset", "reason": reason, "generation": next])
            onStatus("Audio cue context reset: \(reason)")
        }
        lock.unlock()
    }

    /// Safe from callbacks too. Pending classifier results are discarded after stop.
    func stop() {
        lock.lock()
        let wasStopped = stopped
        stopped = true
        generation += 1
        lock.unlock()
        let finish = { [self] in
            clearContext()
            if !wasStopped { write(["event": "stopped"]) }
            try? file.synchronize()
        }
        if DispatchQueue.getSpecific(key: queueKey) == true { finish() }
        else { queue.sync(execute: finish) }
    }

    deinit { try? file.close() }

    private func isCurrent(_ value: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return !stopped && generation == value
    }

    private func process(_ samples: [Float], rate newRate: Double, end: Double, generation: Int) {
        let start = end - Double(samples.count) / newRate
        // System-tap timestamps approximate callback ends. Allow small scheduling jitter,
        // while material gaps/reset/rate changes always clear classifier context.
        let difference = previousEnd.map { start - $0 } ?? 0
        if analyzer != nil && (rate != newRate || abs(difference) > 0.1) {
            write(["event": "discontinuity", "previousEndUptime": previousEnd as Any? ?? NSNull(),
                   "nextStartUptime": start, "differenceSeconds": difference,
                   "previousSampleRate": rate as Any? ?? NSNull(), "sampleRate": newRate])
            clearContext()
        }
        do {
            if analyzer == nil { try createContext(rate: newRate, start: start, generation: generation) }
            guard let analyzer,
                  let format = AVAudioFormat(standardFormatWithSampleRate: newRate, channels: 1),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
                throw NSError(domain: "SkyboxCues", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Unable to create analysis buffer"])
            }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { values in
                buffer.floatChannelData![0].update(from: values.baseAddress!, count: values.count)
            }
            previousEnd = end
            analyzer.analyze(buffer, atAudioFramePosition: position)
            position += AVAudioFramePosition(samples.count)
        } catch { fail("Cue analysis stopped: \(error.localizedDescription). Recording continues.") }
    }

    private func createContext(rate: Double, start: Double, generation: Int) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let analyzer = SNAudioStreamAnalyzer(format: format)
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        request.windowDuration = CMTime(seconds: 3, preferredTimescale: 48_000)
        request.overlapFactor = 0.5
        contextGeneration += 1
        let context = contextGeneration
        let observer = CueObserver { [weak self] result, error in
            guard let self else { return }
            self.queue.async { [weak self] in
                guard let self, self.isCurrent(generation), self.contextGeneration == context else { return }
                if let error { self.fail("Cue classifier failed: \(error). Recording continues.") }
                else if let result { self.receive(result, generation: generation) }
            }
        }
        try analyzer.add(request, withObserver: observer)
        self.analyzer = analyzer
        self.observer = observer
        self.rate = rate
        origin = start
        position = 0
        write(["event": "context", "originUptime": start, "sampleRate": rate,
               "windowSeconds": request.windowDuration.seconds, "generation": generation,
               "context": context])
    }

    private func receive(_ result: SNClassificationResult, generation: Int) {
        guard isCurrent(generation) else { return }
        let values = Dictionary(result.classifications.map { ($0.identifier, $0.confidence) }, uniquingKeysWith: max)
        let start = origin + result.timeRange.start.seconds
        let end = start + result.timeRange.duration.seconds
        let reading = LiveCueReading(music: values["music"] ?? 0, speech: values["speech"] ?? 0,
            crowd: max(values["crowd"] ?? 0, values["cheering"] ?? 0, values["applause"] ?? 0),
            startUptime: start, endUptime: end)
        guard start.isFinite, end.isFinite else { fail("Invalid classifier time range; cue analysis stopped."); return }
        write(["event": "scores", "startUptime": start, "endUptime": end,
               "music": reading.music, "speech": reading.speech, "crowd": reading.crowd,
               "crowdRaw": values["crowd"] ?? 0, "cheering": values["cheering"] ?? 0,
               "applause": values["applause"] ?? 0, "context": contextGeneration])
        guard !logFailed, isCurrent(generation) else { return }
        let candidate = detector.observe(startUptime: start, endUptime: end, music: reading.music,
                                         crowd: reading.crowd, context: contextGeneration)
        onUpdate(reading)
        guard isCurrent(generation) else { return }
        if let candidate {
            write(["event": "breakCandidate", "detectedAtUptime": candidate.detectedAtUptime,
                   "evidenceStartUptime": candidate.evidenceStartUptime,
                   "baselineMusic": candidate.baselineMusic, "baselineCrowd": candidate.baselineCrowd,
                   "music": candidate.music, "crowd": candidate.crowd,
                   "context": contextGeneration, "ruleVersion": BreakCueDetector.ruleVersion,
                   "note": "Observation only; not a confirmed commercial. No playback action."])
            if !logFailed { onCandidate(candidate) }
        }
    }

    private func clearContext() {
        detector.reset()
        contextGeneration += 1
        analyzer?.removeAllRequests()
        analyzer = nil
        observer = nil
        rate = nil
        position = 0
        previousEnd = nil
    }

    private func fail(_ message: String) {
        lock.lock(); stopped = true; generation += 1; lock.unlock()
        clearContext()
        write(["event": "error", "message": message])
        onStatus(message)
    }

    private func write(_ object: [String: Any]) {
        guard !logFailed else { return }
        do {
            var record = object
            record["loggedAtUptime"] = ProcessInfo.processInfo.systemUptime
            var data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
            data.append(0x0a)
            try file.write(contentsOf: data)
        } catch {
            logFailed = true
            lock.lock(); stopped = true; generation += 1; lock.unlock()
            onStatus("Cue logging failed: \(error.localizedDescription). Recording continues.")
        }
    }
}

private final class CueObserver: NSObject, SNResultsObserving {
    let callback: (SNClassificationResult?, String?) -> Void
    init(callback: @escaping (SNClassificationResult?, String?) -> Void) { self.callback = callback }
    func request(_ request: SNRequest, didProduce result: SNResult) {
        callback(result as? SNClassificationResult, nil)
    }
    func request(_ request: SNRequest, didFailWithError error: Error) {
        callback(nil, error.localizedDescription)
    }
    func requestDidComplete(_ request: SNRequest) { }
}
