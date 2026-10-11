import Foundation
import IOKit.pwr_mgt

/// Refreshes user activity during an automatic viewing session. Call on the main thread.
/// Unlike a display-sleep assertion alone, this also reports ongoing viewing activity.
final class ViewingActivity {
    typealias Declare = (inout IOPMAssertionID) -> IOReturn
    private let declare: Declare
    private let release: (IOPMAssertionID) -> Void
    private var assertion = IOPMAssertionID(kIOPMNullAssertionID)
    private var lastRefresh: TimeInterval?
    private(set) var enabled = false

    init(declare: @escaping Declare = { id in
        IOPMAssertionDeclareUserActivity("Skybox automatic viewing" as CFString,
                                        kIOPMUserActiveLocal, &id)
    }, release: @escaping (IOPMAssertionID) -> Void = { _ = IOPMAssertionRelease($0) }) {
        self.declare = declare
        self.release = release
    }

    func start() { enabled = true; lastRefresh = nil }

    /// Returns an error only when a refresh was attempted and failed.
    func refresh(now: TimeInterval) -> IOReturn? {
        guard enabled, now.isFinite,
              lastRefresh.map({ now - $0 >= 30 }) ?? true else { return nil }
        lastRefresh = now
        let result = declare(&assertion)
        return result == kIOReturnSuccess ? nil : result
    }

    func stop() {
        enabled = false
        lastRefresh = nil
        if assertion != kIOPMNullAssertionID {
            release(assertion)
            assertion = IOPMAssertionID(kIOPMNullAssertionID)
        }
    }

    deinit { stop() }
}
