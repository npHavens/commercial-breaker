import Foundation

/// Temporal smoothing only: two overlapping samples are not independent proof.
/// A break also needs one `commercial` among its matching predictions. The 21 breaks
/// confirmed on promos alone from October 26 to November 14 were all in-broadcast UFC
/// content (fighter hype packages, card previews, simulcast notices), not ad breaks.
struct GeminiConfirmation {
    enum State: String { case program = "Program", commercialBreak = "Break (commercial / promo)" }
    private(set) var confirmed: State?
    private(set) var candidate: State?
    private(set) var count = 0
    private(set) var lastEnd: Double?
    /// Whether the current break candidate includes a `commercial` prediction.
    private(set) var commercialHeard = false

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
        if candidate == .commercialBreak && !commercialHeard && confirmed != .commercialBreak {
            return previous + "Promo only · waiting for a commercial before confirming a break"
        }
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
        var isCommercial = false
        switch raw {
        case "program": next = .program
        case "commercial": next = .commercialBreak; isCommercial = true
        case "promo": next = .commercialBreak
        default: next = nil
        }
        if let lastEvidenceEnd, end - lastEvidenceEnd > 15 { clearCandidate() }
        guard let next else {
            unclearCount += 1
            // An unconfirmed break candidate (one prediction, or promos held for a
            // commercial) may bridge one unclear sample.
            let unconfirmedBreak = candidate == .commercialBreak && (count == 1 || !commercialHeard)
            if !unconfirmedBreak || unclearCount > 1 { clearCandidate() }
            return false
        }
        unclearCount = 0
        lastEvidenceEnd = end
        if candidate != next || count == 0 {
            candidateStart = end
            count = 1
            commercialHeard = false
        } else if next == .commercialBreak || end - (candidateStart ?? end) >= 5 {
            count = min(2, count + 1)
        }
        if isCommercial { commercialHeard = true }
        candidate = next
        guard count == 2, next == .program || commercialHeard else { return false }
        let changed = confirmed != next
        confirmed = next
        return changed
    }

    private mutating func clearCandidate() {
        candidate = nil; count = 0; commercialHeard = false
    }
}
