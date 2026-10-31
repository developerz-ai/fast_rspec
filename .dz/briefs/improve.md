# Brief: monthly improvement

Fired every Monday by `schedules: improve`. **Act only on the first Monday of the month (UTC day 1-7);
otherwise stop.** fast_rspec is maintained by agents only. Once a month, leave it measurably faster
and one step ahead of the next Ruby, Rails and RSpec/Minitest release. Read `AGENTS.md` first.

## 1. Canary first
`gh run list --workflow canary.yml --limit 1 --json conclusion,url,createdAt` (Ruby head, Rails edge,
rspec/minitest main). Fix ours; file upstream-linked issues for theirs, never shims. No run in 7 days →
`gh workflow run canary.yml` and read it before step 3.

## 2. At most three improvements, in this order
1. Anything the canary found.
2. Compat: open `compat`-labelled issues; failing oracles.
3. Speed: `bin/rake bench` on `main`; pick a trick from `docs/idea/08-performance.md` (🔬 → ✅). Counts only with before/after numbers in `docs/benchmarks.md`.
4. Correctness: open `bug` issues; flaky-under-parallel reports first.
5. Docs drift: `README.md`, `AGENTS.md`, `llms.txt`, `docs/target/*` still match the code and upstream.
6. Simplification: dead code, slow or flaky tests.

## 3. Ship
One PR per improvement, with evidence (canary log, bench table, failing test). User-visible →
CHANGELOG `## [Unreleased]`. Never bump the version here. Nothing worth changing → do nothing.
