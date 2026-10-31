---
name: benchmark
description: Measure fast_rspec performance and compare before/after a change, or against stock rspec / minitest / parallel_tests / upstream batteries. Use when a change claims or may affect speed, boot cost or allocations, or the user asks to benchmark, profile or compare.
---

# Benchmark fast_rspec (before/after)

Pillar 3: no claim without numbers. Numbers go in `docs/benchmarks.md`.

## Tools
| Command | Measures |
|---|---|
| `bundle exec rake bench` | vs our own past self: boot, per-example cost, scheduler, IPC |
| `bundle exec rake bench:vs_stock` | vs stock rspec, minitest, `rails test`, parallel_tests, upstream batteries |
| `bundle exec ruby -e '…require…'` + `GC.stat(:total_allocated_objects)` | require cost / allocations |
| `stackprof`, `memory_profiler` | where time / allocations go (parent and worker) |

Variants: `--yjit`, `FAST_RSPEC_DISABLE_EXT=1`, `FAST_RSPEC_WORKERS=1|N`, `FAST_RSPEC_POOL=fork|thread|spawn`.

## Procedure
1. Record environment: `ruby -v`, `nproc`, `uname -m`, variant flags.
2. **Baseline** without worktrees or stash: `git archive <base-rev> | tar -x -C "$SCRATCH/base"`, `bundle install && bundle exec rake compile` there, run the command, save output.
3. **Candidate**: in this checkout, `bundle exec rake compile`, identical command, save output.
4. Repeat each side ≥ 2× if delta < 10%; overlapping error bars = "no measurable change".
5. Correctness: `bin/check`.
6. Report: table (benchmark, before, after, ratio, error) + environment line. Never round away regressions. Delete `$SCRATCH/base`.
