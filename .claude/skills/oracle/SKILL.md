---
name: oracle
description: Run, add or debug a compat oracle — an upstream gem's own test suite (rspec-core, rspec-expectations, rspec-mocks, minitest, webmock, vcr, faker, factory_bot, database_cleaner, simplecov) executed against fast_rspec. Use when implementing or changing any drop-in surface, when an oracle fails, or when bumping an oracle's pinned SHA.
---

# Compat oracles

Upstream's suites are the spec (`docs/idea/09-compat-oracles.md`). Divergence = we're wrong, unless listed in `docs/idea/parity-divergences.md`.

## Layout
`apps/fast-rspec/test/oracles/<gem>/` — `.sha` (pinned upstream commit), `Gemfile` overlay, `run` (script), `skip.txt` (known-failing ids, each with a reason + issue link; only shrinks).

## Run
```bash
bin/rake test:oracles                 # all
bin/rake test:oracles ORACLE=minitest # one
```
Output: pass/fail/skip counts + % → update `docs/compat.md` (only goes up).

## Debug a failure
1. Run the single upstream test under **stock** upstream to confirm it passes there.
2. Run it under fast_rspec with `FAST_RSPEC_WORKERS=1` — serial first; parallel-only failures → `debug-parallel` skill.
3. Read upstream source (`gem contents <gem>`) for the behavior; check `docs/target/<file>.md`; fix the doc if it was wrong.
4. Fix our implementation (public behavior only, never copy source). Add a focused unit test in `apps/fast-rspec/test/unit/`.
5. Remove the id from `skip.txt` if it was there.

## Add / bump
New oracle: clone at a release tag, record `.sha`, write `run`, start with a full `skip.txt`, then burn it down. Bump: one PR per gem, only merged on green.
