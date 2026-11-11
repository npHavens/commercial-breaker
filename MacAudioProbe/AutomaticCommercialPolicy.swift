import Foundation

/// Coordinates routing intent only. The controller verifies routes, owns audio capture,
/// and rejects stale asynchronous completions using its session generation.
struct AutomaticCommercialPolicy {
    enum Phase: Equatable {
        case idle, starting, watchingTV, movingToMac, mutedMac, movingToTV, recovering
        case watchingMac, mutingLocalMac, mutedLocalMac, unmutingLocalMac
        case releasingLocalLimit, awaitingLocalProgram, audibleMacAwaitingTV
    }

    enum Action: Equatable { case none, toMac, toTV, muteLocal, unmuteLocal }

    private(set) var phase: Phase = .idle

    @discardableResult
    mutating func begin() -> Bool {
        guard phase == .idle else { return false }
        transition(to: .starting)
        return true
    }

    @discardableResult
    mutating func startedOnTV() -> Bool {
        complete(from: .starting, to: .watchingTV)
    }

    @discardableResult
    mutating func startedOnMac() -> Bool { complete(from: .starting, to: .watchingMac) }

    @discardableResult
    mutating func mutedLocally() -> Bool { complete(from: .mutingLocalMac, to: .mutedLocalMac) }

    @discardableResult
    mutating func unmutedLocally() -> Bool { complete(from: .unmutingLocalMac, to: .watchingMac) }

    /// The timeout releases sound without rearming on the same commercial.
    @discardableResult
    mutating func localMuteLimitReached() -> Bool {
        complete(from: .mutedLocalMac, to: .releasingLocalLimit)
    }

    @discardableResult
    mutating func localLimitReleased() -> Bool {
        complete(from: .releasingLocalLimit, to: .awaitingLocalProgram)
    }

    /// Sound has been restored on the Mac; keep listening for a confirmed TV return.
    @discardableResult
    mutating func airPlayLimitReleased() -> Bool {
        complete(from: .mutedMac, to: .audibleMacAwaitingTV)
    }

    mutating func confirmed(_ state: GeminiConfirmation.State) -> Action {
        switch (phase, state) {
        case (.awaitingLocalProgram, .program):
            transition(to: .watchingMac)
            return .none
        case (.watchingMac, .commercialBreak):
            transition(to: .mutingLocalMac)
            return .muteLocal
        case (.mutedLocalMac, .program):
            transition(to: .unmutingLocalMac)
            return .unmuteLocal
        case (.watchingTV, .commercialBreak):
            transition(to: .movingToMac)
            return .toMac
        case (.mutedMac, .program), (.audibleMacAwaitingTV, .program):
            transition(to: .movingToTV)
            return .toTV
        default:
            return .none
        }
    }

    @discardableResult
    mutating func reachedMac() -> Bool {
        complete(from: .movingToMac, to: .mutedMac)
    }

    @discardableResult
    mutating func reachedTV() -> Bool {
        complete(from: .movingToTV, to: .watchingTV)
    }

    /// Only use when routing certifies that no destination press was attempted.
    @discardableResult
    mutating func pickerUnavailable() -> Bool {
        switch phase {
        case .movingToMac: transition(to: .watchingTV)
        case .movingToTV: transition(to: .audibleMacAwaitingTV)
        default: return false
        }
        return true
    }

    /// Prevents further prediction-driven actions while the controller restores audible playback.
    mutating func recover() {
        guard phase != .idle, phase != .recovering else { return }
        transition(to: .recovering)
    }

    mutating func stop() {
        transition(to: .idle)
    }

    private mutating func complete(from: Phase, to: Phase) -> Bool {
        guard phase == from else { return false }
        transition(to: to)
        return true
    }

    private mutating func transition(to next: Phase) {
        phase = next
    }
}
