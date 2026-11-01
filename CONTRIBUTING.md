# Contributing

Commercial Breaker is a community sports-viewing project in early development. Small,
reviewable contributions are welcome; reliability matters more than features.

Branch from `main` using `fix/`, `feat/` or `chore/` names and open a pull request.
Keep behavior fixes separate from large file moves or framework migrations.
Describe the problem, resulting behavior, checks run, and live checks still
needed. A passing build is not evidence that AirPlay or protected video works.
Do not merge a PR solely because its code compiles.

Run the relevant offline tests from README and the native runbook; the Tests
workflow runs them, plus an unsigned app build, on every pull request. For routing
or capture changes, test cancellation, failure recovery, mute release, and a
complete live break/return cycle. Never interrupt someone else's active playback
for automated verification. Gemini evaluations upload audio: use authorized
fixtures, not incidental room recordings.

Do not commit recordings, stream-session URLs, bearer tokens, keys, `.env` files,
or build output. Preserve useful synthetic regression fixtures and findings.
Historical experiment notes are evidence, not current setup instructions.

The current extension is JavaScript. TypeScript/React migration is planned as a
separate change with behavior parity; it is not a prerequisite for small fixes.
