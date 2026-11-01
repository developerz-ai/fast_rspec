---
name: new-battery
description: Add or extend a rebuilt battery (our lean implementation of an upstream gem's public API — webmock, vcr, faker, factory_bot, database_cleaner, simplecov) or a wiring for an upstream gem we don't rebuild (shoulda, capybara, devise, sidekiq). Use when implementing a battery, adding API surface to one, or wiring a new third-party gem.
---

# New battery / wiring

First decide: **rebuild or wire?** Use the verdict table in `docs/idea/06-batteries.md`. Rebuild only when upstream taxes every run or every test and the surface is bounded.

## Rebuilt battery (`apps/fast-rspec/lib/fast_rspec/batteries/<name>/`)
1. Spec: `docs/target/<file>.md` covers the public API. Missing → write that section first from upstream source (`gem contents <gem>`).
2. Constant + require paths: upstream constant (`WebMock`, `Faker`, …); shim every upstream require path in `apps/fast-rspec/lib/compat/`.
3. Lazy: nothing loads until `applies?`; sub-features autoload.
4. Wiring: `applies?` (pure detect) · `configured_by_user?` (detect user calls, not state) · idempotent `install!`.
5. Parallel: per-worker isolation for anything it writes/shares (`docs/idea/07-isolation.md`); thread-safe under the thread pool.
6. Oracle: `apps/fast-rspec/test/oracles/<gem>/` (see `oracle` skill); target ≥ 90% before removing the upstream fallback.
7. Bench: require cost + hot path vs upstream (`benchmark` skill); numbers in `docs/benchmarks.md`.
8. Docs: README battery table, `AGENTS.md` if layout changed, CHANGELOG.

## Wiring (`apps/fast-rspec/lib/fast_rspec/wiring/<name>.rb`)
Upstream gem stays in the user's Gemfile (never in our gemspec). Detect → configure the way an expert would (per-worker ports/browsers/DBs, known upstream bug fixes) → step aside if the user configured it.

Never copy upstream source. Never add a runtime dependency.
