import Foundation

/// Linear amplitude measurements for one block of normalized audio samples.
struct AudioLevels: Equatable {
    let peak: Double
    let rms: Double

    /// Returns nil for an empty block or any nonfinite sample.
    /// Silence is a valid measurement with both values equal to zero.
    static func measure<S: Sequence>(_ samples: S) -> AudioLevels? where S.Element == Float {
        var accumulator = AudioLevelAccumulator()
        for sample in samples { accumulator.add(sample) }
        return accumulator.levels
    }
}

/// Uses Double arithmetic without retaining samples or allocating in the audio callback.
struct AudioLevelAccumulator {
    private(set) var sampleCount: UInt64 = 0
    private(set) var invalidSamples: UInt64 = 0
    private var peak = 0.0
    private var sumOfSquares = 0.0

    mutating func add(_ sample: Float) {
        guard sample.isFinite else {
            invalidSamples += 1
            return
        }
        let value = Double(sample)
        sampleCount += 1
        peak = max(peak, abs(value))
        sumOfSquares += value * value
    }

    var levels: AudioLevels? {
        guard sampleCount > 0, invalidSamples == 0 else { return nil }
        return AudioLevels(peak: peak, rms: sqrt(sumOfSquares / Double(sampleCount)))
    }
}
