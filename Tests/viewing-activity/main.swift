import Foundation
import IOKit.pwr_mgt

var calls = 0
var released: [IOPMAssertionID] = []
var fail = false
var activity: ViewingActivity? = ViewingActivity(declare: { id in
    calls += 1
    if fail { return kIOReturnError }
    // The OS may replace the identifier on refresh; the latest one must be released.
    id = IOPMAssertionID(calls)
    return kIOReturnSuccess
}, release: { released.append($0) })
assert(activity!.refresh(now: 1) == nil && calls == 0)
activity!.start()
assert(activity!.refresh(now: 1) == nil && calls == 1)
assert(activity!.refresh(now: 30.9) == nil && calls == 1)
assert(activity!.refresh(now: 31) == nil && calls == 2)
fail = true
assert(activity!.refresh(now: 61) == kIOReturnError && calls == 3)
assert(activity!.refresh(now: 62) == nil && calls == 3)
activity!.stop()
activity!.stop()
assert(released == [2])
assert(activity!.refresh(now: 100) == nil && calls == 3)
fail = false
activity!.start()
assert(activity!.refresh(now: 101) == nil && calls == 4)
activity = nil
assert(released == [2, 4])
print("Viewing activity checks passed: cadence, identifier replacement, failure, stop/restart, deinit")
