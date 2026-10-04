import Foundation

func feed(_ buffer: GeminiAudioBuffer, rate: Double = 48_000, start: Double = 100, seconds: Int = 8) {
    for second in 0..<seconds {
        let values = (0..<Int(rate)).map { Float(sin(2 * .pi * 440 * Double($0) / rate) * 0.25) }
        buffer.ingest(values, sampleRate: rate, endedAt: start + Double(second + 1))
    }
}
func little32(_ data: Data, _ at: Int) -> UInt32 {
    (0..<4).reduce(0) { $0 | UInt32(data[at + $1]) << ($1 * 8) }
}
let buffer = GeminiAudioBuffer()
precondition(buffer.snapshot(now: 100) == nil)
feed(buffer)
let clip = buffer.snapshot(now: 108)!
precondition(clip.startUptime == 100 && clip.endUptime == 108)
precondition(clip.wavData.count == 256_044)
precondition(little32(clip.wavData, 24) == 16_000)
precondition(String(data: clip.wavData.prefix(4), encoding: .utf8) == "RIFF")
precondition(buffer.snapshot(now: 110) != nil)
precondition(buffer.snapshot(now: 110.001) == nil)
precondition(buffer.snapshot(now: 107) == nil)
precondition(buffer.snapshot(now: .nan) == nil)
// Rolling retention keeps the latest eight seconds even after ten seconds.
feed(buffer, start: 108, seconds: 12)
precondition(buffer.snapshot(now: 120)!.startUptime == 112)
buffer.reset()
precondition(buffer.snapshot(now: 120) == nil)
feed(buffer, rate: 44_100)
precondition(buffer.snapshot(now: 108)?.wavData.count == 256_044)
// Both supported extremes produce a complete eight-second WAV.
for rate in [8_000.0, 192_000.0] {
    buffer.reset()
    feed(buffer, rate: rate)
    precondition(buffer.snapshot(now: 108)?.wavData.count == 256_044)
}
// Hardware-sized blocks retain exact duration despite uptime rounding.
buffer.reset()
let block = [Float](repeating: 0.1, count: 4096)
for index in 0..<100 {
    buffer.ingest(block, sampleRate: 48_000, endedAt: 500_000 + Double((index + 1) * 4096) / 48_000)
}
precondition(buffer.snapshot(now: 500_000 + Double(409_600) / 48_000) != nil)
// A gap, overlap, bad sample, and changed format each invalidate prior context.
for mode in 0..<4 {
    buffer.reset()
    feed(buffer)
    switch mode {
    case 0: buffer.ingest([Float](repeating: 0, count: 48_000), sampleRate: 48_000, endedAt: 110)
    case 1: buffer.ingest([Float](repeating: 0, count: 48_000), sampleRate: 48_000, endedAt: 108.5)
    case 2: buffer.ingest([.nan], sampleRate: 48_000, endedAt: 108.001)
    default: buffer.ingest([Float](repeating: 0, count: 16_000), sampleRate: 16_000, endedAt: 109)
    }
    precondition(buffer.snapshot(now: 110) == nil)
}
// Resampling retains an audible 440 Hz tone at the expected amplitude.
var crossings = 0
var peak = 0
var previous = 0
for offset in stride(from: 44, to: clip.wavData.count, by: 2) {
    let sample = Int(Int16(bitPattern: UInt16(clip.wavData[offset]) | UInt16(clip.wavData[offset + 1]) << 8))
    if previous < 0 && sample >= 0 { crossings += 1 }
    peak = max(peak, abs(sample))
    previous = sample
}
precondition(abs(crossings - 3520) <= 2)
precondition((8_000...8_400).contains(peak))
print("Gemini audio buffer tests passed")
