# Crowd detection branch trial

Branch: `experiment/crowd-detection`. Local `main` at `2b07370` preserves the
pre-trial source, including the digital-silence guard. No remote was created.
Existing raw experiment artifacts remain local; this is a source baseline,
not the later productization/cleanup milestone.

Nick chose live judgment over further offline labeling for this trial.
Football workers now use the evaluated crowd-plus-commentary prompt and
`program` / `decision_usable` boolean schema on both microphone and system
capture. Unusable/ambiguous audio cannot establish program or a new break.
The AirPlay return leg maps usable negatives to `not_program` so it only supplies
return evidence. UFC keeps its previous prompts and schemas.

Two-result confirmation, five fresh seconds for program return, the existing
fast break follow-up and all routing behavior remain unchanged. The old
`transition_heard` output is not requested by this minimal variant. No estimated
transition timestamp or new transition-driven scheduling is implemented.

## Try it

The native app loads the worker from this checkout. A new automatic session or
capture handoff starts a new worker and picks up this branch without rebuilding
the app. Existing workers keep their loaded code. No stop/start, app relaunch,
extension reload or playback command was issued during implementation.

At your next convenient session start, select Football and use Automatic as
usual. Worker-ready log records identify `classifier: crowd-minimal-v1` and the
exact prompt hash. Mark missed breaks/early returns if convenient; those markers
do not control playback. Native remains v0.2.41 and extension source v0.2.21.

To revert, stop Automatic at a convenient time, run `git switch main`, then
start a new session. Branch switching does not replace an already running
worker. Avoid switching during a handoff, which could start a worker mid-switch.

## Verification

- All 20 Gemini Node tests passed, including all usable/unusable boolean
  combinations for both standard detection and the return-only leg, plus
  malformed-output rejection.
- Swift confirmation checks passed. `git diff --check` passed.
- No new remote audio requests were made. Live quality is for Nick to assess.
