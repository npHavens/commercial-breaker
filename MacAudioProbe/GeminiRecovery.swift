import Foundation

/// Recover temporary failures using future audio, never by resending old clips.
/// Gemini sometimes times out every request for minutes and then answers again, so a streak of
/// timeouts and temporary failures stops detection only once it has lasted `giveUpAfter` seconds.
struct GeminiRecovery {
    static let giveUpAfter = 300.0
    /// Failures the worker could not classify may be permanent (missing credentials, a bad
    /// endpoint), so a streak stops at this many of them, as every streak did before v0.2.51.
    static let unclassifiedLimit = 3
    static let longestDelay = 15.0

    enum Failure { case temporary, unclassified }

    /// How a failed request may be recovered, or nil when it stops detection at once.
    static func failure(error: String, httpStatus: Int?) -> Failure? {
        if let httpStatus, (400...499).contains(httpStatus), ![408, 429].contains(httpStatus) { return nil }
        if ["timeout", "temporary-failure"].contains(error) { return .temporary }
        return error == "request-failed" && (httpStatus == nil || httpStatus == 0) ? .unclassified : nil
    }

    private(set) var consecutiveFailures = 0
    private(set) var resumeAt = 0.0
    private var unclassifiedFailures = 0
    private var streakStart: Double?

    /// Seconds since the streak's first failed request was sent.
    func streakSeconds(now: Double) -> Double { streakStart.map { now - $0 } ?? 0 }

    /// The delay before the next request on fresh audio, or nil once the streak should stop.
    /// `sent` is when the failed request went out, so a 20-second timeout counts from its start.
    mutating func failed(_ failure: Failure, sent: Double, now: Double) -> Double? {
        streakStart = streakStart ?? sent
        consecutiveFailures += 1
        if failure == .unclassified { unclassifiedFailures += 1 }
        guard streakSeconds(now: now) < Self.giveUpAfter, unclassifiedFailures < Self.unclassifiedLimit else { return nil }
        let delay = min(Double(consecutiveFailures * 5), Self.longestDelay)
        resumeAt = now + delay
        return delay
    }

    /// Call only for answers from Gemini; the worker's local silence result says nothing about it.
    mutating func succeeded() {
        consecutiveFailures = 0
        unclassifiedFailures = 0
        resumeAt = 0
        streakStart = nil
    }
}
