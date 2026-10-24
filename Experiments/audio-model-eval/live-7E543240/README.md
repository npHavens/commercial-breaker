# First live two-prediction confirmation session

September 27, 2026, microphone source, v0.2.15. Nick clarified that the single
Football returned marker represents switching to another game already playing.
This is not an observed natural return from the original channel's break.
Original event and prediction logs remain unchanged.

Both commercial markers were followed by confirmed Break: +9.59s and +9.45s.
The game-switch marker was followed by confirmed Football at +12.51s. Apart from
initial football confirmation, these were the only confirmed-state changes.
No extra confirmed break occurred between the markers in this session. This is
agreement with approximate user labels, not independently measured accuracy.

84 requests yielded 84 predictions and no failures. Median response 1.548s,
maximum 3.065s; recorder reported zero dropped blocks. Eight unclear predictions
interrupted pending streaks without creating opposing confirmed transitions.

Because Football returned does not reset the buffer, the channel switch was not
an explicit context reset. The live classifier adapted based on new audio. Use
Changed game for future channel switches so old audio and pending results are
invalidated; continue ordinary return markers when the same broadcast resumes.
No playback controls were enabled and no additional remote requests were made
for this review. More genuine break endings and promos remain useful tests.
