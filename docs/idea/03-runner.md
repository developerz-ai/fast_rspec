# ⚙️ Runner

## Architecture pick: Puma-style preload + fork (decided 2026-10-31)
All cores by default. Same playbook as Puma's `preload_app!` + `fork_worker`:

1. **Boot clean in the parent**: load app + helpers + support files, eager-load (CI), warm lazy caches (I18n, factories, faker tables).
2. **Make memory fork-friendly**: `GC.start(full_mark: true, immediate_sweep: true)` ×3 → `GC.compact` → `Process.warmup` (Ruby 3.3+) → close DB/Redis/HTTP sockets. Old objects promoted and compacted = pages stay shared (copy-on-write) across workers.
3. **Fork N = cores** workers; each reconnects, takes its isolation slot, enables YJIT.
4. **Refork** (Puma `fork_worker` idea, ⚙️): after worker 0 finishes its first units (hot YJIT code, warmed caches), new/replacement workers fork from *it*, not the cold parent.
5. **Workers pull work** (work-stealing) until the queue is empty; parent only dispatches and reports.

| Alternative | Verdict |
|---|---|
| Ractors | ❌ v1 — user code, ActiveRecord, globals and mutable constants aren't Ractor-shareable; 🔬 later for the pure engine (scheduler, result encoding) |
| Threads (CRuby) | ❌ GVL serializes Ruby; fine only for IO-bound suites |
| Spawn N processes (parallel_tests) | ❌ pays boot N times; kept only as `FAST_RSPEC_POOL=spawn` fallback |
| Threads (JRuby/TruffleRuby) | ✅ no GVL — real parallelism; per-thread isolation ([07-isolation.md](07-isolation.md)) |

## Flow
1. **Discover** files (from args, `.rspec`, `test/**/*_test.rb`). No loading yet beyond the helper.
2. **Preload** helper + app once in the parent (bootsnap honored).
3. **Plan** units: files by default; split slow files into example/test-method units when one file > `total/N`.
4. **Order** longest-first from the runtime log `tmp/fast_rspec/runtime.log` (unknown files: by size). Seeded shuffle within equal buckets when `--order rand`.
5. **Fork/spawn** N workers; each pulls the next unit (work-stealing → no idle tail).
6. **Stream** results back (one message per unit, compact binary/Marshal; C ext for encode/decode on CRuby).
7. **Report** in the parent through upstream's reporter/formatters, de-interleaved.
8. **Persist** runtime log, `--only-failures` status file, merged coverage.

## Defaults
| Knob | Default | Override |
|---|---|---|
| workers | `Etc.nprocessors` | `-n N`, `FAST_RSPEC_WORKERS` |
| pool | fork (CRuby), thread (JRuby/Truffle) | `FAST_RSPEC_POOL=fork\|thread\|spawn` |
| small suite | run serial when units < 2×N or est. < 1s (no fork tax) | `--parallel` forces |
| fail fast | honored across workers (broadcast stop) | `--fail-fast` |

## Must-haves
- One-line repro on failure: `fast_rspec -n1 --seed 1234 spec/a_spec.rb spec/b_spec.rb` (the failing worker's unit sequence).
- Ctrl-C: first = graceful (finish units, report), second = kill.
- Crash of a worker → its in-flight unit re-queued once, then reported as an error.
