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

`npm run lint` checks blank lines between JavaScript statements, and CI runs it. This is
the rule's one description; `eslint.config.mjs` points here. A blank line goes:

- after the imports;
- before a `return` that follows another statement in its block, even a one-line one;
- before and after a multi-line `const` or `let` declaration, expression statement or `export`;
- before and after a multi-line statement that ends with the closing `}` of a block: a
  function, `if`, loop, `switch` or `try`, an immediately invoked function, or a brace-less
  `if` whose body ends in a multi-line arrow function.

Nothing else needs one: runs of one-line statements stay together, and so do a multi-line
`class` and a brace-less `if` or `throw` that spans lines without ending in a block.
`npm run lint -- --fix` adds missing blank lines but never re-indents. Don't put a `return`
or a multi-line statement on the same line as another, as in `{ a(); return; }`: `--fix`
splits that line without re-indenting it, and lint passes the result.

Do not commit recordings, stream-session URLs, bearer tokens, keys, `.env` files,
or build output. Preserve useful synthetic regression fixtures and findings.
Historical experiment notes are evidence, not current setup instructions.

The current extension is JavaScript. TypeScript/React migration is planned as a
separate change with behavior parity; it is not a prerequisite for small fixes.
