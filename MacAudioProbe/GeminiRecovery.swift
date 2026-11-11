import Foundation

/// Recover temporary failures using future audio, never by resending old clips.
/// Gemini sometimes times out every request for minutes and then answers again, so a streak of
/// timeouts and temporary failures stops detection only once it has spent `giveUpAfter` seconds
/// failing.
struct GeminiRecovery {
    static let giveUpAfter = 300.0
    /// Failures the worker could not classify may be permanent (missing credentials, a bad
    /// endpoint), so a streak stops at this many of them, as every streak did before v0.2.51.
    static let unclassifiedLimit = 3
    static let longestDelay = 15.0

    enum Failure { case temporary, unclassified }
    enum Outcome: Equatable { case retry(after: Double), stopAfterTime, stopUnclassified }

    /// How a failed request may be recovered, or nil when it stops detection at once.
    static func failure(error: String, httpStatus: Int?) -> Failure? {
        if let httpStatus, (400...499).contains(httpStatus), ![408, 429].contains(httpStatus) { return nil }
        if ["timeout", "temporary-failure"].contains(error) { return .temporary }
        return error == "request-failed" && (httpStatus == nil || httpStatus == 0) ? .unclassified : nil
    }

    private(set) var consecutiveFailures = 0
    private(set) var resumeAt = 0.0
    /// Seconds this streak has spent on failed requests and on the waits before retrying them.
    /// Time spent otherwise, such as waiting for audio or on local silence answers, is not counted.
    private(set) var failingSeconds = 0.0
    private var unclassifiedFailures = 0
    private var lastDelay = 0.0

    /// `sent` is when the failed request went out, so a 20-second timeout counts in full.
    mutating func failed(_ failure: Failure, sent: Double, now: Double) -> Outcome {
        consecutiveFailures += 1
        failingSeconds += lastDelay + (now - sent)
        if failure == .unclassified { unclassifiedFailures += 1 }
        if unclassifiedFailures >= Self.unclassifiedLimit { return .stopUnclassified }
        if failingSeconds >= Self.giveUpAfter { return .stopAfterTime }
        lastDelay = min(Double(consecutiveFailures * 5), Self.longestDelay)
        resumeAt = now + lastDelay
        return .retry(after: lastDelay)
    }

    /// Call only for answers from Gemini; the worker's local silence result says nothing about it.
    mutating func succeeded() {
        consecutiveFailures = 0
        unclassifiedFailures = 0
        resumeAt = 0
        failingSeconds = 0
        lastDelay = 0
    }
}
