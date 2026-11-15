/// Opening the AirPlay picker while Commercial Breaker is in front can return focus
/// to it right after Safari activates: at startup (October 18) and after Stop
/// (November 14). `RoutingModel.routeForAutomation` wraps only its steps before any
/// destination selection in this rule, so a retry can never repeat a selection.
enum FocusBounceRetry {
    /// Runs `attempt`, retrying once if the route is `eligible`, it failed because focus
    /// returned to Commercial Breaker, and Commercial Breaker is still frontmost after
    /// `pause`. An ineligible bounce is rethrown at once, without the pause. `beforeRetry`
    /// runs just before the second attempt. Every other failure, including focus moving
    /// to another app and cancellation during the pause, is rethrown unchanged.
    @MainActor
    static func run<T>(
        eligible: Bool,
        pause: () async throws -> Void,
        ownAppFrontmost: () -> Bool,
        beforeRetry: () async -> Void,
        attempt: () async throws -> T
    ) async throws -> T {
        do {
            return try await attempt()
        } catch let failure as RoutingFailure where eligible && failure.focusReturnedToCommercialBreaker {
            try await pause()
            guard ownAppFrontmost() else { throw failure }
            await beforeRetry()
            return try await attempt()
        }
    }
}
