import Foundation

/// Fails 20-second timeouts back to back, each retry sent when its delay ends, as during an outage.
/// Returns the outcomes in order.
func outage(_ policy: inout GeminiRecovery, from start: Double, upTo limit: Int) -> [GeminiRecovery.Outcome] {
    var sent = start, outcomes: [GeminiRecovery.Outcome] = []
    while outcomes.count < limit {
        let outcome = policy.failed(.temporary, sent: sent, now: sent + 20)
        outcomes.append(outcome)
        guard case .retry(let delay) = outcome else { break }
        sent += 20 + delay
    }
    return outcomes
}

var policy = GeminiRecovery()
// Delays grow 5, 10, then hold at 15 seconds, and a third failure no longer stops detection.
var outcomes = outage(&policy, from: 0, upTo: 4)
assert(outcomes == [.retry(after: 5), .retry(after: 10), .retry(after: 15), .retry(after: 15)])
assert(policy.failingSeconds == 20 + 25 + 30 + 35 && policy.resumeAt == 110 + 15)
// Continuous timeouts count 20, 45, 75, then 35 more each: the tenth failure, at 320 s, is the
// first at or past five minutes, so the overrun is under one delay plus one timeout.
policy = GeminiRecovery()
outcomes = outage(&policy, from: 0, upTo: 20)
assert(outcomes.count == 10 && outcomes.last == .stopAfterTime && policy.failingSeconds == 320)
print("Failure streak delays and five-minute limit passed")

// Time without failed requests does not count: a timeout, 40 s of local silence answers (no
// succeeded() call), then another timeout continues the streak without the gap.
policy = GeminiRecovery()
_ = policy.failed(.temporary, sent: 0, now: 20)
assert(policy.failed(.temporary, sent: 60, now: 80) == .retry(after: 10) && policy.failingSeconds == 45)
// After a longer gap the streak has expired: 4.5 minutes of failing, half an hour of silence,
// then one timeout starts over rather than stopping detection.
policy = GeminiRecovery()
let longOutage = outage(&policy, from: 0, upTo: 9)
assert(longOutage.allSatisfy { $0 != .stopAfterTime } && policy.failingSeconds == 285)
assert(policy.failed(.temporary, sent: 2100, now: 2120) == .retry(after: 5) && policy.failingSeconds == 20)
policy = GeminiRecovery(failuresInARowLimit: 3)
_ = policy.failed(.unclassified, sent: 0, now: 1); _ = policy.failed(.unclassified, sent: 6, now: 7)
assert(policy.failed(.unclassified, sent: 600, now: 601) == .retry(after: 5), "Expired counts do not carry over")
print("Gaps between failed requests and streak expiry passed")

// October 27: timeouts for at least three minutes, across a restart, would keep retrying.
policy = GeminiRecovery()
assert(outage(&policy, from: 0, upTo: 6) == [5, 10, 15, 15, 15, 15].map { .retry(after: $0) })
// November 9, 8:00 PM: three timeouts, then Gemini answered again, which resets the streak.
policy = GeminiRecovery()
assert(outage(&policy, from: 0, upTo: 3) == [.retry(after: 5), .retry(after: 10), .retry(after: 15)])
policy.succeeded()
assert(policy.resumeAt == 0 && policy.consecutiveFailures == 0 && policy.failingSeconds == 0)
assert(outage(&policy, from: 500, upTo: 1) == [.retry(after: 5)], "A fresh streak starts at the shortest delay")
print("Outage replays and successful reset passed")

// Unclassified failures may be permanent, so the third in a streak stops it, however quickly.
policy = GeminiRecovery()
assert(policy.failed(.unclassified, sent: 0, now: 1) == .retry(after: 5) && policy.failed(.temporary, sent: 6, now: 26) == .retry(after: 10))
assert(policy.failed(.unclassified, sent: 36, now: 37) == .retry(after: 15))
assert(policy.failed(.unclassified, sent: 52, now: 53) == .stopUnclassified, "Three unclassified failures stop detection")
policy = GeminiRecovery()
for _ in 0..<2 { _ = policy.failed(.unclassified, sent: 0, now: 1) }
policy.succeeded()
assert(policy.failed(.unclassified, sent: 10, now: 11) == .retry(after: 5), "A success clears the unclassified count")
print("Unclassified failure limit passed")

// While AirPlay playback is on the Mac, the old stop at three failures in a row still applies.
policy = GeminiRecovery(failuresInARowLimit: GeminiRecovery.offTVFailureLimit)
assert(outage(&policy, from: 0, upTo: 5) == [.retry(after: 5), .retry(after: 10), .stopAfterFailuresInARow])
policy = GeminiRecovery(failuresInARowLimit: 3)
_ = policy.failed(.temporary, sent: 0, now: 20); _ = policy.failed(.temporary, sent: 25, now: 45)
policy.succeeded()
assert(policy.failed(.temporary, sent: 600, now: 620) == .retry(after: 5), "An answer from Gemini clears the count")
print("Off-TV failures-in-a-row limit passed")

assert(GeminiRecovery.failure(error: "request-failed", httpStatus: nil) == .unclassified)
assert(GeminiRecovery.failure(error: "request-failed", httpStatus: 0) == .unclassified)
assert(GeminiRecovery.failure(error: "temporary-failure", httpStatus: 503) == .temporary)
assert(GeminiRecovery.failure(error: "temporary-failure", httpStatus: 429) == .temporary)
assert(GeminiRecovery.failure(error: "timeout", httpStatus: nil) == .temporary)
for code in [400, 401, 403] {
    assert(GeminiRecovery.failure(error: "request-failed", httpStatus: code) == nil)
}
for error in ["invalid-request", "busy", "incomplete-response", "invalid-response"] {
    assert(GeminiRecovery.failure(error: error, httpStatus: nil) == nil)
}
print("Failure classes and terminal authentication checks passed")
