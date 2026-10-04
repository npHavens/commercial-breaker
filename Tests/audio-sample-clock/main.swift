import Foundation

func close(_ actual: Double, _ expected: Double, _ label: String) {
    precondition(abs(actual - expected) < 0.000001, "\(label): \(actual) != \(expected)")
}
var clock = AudioSampleClock(hostNowSeconds: 1000, uptimeNow: 500)
// Callback arrival can jitter independently; only hardware timestamps enter the clock.
var previous = 501.0
for block in 0..<300 {
    let hardwareStart = 1001 + Double(block) / 10
    let end = try clock.endUptime(sampleTime: Int64(block * 4800), hostSeconds: hardwareStart,
                                  frameCount: 4800, sampleRate: 48_000)
    close(end - previous, 0.1, "contiguous duration")
    previous = end
}
close(previous, 531, "full 30 seconds retained")
// Missing 0.2 seconds remains a gap.
close(try clock.endUptime(sampleTime: 1_449_600, hostSeconds: 1031.2,
                         frameCount: 4800, sampleRate: 48_000), 531.3, "sample gap")
// Device sample timeline reset anchors to its new host timestamp.
close(try clock.endUptime(sampleTime: 0, hostSeconds: 1040,
                         frameCount: 4800, sampleRate: 48_000), 540.1, "sample reset")
// Host jump with contiguous sample position is preserved.
close(try clock.endUptime(sampleTime: 4800, hostSeconds: 1042,
                         frameCount: 4800, sampleRate: 48_000), 542.1, "host discontinuity")
close(try clock.endUptime(sampleTime: 0, hostSeconds: 1050,
                         frameCount: 4410, sampleRate: 44_100), 550.1, "rate change")
do {
    _ = try clock.endUptime(sampleTime: .max, hostSeconds: 1050, frameCount: 1, sampleRate: 48_000)
    preconditionFailure("overflow accepted")
} catch AudioSampleClock.ClockError.invalidTimestamp { }
print("Audio sample clock tests passed")
