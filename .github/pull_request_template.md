## What & why

<!-- One or two sentences. Link issues: Fixes #123 -->

## Changes

-

## Checklist

- [ ] `bin/check` passes (`full` if runner, adapters or batteries changed)
- [ ] Drop-in: no user file needs editing; flags, output, exit codes unchanged (or listed in `docs/idea/parity-divergences.md`)

**Serial/parallel parity on the demo apps — tick exactly one status; only Verified means met.** `bin/check full` does NOT perform this comparison: `test:apps` runs `bin/stacks` per demo app but varies `STACK` only, never `FAST_RSPEC_WORKERS`. A green `bin/check full` is not parity evidence.

- [ ] **Verified** — BOTH runs pasted, per-suite counts (`N ex, M fail`) compared and identical, same app+suite:
  - `FAST_RSPEC_WORKERS=1 demo/ruby/bin/stacks` (serial)
  - `FAST_RSPEC_WORKERS=4 demo/ruby/bin/stacks` (parallel; leaving `FAST_RSPEC_WORKERS` unset = default worker count, also acceptable)
  <!-- Paste both count matrices and the per-suite comparison here. One run, one stack, or upstream-only output is not evidence. Add STRICT=1 so a failing fast_rspec run gates too. -->

- [ ] **Blocked (unmet)** — the requirement stays open. Name the blocker and the exact verifying command for when it clears:
  <!-- Blocker: … Verifying command: FAST_RSPEC_WORKERS=1 demo/ruby/bin/stacks, then FAST_RSPEC_WORKERS=4 demo/ruby/bin/stacks, counts compared identical. Not a waiver — a PR merging with this tick has not met the requirement. -->

- [ ] **Not applicable** — the change cannot touch parallel execution (docs/design prose only). One-line justification:
  <!-- Why parallelism is untouched. Never a stand-in for "didn't run it". -->

- [ ] C change mirrored in `apps/fast-rspec/lib/fast_rspec/render/pure_ruby.rb` (parity test passes)
- [ ] CRuby, JRuby, TruffleRuby green
- [ ] `CHANGELOG.md` `## [Unreleased]` updated for user-visible changes
- [ ] `AGENTS.md` / `README.md` / `docs/` updated if commands or behavior changed

## Performance (if relevant)

<!-- Before/after from `bin/rake bench`, same machine. Include `ruby -v` (YJIT?) and worker count. -->

| Suite | Before (s) | After (s) | Ratio |
|---|---|---|---|
