import Foundation

func add(_ detector: inout BreakCueDetector, _ end: Double, music: Double = 0.1,
         crowd: Double = 0.1, context: Int = 1) -> BreakCueCandidate? {
    detector.observe(startUptime: end - 3, endUptime: end, music: music, crowd: crowd, context: context)
}
func baseline(_ detector: inout BreakCueDetector, origin: Double = 0,
              music: Double = 0.1, crowd: Double = 0.1, context: Int = 1) {
    for i in 0..<12 { precondition(add(&detector, origin + 3 + Double(i) * 1.5, music: music, crowd: crowd, context: context) == nil) }
}
var detector = BreakCueDetector()
baseline(&detector)
precondition(add(&detector, 21, music: 0.5, crowd: 0.04) == nil, "one window must not trigger")
let first = add(&detector, 22.5, music: 0.5, crowd: 0.04)!
precondition(first.evidenceStartUptime == 18 && first.detectedAtUptime == 22.5)
precondition(add(&detector, 24, music: 0.8, crowd: 0.01) == nil, "cooldown")
// At exactly30seconds the cooldown permits new evidence.
for i in 0..<18 { precondition(add(&detector, 24 + Double(i) * 1.5) == nil) }
_ = add(&detector, 51, music: 0.8, crowd: 0.01)
precondition(add(&detector, 52.5, music: 0.8, crowd: 0.01) != nil)
var changed = BreakCueDetector(); baseline(&changed)
_ = add(&changed, 21, music: 0.8, crowd: 0.01, context: 2)
precondition(add(&changed, 22.5, music: 0.8, crowd: 0.01, context: 2) == nil)
var bounded = BreakCueDetector()
for index in 0..<400 {
    precondition(add(&bounded, 3 + Double(index) * 0.1,
                     music: index < 200 ? 0.1 : 0.8, crowd: index < 200 ? 0.1 : 0.01) == nil)
}
// Short baseline cannot qualify; overlapping windows are excluded from baseline.
var short = BreakCueDetector()
for i in 0..<8 { _ = add(&short, 3 + Double(i) * 1.5) }
_ = add(&short, 15, music: 0.8, crowd: 0.01)
precondition(add(&short, 16.5, music: 0.8, crowd: 0.01) == nil)
// Strict limits reject either confirming window just outside a threshold.
for (music, crowd) in [(0.4999, 0.01), (0.8, 0.04001)] {
    var check = BreakCueDetector(); baseline(&check)
    _ = add(&check, 21, music: music, crowd: crowd)
    precondition(add(&check, 22.5, music: 0.8, crowd: 0.01) == nil)
}
var weakCrowd = BreakCueDetector(); baseline(&weakCrowd, crowd: 0.0799)
_ = add(&weakCrowd, 21, music: 0.8, crowd: 0.01)
precondition(add(&weakCrowd, 22.5, music: 0.8, crowd: 0.01) == nil)
var weakRise = BreakCueDetector(); baseline(&weakRise, music: 0.4)
_ = add(&weakRise, 21, music: 0.54, crowd: 0.01)
precondition(add(&weakRise, 22.5, music: 0.54, crowd: 0.01) == nil)
// Context, gap, invalid input, and backwards time must forget earlier evidence.
for mode in 0..<4 {
    var check = BreakCueDetector(); baseline(&check)
    if mode == 0 { check.reset() }
    if mode == 1 { _ = add(&check, 30) }
    if mode == 2 { _ = add(&check, .nan) }
    if mode == 3 { _ = add(&check, 5) }
    _ = add(&check, 31.5, music: 0.8, crowd: 0.01, context: mode == 0 ? 2 : 1)
    precondition(add(&check, 33, music: 0.8, crowd: 0.01, context: mode == 0 ? 2 : 1) == nil)
}
// Pure replay must agree with the separately implemented Python rule and frozen review.
let review = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "Experiments/audio-cues/187D0070/cue-summary-reviewed.json"))) as! [String: Any]
let expected = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "Experiments/audio-cues/187D0070/candidate-evaluation.json"))) as! [String: Any]
precondition(NSDictionary(dictionary: BreakCueDetector.rule).isEqual(to: expected["rule"] as! [String: Any]))
var replay = BreakCueDetector()
let candidates = (review["windows"] as! [[String: Any]]).compactMap { window in
    replay.observe(startUptime: window["startUptime"] as! Double, endUptime: window["endUptime"] as! Double,
                   music: window["music"] as! Double, crowd: window["crowd"] as! Double, context: window["context"] as! Int)
}
let reference = expected["candidates"] as! [[String: Any]]
precondition(candidates.count == 2 && reference.count == 2)
for (actual, expected) in zip(candidates, reference) {
    precondition(abs(actual.detectedAtUptime - (expected["detectedAtUptime"] as! Double)) < 1e-8)
    precondition(abs(actual.evidenceStartUptime - (expected["evidenceStartUptime"] as! Double)) < 1e-8)
    precondition(abs(actual.baselineMusic - (expected["baselineMusic"] as! Double)) < 1e-12)
    precondition(abs(actual.baselineCrowd - (expected["baselineCrowd"] as! Double)) < 1e-12)
}
print("Break cue persistence, bounds, resets, cooldown, and exact two-candidate replay passed")
