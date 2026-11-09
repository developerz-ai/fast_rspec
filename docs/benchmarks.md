# 📊 Benchmarks

Every speed claim in README / llms.txt must point here. Same machine per table; record `ruby -v`, cores, worker count.

## Baselines — upstream (2026-10-31)
Ruby 3.4.7 (+PRISM, YJIT off), x86_64-linux. `require` measured in a fresh process (includes the gem's own dependencies). 10k-example run = one file of 10,000 trivial examples, serial.

| Upstream | LOC | `require` | Allocations | 10k trivial examples |
|---|---|---|---|---|
| rspec-core + -expectations + -mocks (+ -support) 3.13 | ~32.5k | 216 ms | 84k | 2.71 s, 72 MB RSS |
| minitest 6.0.6 | ~5.3k | 92 ms | 48k | 0.45 s, 34 MB RSS |
| webmock 3.34 | ~5.6k | 1291 ms | 381k | — |
| capybara 3.40 | ~26.9k | 553 ms | 171k | — |
| faker 3.8 | ~22.4k + 318 YAML | 428 ms (+ 1016 ms first call) | 121k | — |
| factory_bot 6.6 | ~3.0k | 213 ms | 82k | — |
| vcr 6.4 | ~4.9k | 145 ms | 65k | — |

## fast_rspec
Measured 2026-11-01 with `bench/run.rb`: median of 15 fresh `ruby -I lib` processes, serial. `ruby 3.4.11 (2026-09-23 revision 592f1ffdb3) +PRISM [x86_64-linux]`, YJIT off, 8 cores, native C extension (`FastRspec::Render.native?` = true).

| Metric | Result | Target |
|---|---|---|
| `require "fast_rspec"` | 1.03 ms | < 20 ms |
| Allocations during `require` | 86 | < 5k |
| 10,000 empty blocks, serial (harness floor, no engine) | 0.0035 s | < 0.5 s (10k trivial examples) |

No example engine exists yet (`lib/fast_rspec/engine/` is empty), so the 10k row is the cost of calling 10,000 empty `proc {}` serially, not an example-run number. The `require` row covers only the scaffold (`Configuration`, `Detect`, `Render` are autoloaded). Neither row is comparable with the upstream baselines above until the engine lands. The targets (`require` < 20 ms / < 5k allocs; 10k trivial examples serial < 0.5 s) are targets, not claims.

Reproduce: `cd apps/fast-rspec && bundle exec rake bench` (`BENCH_RUNS=N` changes the sample count).
