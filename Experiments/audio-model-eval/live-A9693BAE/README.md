# First live Gemini observation session

September 27, 2026, approximately 2:07–2:18 PM America/Chicago. Source microphone.
86 requests, 85 predictions; median response 1.466 seconds. No recorder drops reported.
Predictions: 50 football, 19 commercial, 3 promo, 13 unclear. These are model outputs,
not an accuracy score; the initial state is unmarked and markers are approximate.

A request at 2:10:41 PM reached the worker's 20-second timeout at 2:11:01 PM.
Version 0.2.13 intentionally disabled observation on every request error. The user
re-enabled it at 2:12:35 PM. Local capture continued. The log identifies timeout,
not the underlying provider/network cause; no raw provider error was retained.

First commercial result arrived 6.31 seconds after the commercial marker. Football
results stabilized 6.97 seconds after the return marker. Near return, a faint-audio
football result arrived 4.54 seconds before the marker, then commercial at +1.94s,
then football at +6.97/+12.66/+17.56s. This oscillation precludes treating a single
classification as a reliable unmute trigger. The actual transition has not been
independently annotated from audio. Quiet TV and room speech frequently yielded
unclear, and some explanations inferred content from nonspecific speech/music.

Version 0.2.14 recovers the first two consecutive worker-reported timeouts after
5 and 10 seconds using freshly captured audio. It clears stale predictions and
never resends the timed-out clip. A successful response resets the count; three
consecutive timeouts disable observation. Other errors and a hung worker still
stop observation. No automatic playback controls were added. Fake-worker tests
exercise recovery and fresh results without sending any audio to Google.
