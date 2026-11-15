/// Opening the AirPlay picker while Commercial Breaker is in front can return focus
/// to it right after Safari activates: at startup (October 18) and after Stop
/// (November 14). The routing model marks that failure only before it selects a
/// destination, so retrying it cannot repeat a selection.
enum FocusBounceRetry {
    /// Runs `attempt`, retrying once if it failed because focus returned to Commercial
    /// Breaker and Commercial Breaker is still frontmost after `pause`. Every other
    /// failure, including focus moving to another app, is rethrown unchanged.
    /// Returns true when the retry is the attempt that succeeded.
    @MainActor
    static func run(
        pause: () async throws -> Void,
        ownAppFrontmost: () -> Bool,
        attempt: () async throws -> Void
    ) async throws -> Bool {
        do {
            try await attempt()
            return false
        } catch let failure as RoutingFailure where failure.focusReturnedToCommercialBreaker {
            try await pause()
            try Task.checkCancellation()
            guard ownAppFrontmost() else { throw failure }
            try await attempt()
            return true
        }
    }
}
