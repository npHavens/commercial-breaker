import AVFoundation
import Foundation

final class Results: @unchecked Sendable {
    let lock = NSLock()
    var readings: [LiveCueReading] = []
    var statuses: [String] = []
    func add(_ reading: LiveCueReading) { lock.lock(); readings.append(reading); lock.unlock() }
    func status(_ text: String) { lock.lock(); statuses.append(text); lock.unlock() }
    func snapshot() -> ([LiveCueReading], [String]) { lock.lock(); defer { lock.unlock() }; return (readings, statuses) }
}
guard CommandLine.arguments.count == 2 else { fatalError("Pass an existing mono WAV file; this test never starts capture.") }
let input = try AVAudioFile(forReading: URL(fileURLWithPath: CommandLine.arguments[1]))
let rate = input.processingFormat.sampleRate
precondition(input.processingFormat.channelCount == 1)
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("skybox-cue-test-" + UUID().uuidString)
defer { try? FileManager.default.removeItem(at: directory) }
let results = Results()
let service = try LiveAudioCues(directory: directory, onUpdate: { results.add($0) }, onStatus: { results.status($0) })
func feed(origin: Double) throws {
    input.framePosition = 0
    for second in 0..<9 {
        let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: AVAudioFrameCount(rate))!
        try input.read(into: buffer)
        precondition(buffer.frameLength > 0)
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        service.ingest(samples: samples, sampleRate: rate, endedAt: origin + Double(second + 1))
        Thread.sleep(forTimeInterval: 0.4)
    }
    Thread.sleep(forTimeInterval: 1)
}
try feed(origin: 567_000)
precondition(!results.snapshot().0.isEmpty, "No built-in classifier output")
service.reset(reason: "Changed game")
try feed(origin: 568_000)
service.ingest(samples: Array(repeating: 0, count: Int(rate)), sampleRate: rate, endedAt: 569_001)
Thread.sleep(forTimeInterval: 0.4)
service.stop()
let snapshot = results.snapshot()
precondition(snapshot.0.contains { $0.startUptime >= 568_000 })
precondition(snapshot.0.allSatisfy { $0.endUptime > $0.startUptime && (0...1).contains($0.music) && (0...1).contains($0.speech) && (0...1).contains($0.crowd) })
let lines = try String(contentsOf: directory.appendingPathComponent("live-cues.jsonl"), encoding: .utf8).split(separator: "\n")
let records = try lines.map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
precondition(records.contains { $0["event"] as? String == "reset" })
precondition(records.contains { $0["event"] as? String == "discontinuity" })
precondition(!records.contains { $0["event"] as? String == "error" })
let errors = Results()
let failing = try LiveAudioCues(directory: directory.appendingPathComponent("failure"), onUpdate: { errors.add($0) }, onStatus: { errors.status($0) })
failing.ingest(samples: [.nan], sampleRate: rate, endedAt: 1)
Thread.sleep(forTimeInterval: 0.2)
failing.stop()
precondition(errors.snapshot().1.contains { $0.contains("Nonfinite") })
let overload = Results()
let saturated = try LiveAudioCues(directory: directory.appendingPathComponent("overload"),
    onUpdate: { overload.add($0) }, onStatus: { overload.status($0) })
let block = Array(repeating: Float(0.1), count: Int(rate))
for index in 0..<100 { saturated.ingest(samples: block, sampleRate: rate, endedAt: Double(index + 1)) }
saturated.stop()
precondition(overload.snapshot().1.contains { $0.contains("backlog") })
print("Live cue WAV streaming, bounded values, reset/gap timing, JSONL, nonfinite failure, and overload shutdown passed (\(snapshot.0.count) readings)")
