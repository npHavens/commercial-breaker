import Foundation
var policy = GeminiRecovery()
assert(policy.failed(now: 100) == 5 && policy.resumeAt == 105)
assert(policy.failed(now: 130) == 10 && policy.resumeAt == 140)
assert(policy.failed(now: 170) == nil && policy.consecutiveFailures == 3)
policy.succeeded()
assert(policy.resumeAt == 0 && policy.consecutiveFailures == 0)
assert(policy.failed(now: 200) == 5)
print("Timeout recovery bounds and successful reset passed")

assert(GeminiRecovery.allowsRetry(error: "request-failed", httpStatus: nil))
assert(GeminiRecovery.allowsRetry(error: "request-failed", httpStatus: 0))
assert(GeminiRecovery.allowsRetry(error: "temporary-failure", httpStatus: 503))
assert(GeminiRecovery.allowsRetry(error: "timeout", httpStatus: nil))
for code in [400, 401, 403] {
    assert(!GeminiRecovery.allowsRetry(error: "request-failed", httpStatus: code))
}
assert(!GeminiRecovery.allowsRetry(error: "invalid-request", httpStatus: nil))
print("Unknown failure recovery and terminal authentication checks passed")
