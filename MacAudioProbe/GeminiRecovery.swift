import Foundation

/// Recover isolated temporary failures using future audio, never by resending old clips.
struct GeminiRecovery {
    static func allowsRetry(error: String, httpStatus: Int?) -> Bool {
        if let httpStatus, (400...499).contains(httpStatus), ![408, 429].contains(httpStatus) { return false }
        return ["timeout", "temporary-failure"].contains(error)
            || (error == "request-failed" && (httpStatus == nil || httpStatus == 0))
    }

    private(set) var consecutiveFailures = 0
    private(set) var resumeAt = 0.0

    mutating func failed(now: Double) -> Double? {
        consecutiveFailures += 1
        guard consecutiveFailures < 3 else { return nil }
        let delay = Double(consecutiveFailures * 5)
        resumeAt = now + delay
        return delay
    }

    mutating func succeeded() {
        consecutiveFailures = 0
        resumeAt = 0
    }
}
