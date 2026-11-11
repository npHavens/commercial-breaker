import Foundation
var policy = GeminiRecovery()
// Timeouts arrive 20 s after their request was sent; the streak counts from that send.
// Delays grow 5, 10, then hold at 15 seconds, and a third failure no longer stops detection.
assert(policy.failed(.temporary, sent: 80, now: 100) == 5 && policy.resumeAt == 105)
assert(policy.failed(.temporary, sent: 105, now: 125) == 10 && policy.resumeAt == 135)
assert(policy.failed(.temporary, sent: 135, now: 155) == 15 && policy.consecutiveFailures == 3)
assert(policy.streakSeconds(now: 155) == 75)
assert(policy.failed(.temporary, sent: 170, now: 190) == 15)
assert(policy.failed(.temporary, sent: 359, now: 379.9) == 15, "A streak just under five minutes still retries")
assert(policy.failed(.temporary, sent: 360, now: 380) == nil, "A streak lasting five minutes stops detection")
print("Failure streak delays and five-minute limit passed")

// October 27: timeouts for at least three minutes, across a restart. Requests went out at
// +0, +25 and +55 s, then the restarted worker's at +117, +142 and +172 s.
policy = GeminiRecovery()
for sent in [0.0, 25, 55, 117, 142, 172] { assert(policy.failed(.temporary, sent: sent, now: sent + 20) != nil) }
// November 9, 8:00 PM: three timeouts, then Gemini answered again.
policy = GeminiRecovery()
for (sent, delay) in [(0.0, 5.0), (25, 10), (55, 15)] { assert(policy.failed(.temporary, sent: sent, now: sent + 20) == delay) }
policy.succeeded()
assert(policy.resumeAt == 0 && policy.consecutiveFailures == 0 && policy.streakSeconds(now: 500) == 0)
// A success starts the next streak's five minutes over.
assert(policy.failed(.temporary, sent: 200, now: 220) == 5 && policy.failed(.temporary, sent: 470, now: 490) == 10)
assert(policy.failed(.temporary, sent: 480, now: 500) == nil)
print("Outage replays, successful reset and fresh streak timing passed")

// Unclassified failures may be permanent, so the third in a streak stops it, however quickly.
policy = GeminiRecovery()
assert(policy.failed(.unclassified, sent: 0, now: 1) == 5 && policy.failed(.temporary, sent: 6, now: 26) == 10)
assert(policy.failed(.unclassified, sent: 36, now: 37) == 15)
assert(policy.failed(.unclassified, sent: 52, now: 53) == nil, "Three unclassified failures stop detection")
policy = GeminiRecovery()
for _ in 0..<2 { _ = policy.failed(.unclassified, sent: 0, now: 1) }
policy.succeeded()
assert(policy.failed(.unclassified, sent: 10, now: 11) != nil, "A success clears the unclassified count")
print("Unclassified failure limit passed")

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
