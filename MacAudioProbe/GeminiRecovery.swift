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
    /// Failed requests in a row that stop a session while AirPlay playback is on the Mac. Minutes
    /// of retries there would leave the TV without picture, so the pre-v0.2.51 rule still applies.
    static let offTVFailureLimit = 3

    enum Failure { case temporary, unclassified }
    enum Outcome: Equatable { case retry(after: Double), stopAfterTime, stopUnclassified, stopAfterFailuresInARow }

    /// Counts here run from Gemini's last answer: the worker's local silence answers neither reset
    /// nor add to them, since they never reached Gemini.
    let failuresInARowLimit: Int?
    init(failuresInARowLimit: Int? = nil) { self.failuresInARowLimit = failuresInARowLimit }

    /// How a failed request may be recovered, or nil when it stops detection at once.
    static func failure(error: String, httpStatus: Int?) -> Failure? {
        // The worker already sends 4xx other than 408 and 429 as request-failed; this keeps them
        // terminal if it ever reports one with another error name.
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

    /// The wait before retrying after the `n`th failure in a row; 0 before any failure.
    private static func delay(after n: Int) -> Double { min(Double(n * 5), longestDelay) }

    /// `sent` is when the failed request went out, so a 20-second timeout counts in full.
    mutating func failed(_ failure: Failure, sent: Double, now: Double) -> Outcome {
        failingSeconds += Self.delay(after: consecutiveFailures) + (now - sent)
        consecutiveFailures += 1
        if failure == .unclassified { unclassifiedFailures += 1 }
        if let failuresInARowLimit, consecutiveFailures >= failuresInARowLimit { return .stopAfterFailuresInARow }
        if unclassifiedFailures >= Self.unclassifiedLimit { return .stopUnclassified }
        if failingSeconds >= Self.giveUpAfter { return .stopAfterTime }
        let delay = Self.delay(after: consecutiveFailures)
        resumeAt = now + delay
        return .retry(after: delay)
    }

    /// Call only for answers from Gemini; the worker's local silence result says nothing about it.
    mutating func succeeded() {
        consecutiveFailures = 0
        unclassifiedFailures = 0
        resumeAt = 0
        failingSeconds = 0
    }
}
