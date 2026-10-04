import Foundation

/// Temporal smoothing only: two overlapping samples are not independent proof.
struct GeminiConfirmation {
    enum State: String { case program = "Program", commercialBreak = "Break (commercial / promo)" }
    private(set) var confirmed: State?
    private(set) var candidate: State?
    private(set) var count = 0
    private(set) var lastEnd: Double?

    private var lastEvidenceEnd: Double?
    private var unclearCount = 0
    private var candidateStart: Double?
    private var latestRaw = "unclear"

    var needsFastFollowUp: Bool { candidate == .commercialBreak && count == 1 }

    var display: String {
        let previous = confirmed.map { "Last confirmed: \($0.rawValue) · " } ?? ""
        guard let candidate else { return previous + (latestRaw == "not_program" ? "No sport coverage · waiting for return" : latestRaw == "unusable" ? "Audio unusable · waiting for usable audio" : "Current audio unclear · waiting for two matching predictions") }
        if unclearCount > 0 { return previous + "Current audio unclear · holding recent \(candidate.rawValue) candidate" }
        if count < 2 { return previous + "\(candidate.rawValue) · 1/2 predictions" }
        return "Confirmed: \(candidate.rawValue) · 2/2 predictions"
    }

    mutating func reset() { self = Self() }

    /// Break candidates may bridge one unclear sample within 15 seconds.
    /// Program requires uninterrupted evidence spanning at least five fresh seconds.
    /// It never counts as positive evidence or extends the evidence deadline.
    mutating func accept(_ raw: String, end: Double) -> Bool {
        guard end.isFinite, lastEnd.map({ end > $0 }) ?? true else { reset(); return false }
        if let lastEnd, end - lastEnd > 15 { reset() }
        lastEnd = end
        latestRaw = raw
        let next: State?
        switch raw {
        case "program": next = .program
        case "commercial", "promo": next = .commercialBreak
        default: next = nil
        }
        if let lastEvidenceEnd, end - lastEvidenceEnd > 15 {
            candidate = nil; count = 0
        }
        guard let next else {
            unclearCount += 1
            if candidate != .commercialBreak || unclearCount > 1 || count != 1 { candidate = nil; count = 0 }
            return false
        }
        unclearCount = 0
        lastEvidenceEnd = end
        if candidate != next || count == 0 {
            candidateStart = end
            count = 1
        } else if next == .commercialBreak || end - (candidateStart ?? end) >= 5 {
            count = min(2, count + 1)
        }
        candidate = next
        guard count == 2 else { return false }
        let changed = confirmed != next
        confirmed = next
        return changed
    }
}
