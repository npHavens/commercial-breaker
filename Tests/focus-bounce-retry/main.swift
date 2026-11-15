import Foundation

let bounce = RoutingFailure(message: "Focus moved away from Safari", focusReturnedToCommercialBreaker: true)
let otherApp = RoutingFailure(message: "Focus moved away from Safari (frontmost: another app)")
let missingRows = RoutingFailure(message: "AirPlay picker did not expose the required destination rows", retryableBeforeSelection: true)

struct Run: Equatable {
    var result: String
    var attempts = 0, pauses = 0, retryNotes = 0
}

/// Runs the retry with scripted attempt outcomes. `result` is the value returned by
/// the attempt that succeeded, or the message of the failure that was thrown.
@MainActor
func run(_ outcomes: [RoutingFailure?], eligible: Bool = true, ownAppFrontmost: Bool = true, cancelDuringPause: Bool = false) async -> Run {
    var run = Run(result: "")
    do {
        run.result = try await FocusBounceRetry.run(
            eligible: eligible,
            pause: {
                run.pauses += 1
                if cancelDuringPause { throw CancellationError() }
            },
            ownAppFrontmost: { ownAppFrontmost },
            beforeRetry: { failure in
                assert(failure.focusReturnedToCommercialBreaker)
                run.retryNotes += 1
            },
            attempt: {
                defer { run.attempts += 1 }
                if let failure = outcomes[run.attempts] { throw failure }
                return "attempt \(run.attempts + 1)"
            })
    } catch let failure as RoutingFailure {
        run.result = failure.message
    } catch is CancellationError {
        run.result = "canceled"
    } catch {
        run.result = "\(error)"
    }
    return run
}

@main
struct FocusBounceRetryTests {
    @MainActor
    static func main() async {
        // Success on the first attempt never pauses or retries.
        var r = await run([nil]); assert(r == Run(result: "attempt 1", attempts: 1))
        // A focus bounce with Commercial Breaker still in front retries once, after the
        // pause and the retry note, and returns the second attempt's value.
        r = await run([bounce, nil]); assert(r == Run(result: "attempt 2", attempts: 2, pauses: 1, retryNotes: 1))
        // A second bounce is not retried again.
        r = await run([bounce, bounce]); assert(r == Run(result: bounce.message, attempts: 2, pauses: 1, retryNotes: 1))
        // If another app took the front during the pause, stop instead of acting there.
        r = await run([bounce, nil], ownAppFrontmost: false); assert(r == Run(result: bounce.message, attempts: 1, pauses: 1))
        // Cancellation during the pause (Stop again, shutdown): this call makes no second attempt.
        r = await run([bounce, nil], cancelDuringPause: true); assert(r == Run(result: "canceled", attempts: 1, pauses: 1))
        // A route that began in another app stops on a bounce at once, without pausing.
        r = await run([bounce, nil], eligible: false); assert(r == Run(result: bounce.message, attempts: 1))
        // Focus lost to another app, or missing picker rows, are not this retry's to handle.
        r = await run([otherApp, nil]); assert(r == Run(result: otherApp.message, attempts: 1))
        r = await run([missingRows, nil]); assert(r == Run(result: missingRows.message, attempts: 1))
        print("focus-bounce-retry: ok")
    }
}
