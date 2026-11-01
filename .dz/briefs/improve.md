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
3. Speed: run `bin/rake bench` on `main`; pick a trick from `docs/idea/08-performance.md`
   (🔬 → ✅). If the bench launcher or rake task is unavailable (missing command, abort like
   Rakefile's `abort 'bench: not implemented yet'`, or a non-zero exit), record the speed step as an
   explicit BLOCKED result in the run report: the exact command and its failure output. Never record
   it as passed and never skip it silently. Only real before/after numbers, measured by a working
   benchmark and recorded in `docs/benchmarks.md`, count as performance evidence; a blocked run, an
   estimate or a fabricated number never does.
4. Correctness: open `bug` issues; flaky-under-parallel reports first.
5. Docs drift: `README.md`, `AGENTS.md`, `llms.txt`, `docs/target/*` still match the code and upstream.
6. Simplification: dead code, slow or flaky tests.

## 3. Ship
One PR per improvement, with evidence (canary log, bench table, failing test). User-visible →
CHANGELOG `## [Unreleased]`. Never bump the version here. Nothing worth changing → do nothing.
