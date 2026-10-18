# October 11: reported screen saver and Automatic stop

Nick reported that the screen saver appeared and stopped the app. Read-only
inspection found this sequence (America/Chicago):

- 13:21:19: Mac route confirmed and system capture muted.
- 13:23:42: one program result; 13:23:47: not_program resets return evidence.
- 13:23:51 request timed out at 13:24:11; bounded recovery began.
- 13:24:18: one fresh program result, insufficient for return confirmation.
- 13:24:19: Automatic stopped explicitly with `Three-minute muted limit reached`.
- 13:24:21: TV recovery route confirmed.

Source: `automatic-E090AFAD-0A82-493F-BB87-B60CB8E507FC.jsonl` and the
`2FFB5B29-8A6D-4D89-BBA2-1461BF5323FC` session's Gemini observations under
Application Support/SkyboxAudioProbe. These logs establish the app's stop
reason; they do not establish when the screen saver initially appeared.
The inspected loginwindow events include unlock at 13:28:26, but the narrow
screen-saver queries did not yield a start timestamp.

Automatic's stop releases both keep-awake mechanisms, so a subsequent screen
saver is expected. It is not established that v0.2.42's refresh failed while
Automatic was enabled. No playback controls, app restart or preference changes
were issued during this investigation.

Nick was asked to choose the long-break behavior: remain muted and detect until
program returns, or restore Mac sound at three minutes while continuing
detection. The existing cutoff should not be confused with a detector crash.

Nick clarified that this was halftime and chose unmute after three minutes.
v0.2.43 restores Mac sound while keeping detection and keep-awake running,
then waits for fresh confirmed program to return to TV. No further screen-saver
change is justified by this incident alone.
