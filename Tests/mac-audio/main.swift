import Foundation

func expect(_ samples: [Float], peak: Double, rms: Double) {
    guard let levels = AudioLevels.measure(samples) else { fatalError("Expected valid levels") }
    precondition(abs(levels.peak - peak) < 1e-10)
    precondition(abs(levels.rms - rms) < 1e-10)
}

expect([0, 0, 0], peak: 0, rms: 0)
expect([-0.5, 0.5], peak: 0.5, rms: 0.5)
expect([-1, 0, 1, 0], peak: 1, rms: sqrt(0.5))
expect([-2, 1], peak: 2, rms: sqrt(2.5)) // Do not clamp diagnostic clipping.
precondition(AudioLevels.measure([Float]()) == nil)
for invalid: Float in [.nan, .infinity, -.infinity] {
    precondition(AudioLevels.measure([0.5, invalid, 0.5]) == nil)
}
let large = AudioLevels.measure([Float.greatestFiniteMagnitude])!
precondition(large.rms.isFinite && large.peak.isFinite)
var accumulator = AudioLevelAccumulator()
accumulator.add(-0.5)
accumulator.add(0.5)
precondition(accumulator.sampleCount == 2)
precondition(accumulator.levels == AudioLevels(peak: 0.5, rms: 0.5))
accumulator.add(.nan)
precondition(accumulator.invalidSamples == 1 && accumulator.levels == nil)
print("Audio measurement checks passed")
