---
description: End-to-end feature workflow for fast_rspec — understand, explore, build (parallel agents in this one checkout, no worktrees), gate on bin/check + oracles + bench, PR, merge. Tracks in GitHub issues.
argument-hint: <what you want built, plain language> [+ reference URL(s)]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent, SendMessage, TaskCreate, TaskUpdate, TaskList, Skill, WebFetch
---

# /feature

Senior engineer on **FastRspec**. Read [`AGENTS.md`](../../AGENTS.md) and [`docs/idea/00-seed.md`](../../docs/idea/00-seed.md) first. The three pillars (drop-in · zero config · measured) override everything below.

## Request
$ARGUMENTS

**The prompt is the context — read the intent.** "Just ship it" → run start-to-finish, merge on green, surface decisions in the PR body. Tentative ask → clarify the genuinely ambiguous, let the user review before merge. Always stop for a real blocker: a change that breaks drop-in, a "faster" claim without numbers, anything destructive.

## PR mode — one PR in flight, ≤100 files
- Cut PR-sized chunks before coding. Build → `bin/check` → PR → **merged** → `git pull` → clean tree → next chunk.
- Land shared primitives first (a `Detect` query, an isolation slot, a runner message type), consumers after. Never split a compile unit.

## Hive rules (one checkout, never worktrees)
- Hive only for **search** (broad sweeps) or **scale** (path-disjoint work). Small change → do it yourself.
- ≤4 agents at once; agents never spawn agents. You coordinate, own git, and the ledger.
- **The file set is the lock.** Each brief names its exclusive paths and every other live agent's paths. Collision → stop and report.
- Every brief: evidence first, hypothesis labelled **unverified**; no git ops; never "ask me" (decide-and-flag or stop-and-report); finish the whole slice.
- Re-task live agents with `SendMessage`; never a second agent on the same paths.

| | Agent | Coordinator (once, at the end) |
|---|---|---|
| lint | `bundle exec rubocop <its files>` | `bin/check` |
| tests | `bin/rake test TEST=<its files>` with `FAST_RSPEC_WORKERS=1` | `bin/check` (`full` if runner/adapters/batteries touched) |
| compat | the oracle for its battery/adapter | `bin/rake test:oracles` |
| perf | — | `bin/rake bench` when runner/hot paths touched |

## Flow
1. **Understand.** Goal in one line. Cited URLs → `WebFetch`, extract the mechanism. Check `docs/target/*.md` for the exact upstream surface involved.
2. **Explore (parallel).** Affected layers (`AGENTS.md` layout table), patterns to mirror (`file:line`), oracles that cover it, C ext ⇄ PureRuby twin impact.
3. **Track.** `gh issue list` → reuse or `gh issue create`; PR body `Fixes #NNN`.
4. **Build.** `git checkout -b feat/<slug>` on a clean tree. Tests with the code. C ext change → PureRuby twin + parity test in the same PR. Battery → `applies?` + `configured_by_user?` + idempotent `install!`.
5. **Verify.** `bin/check` green. Runner/adapter change → a sample app in `test/apps/` gives the same results serial and parallel. Perf claim → numbers in `docs/benchmarks.md`.
6. **PR + merge.** Sweep agent leftovers. `git add <paths>` (never `-A`, never `git stash`). Conventional Commit, scope = layer. `gh pr create` (Summary · Test plan · bench delta). Merge on green, confirm, `git pull`.
7. **Docs.** Update `AGENTS.md` commands table, `docs/idea/*`, `docs/target/*`, README, CHANGELOG in the same PR when behavior changed.

## Hard rules
Drop-in is sacred. User config wins. Every Ruby engine stays green. No "faster" claim without numbers. No mocks of DB/Redis in isolation tests. Never `--force`, `--no-verify`, `git stash`, worktrees.

## Output
```
Shipped:   <what>   PR #NNN <merged/open>
Gate:      bin/check <ok>  oracles <ok/n/a>  bench <delta/n/a>
Engines:   cruby <ok> jruby <ok> truffleruby <ok>
Deferred:  <n> — <what, why>        [never omit]
```
