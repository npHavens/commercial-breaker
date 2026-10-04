import AVFoundation
import Foundation

let base = FileManager.default.temporaryDirectory.appendingPathComponent("skybox-clip-tests-" + UUID().uuidString)
defer { try? FileManager.default.removeItem(at: base) }
func records(_ directory: URL) throws -> [[String: Any]] {
    try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "json" }.map {
            try JSONSerialization.jsonObject(with: Data(contentsOf: $0)) as! [String: Any]
        }
}
func feed(_ store: AudioClipStore, end: Double, rate: Double = 8_000) {
    store.ingest(Array(repeating: 0.25, count: Int(rate)), sampleRate: rate, endedAt: end)
    // Keep tests deterministic without filling the deliberately bounded live queue.
    Thread.sleep(forTimeInterval: 0.005)
}
let full = base.appendingPathComponent("full")
let store = try AudioClipStore(directory: full, source: "test")
for second in 1...25 { feed(store, end: Double(second)) }
store.mark("Commercial started", at: 25)
for second in 26...35 { feed(store, end: Double(second)) }
store.stop()
let first = try records(full)
precondition(first.count == 1)
precondition(first[0]["frames"] as! Int == 240_000)
precondition(first[0]["partial"] as! Bool == false)
let wav = try AVAudioFile(forReading: full.appendingPathComponent(first[0]["wav"] as! String))
precondition(wav.length == 240_000 && wav.processingFormat.sampleRate == 8_000)

for changeMarker in ["Changed game", "Changed channel"] {
let reset = base.appendingPathComponent("reset-" + changeMarker)
let second = try AudioClipStore(directory: reset, source: "test")
feed(second, end: 1)
second.mark("Commercial started", at: 1)
second.mark(changeMarker, at: 2)
feed(second, end: 3)
second.mark("Program returned", at: 3)
second.stop()
let partials = try records(reset)
precondition(partials.count == 2)
precondition(partials.allSatisfy { $0["partial"] as! Bool })
precondition(partials.allSatisfy { $0["frames"] as! Int == 8_000 })
precondition(Set(partials.map { $0["completionReason"] as! String }) == ["channel changed", "capture stopped"])

}

let changing = base.appendingPathComponent("rate")
let third = try AudioClipStore(directory: changing, source: "test")
feed(third, end: 1)
third.mark("Commercial started", at: 1)
feed(third, end: 2, rate: 16_000)
third.mark("Football returned", at: 2)
third.ingest([.nan], sampleRate: 16_000, endedAt: 3)
third.stop()
let changes = try records(changing)
precondition(changes.count == 2)
precondition(Set(changes.map { $0["sampleRate"] as! Int }) == [8_000, 16_000])
precondition(changes.contains { $0["completionReason"] as! String == "sample rate changed" })
print("Audio clip pre/post boundaries, WAV samples, stop/channel partials, and rate reset checks passed")

let backwards = base.appendingPathComponent("backwards")
let fourth = try AudioClipStore(directory: backwards, source: "clock-test")
feed(fourth, end: 100)
fourth.mark("Commercial started", at: 100)
feed(fourth, end: 2)
fourth.mark("Football returned", at: 2)
fourth.stop()
let recovered = try records(backwards)
precondition(recovered.count == 2)
precondition(recovered.allSatisfy { $0["frames"] as! Int == 8_000 })
precondition(recovered.contains { $0["completionReason"] as! String == "audio timestamp moved backwards" })
let events = try String(contentsOf: backwards.appendingPathComponent("events.jsonl"), encoding: .utf8)
precondition(events.contains("Capture session started") && events.contains("Capture session stopped"))
precondition(events.contains("clock-test") && events.contains("8000"))
print("Backwards timestamp recovery and session event checks passed")
