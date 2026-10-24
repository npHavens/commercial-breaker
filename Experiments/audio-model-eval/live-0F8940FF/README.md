# Two-prediction replay of the second live session

September 27, 2026. Analysis uses existing local prediction logs; no new audio
requests and no playback changes. Markers are approximate, not ground truth.

The suspected false commercial result appeared at 2:24:14 PM, 20.59 seconds
before the commercial marker, then reverted to football on the next sample.
Two consecutive break results would suppress it. The actual marked break first
produced commercial at +2.24 seconds and a second at +8.16 seconds. Confirmation
would add 5.91 seconds in this instance.

An isolated football classification at 2:25:15 during the marked break would
also be suppressed by two confirmations. However, two football results occur
at 2:27:05 and 2:27:10, 10.90 and 6.00 seconds before the return marker. We cannot
resolve whether the click was late or both predictions were wrong from these
logs. An unclear result follows near the marker; subsequent results alternate
football, promo, football. Thus two confirmations help isolated flips, but do
not establish reliable return detection. A stricter rule requiring two football
results after the marker would never complete before recording stopped, although
the actual system cannot and should not use user markers as classification input.

Replay groups commercial/promo as break, resets the pending streak on unclear or
failure, and changes the last confirmed state only after two consecutive matching
results. Enable/disable/context reset clears all state. This is an offline comparison,
not a deployed policy. Retaining a previous confirmed state through unclear is not
evidence that it remains current; stale/unknown handling must remain explicit in
any live display or future playback policy.

There were no request failures in this session, so it did not exercise timeout
recovery against the actual service. See summary.json for counts and latency.
