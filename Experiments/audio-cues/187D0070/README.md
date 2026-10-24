# First fixed transition-rule replay

Session `187D0070-24CE-475F-B1F5-02DDC6C473D6`, September 27, 2026.
Original event logs are unchanged. `cue-summary-reviewed.json` records the user's
clarification that both game changes landed on a game in progress. Other football
intervals assume no unmarked breaks; the initial interval stays unknown.

The exploratory rule requires music rising while crowd fades, sustained across two
consecutive analysis windows. It compares those windows with disjoint preceding
context (at least 15 seconds, within a 30-second history). Absolute scores and
relative changes are combined; see `candidate-evaluation.json` for every threshold.
No network names, songs, user marker states, or absolute loudness enter the rule.
Changing games or losing continuity resets its history. There is a 30-second
cooldown. The rule detects candidate starts only, not returns.

## Result

Exactly two candidates across 11 minutes 55 seconds:

| Candidate | Relative to nearby commercial click |
|---|---:|
| First | 9.79 seconds before |
| Second | 7.54 seconds after |

No additional candidates were emitted. These are click-relative offsets, not true
broadcast latency: clicks are approximate and the audio windows are three seconds
long. This recording had already been inspected before choosing the hypothesis;
this is an exploratory fit check, not held-out validation, accuracy, precision,
or proof of zero false alarms. There is no demonstrated return detector.

The rule is frozen for prospective observation. Keep playback manual and use the
existing markers on new footage to evaluate missed starts, extra candidates, and
delay. Do not relax thresholds merely to fit these two breaks.

## Reproduce

```sh
python3 -m unittest discover -s Tests/cue-candidates
python3 Tools/evaluate-cue-candidates.py \
  Experiments/audio-cues/187D0070/cue-summary-reviewed.json \
  /tmp/skybox-candidate-evaluation.json
```
