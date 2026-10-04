import AVFoundation
import Foundation

let directory = FileManager.default.temporaryDirectory.appendingPathComponent("skybox-clock-clip-" + UUID().uuidString)
defer { try? FileManager.default.removeItem(at: directory) }
let store = try AudioClipStore(directory: directory, source: "sample-clock regression")
let origin = 567_000.0
let hostOrigin = 987_000.0
let rate = 48_000.0
let count = 4096
let marker = origin + 25
var clock = AudioSampleClock(hostNowSeconds: hostOrigin, uptimeNow: origin)
var marked = false
for block in 0..<440 {
    let sampleTime = Int64(block * count)
    let hardwareHost = hostOrigin + Double(sampleTime) / rate
    let end = try clock.endUptime(sampleTime: sampleTime, hostSeconds: hardwareHost,
                                  frameCount: count, sampleRate: rate)
    // Jitter callback delivery independently of the hardware sample timestamps.
    Thread.sleep(forTimeInterval: block % 3 == 0 ? 0.006 : 0.003)
    store.ingest(Array(repeating: 0.25, count: count), sampleRate: rate, endedAt: end)
    if !marked && end >= marker {
        store.mark("Commercial started", at: marker)
        marked = true
    }
}
store.stop()
let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
let metadataURL = urls.first { $0.pathExtension == "json" }!
let metadata = try JSONSerialization.jsonObject(with: Data(contentsOf: metadataURL)) as! [String: Any]
let wav = try AVAudioFile(forReading: directory.appendingPathComponent(metadata["wav"] as! String))
let duration = Double(wav.length) / wav.processingFormat.sampleRate
print("Integrated sample-clock clip: \(wav.length) frames, \(duration)s")
fflush(stdout)
precondition(abs(duration - 30) <= 0.001, "30-second clip lost samples")
precondition(metadata["partial"] as! Bool == false)
precondition((metadata["missingIntervals"] as! [[String: Double]]).isEmpty)
precondition(metadata["droppedBlocksTotal"] as! Int == 0)
print("Audio clock/clip regression passed")
