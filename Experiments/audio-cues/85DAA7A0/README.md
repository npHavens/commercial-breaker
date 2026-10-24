# Prospective check: fixed rule missed the marked break

Session `85DAA7A0-6867-4764-872F-FD56B19A9E4C` recorded for 522.15 seconds.
The live classifier logged 346 score windows, no error or discontinuity events,
and no break candidates. The recorder saved one complete 30-second commercial-start
clip, with no reported dropped blocks. There were no game-change or return markers.

The user marked a commercial at uptime 571732.7593361667. The frozen
`music-rise-crowd-drop-v1` rule emitted no signal, so this is a missed marked start
in prospective data. Replaying the same rule reproduces the absence of candidates;
this is not a failure of the UI or missing classifier output.

Around the marker, preceding crowd scores averaged about 0.04, below the required
0.08 baseline. The rule therefore could not trigger even when music rose. At the
analysis window ending about 3.34 seconds after the click, the two-window music and
relative crowd conditions passed, but the baseline-crowd requirement still blocked
it. Nearby windows also fail music persistence or crowd-drop conditions.

Conclusion: requiring a sufficiently strong crowd baseline is not robust to this
recording. The data do not establish whether low crowd scores reflect the actual
broadcast mix, quiet/distant capture, room sounds, or classifier error. Do not
simply lower the threshold and claim a fix; replay any revised rule against both
sessions and validate again on unseen footage. Existing rule and playback behavior
remain unchanged. Initial footage has no explicit football marker, so do not claim
verified football false-alarm coverage across the whole session.
