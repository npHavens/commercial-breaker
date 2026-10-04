import Foundation

struct BreakCueCandidate: Sendable {
    let detectedAtUptime: Double
    let evidenceStartUptime: Double
    let baselineMusic: Double
    let baselineCrowd: Double
    let music: Double
    let crowd: Double
}

/// Fixed exploratory rule from evaluate-cue-candidates.py, not a trained classifier.
/// Candidates are observation-only; this type has no playback or recording side effects.
struct BreakCueDetector {
    static let ruleVersion = "music-rise-crowd-drop-v1"
    static let rule: [String: Double] = [
        "historySeconds": 30, "minimumBaselineSeconds": 15,
        "musicMinimum": 0.5, "musicRiseMinimum": 0.15,
        "crowdBaselineMinimum": 0.08, "crowdMaximum": 0.04,
        "crowdFractionMaximum": 0.5, "confirmationWindows": 2,
        "cooldownSeconds": 30, "maximumWindowStepSeconds": 3
    ]
    private struct Window {
        let start: Double
        let end: Double
        let music: Double
        let crowd: Double
        let context: Int
    }
    private var history: [Window] = []
    private var previous: Window?
    private var lastEmitted = -Double.infinity

    mutating func reset() {
        history.removeAll(keepingCapacity: true)
        previous = nil
        lastEmitted = -.infinity
    }

    mutating func observe(startUptime: Double, endUptime: Double, music: Double,
                          crowd: Double, context: Int) -> BreakCueCandidate? {
        guard startUptime.isFinite, endUptime.isFinite, endUptime > startUptime,
              music.isFinite, crowd.isFinite, (0...1).contains(music), (0...1).contains(crowd) else {
            reset()
            return nil
        }
        let current = Window(start: startUptime, end: endUptime, music: music, crowd: crowd, context: context)
        if let previous, previous.context != context || endUptime <= previous.end || endUptime - previous.end > 3 {
            reset()
        }
        previous = current
        history.append(current)
        history.removeAll { endUptime - $0.end > 30 }
        if history.count > 64 { history.removeFirst(history.count - 64) }
        let recent = Array(history.suffix(2))
        guard recent.count == 2 else { return nil }
        // Baseline and confirming evidence must not overlap.
        let baseline = history.filter { $0.end <= recent[0].start }
        guard let first = baseline.first, let last = baseline.last,
              last.end - first.start >= 15 else { return nil }
        let baseMusic = baseline.reduce(0) { $0 + $1.music } / Double(baseline.count)
        let baseCrowd = baseline.reduce(0) { $0 + $1.crowd } / Double(baseline.count)
        let eligible = baseCrowd >= 0.08 && recent.allSatisfy {
            $0.music >= 0.5 && $0.music - baseMusic >= 0.15 &&
            $0.crowd <= 0.04 && $0.crowd <= baseCrowd * 0.5
        }
        guard eligible, endUptime - lastEmitted >= 30 else { return nil }
        lastEmitted = endUptime
        return BreakCueCandidate(detectedAtUptime: endUptime, evidenceStartUptime: recent[0].start,
                                 baselineMusic: baseMusic, baselineCrowd: baseCrowd, music: music, crowd: crowd)
    }
}
