import Foundation

let bounce = RoutingFailure(message: "Focus moved away from Safari", focusReturnedToCommercialBreaker: true)
let otherApp = RoutingFailure(message: "Focus moved away from Safari (frontmost: another app)")
// RoutingModel rethrows any failure after a selection without the focus flag.
let afterSelection = RoutingFailure(message: "Route was requested but could not be confirmed")

/// Runs the retry with scripted attempt outcomes; returns the retry flag or the thrown
/// message, how many attempts ran and how many pauses happened.
@MainActor
func run(_ outcomes: [RoutingFailure?], ownAppFrontmost: Bool = true) async -> (result: String, attempts: Int, pauses: Int) {
    var attempts = 0, pauses = 0
    do {
        let retried = try await FocusBounceRetry.run(
            pause: { pauses += 1 },
            ownAppFrontmost: { ownAppFrontmost },
            attempt: {
                defer { attempts += 1 }
                if let failure = outcomes[attempts] { throw failure }
            })
        return (retried ? "retried" : "first", attempts, pauses)
    } catch let failure as RoutingFailure {
        return (failure.message, attempts, pauses)
    } catch {
        return ("\(error)", attempts, pauses)
    }
}

@main
struct FocusBounceRetryTests {
    @MainActor
    static func main() async {
        // Success on the first attempt never pauses or retries.
        var r = await run([nil])
        assert(r == ("first", 1, 0))
        // A focus bounce with Commercial Breaker still in front retries once, after the pause.
        r = await run([bounce, nil])
        assert(r == ("retried", 2, 1))
        // A second bounce is not retried again.
        r = await run([bounce, bounce])
        assert(r == (bounce.message, 2, 1))
        // If another app took the front during the pause, stop instead of acting there.
        r = await run([bounce, nil], ownAppFrontmost: false)
        assert(r == (bounce.message, 1, 1))
        // Focus lost to another app, or any failure after a selection, is never retried.
        r = await run([otherApp, nil])
        assert(r == (otherApp.message, 1, 0))
        r = await run([afterSelection, nil])
        assert(r == (afterSelection.message, 1, 0))
        print("focus-bounce-retry: ok")
    }
}
