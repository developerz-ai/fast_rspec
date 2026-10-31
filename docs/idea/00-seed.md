# 🌱 FastRspec — Seed

**One gem line replaces your whole test stack, and it runs on every core.**

## Pitch

Today: ~12 test gems + ~9 `test/support/*.rb` files hand-wired per app, and `parallelize` / parallel_tests bolted on top. You need to be an expert to get it right: sequences that collide across workers, VCR cassettes written by two workers at once, Capybara ports that clash, coverage that never merges. Every app re-solves the same problems.

FastRspec: `gem 'fast_rspec'`. Done. RSpec and Minitest themselves are rebuilt lean (upstream RSpec: ~32.5k LOC, 216 ms to `require`, 2.7 s per 10k trivial examples). Same `rspec` / `rails test` commands, all cores, every battery wired the way an expert would.

## Three pillars

1. **100% drop-in.** RSpec + Minitest + `ActiveSupport::TestCase`, unchanged files, flags, output and exit codes. → [01-overview.md](01-overview.md)
2. **Zero config.** Detect, wire, step aside if the user already did. → [06-batteries.md](06-batteries.md)
3. **Measured.** Parallel by default; speed is claimed only with numbers. → [08-performance.md](08-performance.md)

## Doc index

| File | Topic |
|---|---|
| [01-overview.md](01-overview.md) | What / who / non-goals / the drop-in promise |
| [02-architecture.md](02-architecture.md) | Layers, wrap-don't-rewrite, process tree |
| [03-runner.md](03-runner.md) | Preload → pool → work-stealing → results |
| [04-rspec-adapter.md](04-rspec-adapter.md) | Our RSpec: build order, mechanics |
| [05-minitest-adapter.md](05-minitest-adapter.md) | Our Minitest + `ActiveSupport::TestCase` |
| [06-batteries.md](06-batteries.md) | Bundled gems, detection, defaults, off switches |
| [07-isolation.md](07-isolation.md) | Per-worker DB / Redis / tmp / ports / sequences / seeds |
| [08-performance.md](08-performance.md) | Every optimization, C ext vs PureRuby, bench rules |
| [09-compat-oracles.md](09-compat-oracles.md) | Upstream suites as truth |
| [10-testing-ci.md](10-testing-ci.md) | Own suite, demo apps, CI matrix |
| [11-roadmap.md](11-roadmap.md) | Milestones |
| [prior-art.md](prior-art.md) | ExUnit, Ecto sandbox, parallel_tests, test-queue, turbo_tests, … |
| [parity-divergences.md](parity-divergences.md) | Intentional differences from upstream (should stay ~empty) |

Compat targets (exact upstream surfaces we must keep working): [`../target/`](../target/README.md).
