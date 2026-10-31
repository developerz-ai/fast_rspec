# AGENTS.md

Single source of truth for AI coding agents (Claude Code, Codex, Cursor, Copilot, ...) working **on** this repo.
`CLAUDE.md` is a symlink to this file. Edit only `AGENTS.md`.

## FastRspec

**One gem line replaces your whole test stack.** Drop-in for RSpec **and** Minitest (incl. `ActiveSupport::TestCase`), parallel on every core by default, and batteries bundled + auto-configured: factories, Faker, VCR, WebMock, database cleaning, shoulda, time helpers, Capybara, coverage. Rails and plain Ruby.

```ruby
# Gemfile — before: rspec-rails, factory_bot_rails, faker, vcr, webmock,
#   database_cleaner-active_record, shoulda-matchers, shoulda-context,
#   capybara, cuprite, simplecov, minitest-reporters, + 9 test/support/*.rb files
group :test do
  gem 'fast_rspec'
end
```

Then `bundle exec rspec`, `bin/rails test`, `rake test` — unchanged commands, all cores, zero config.

Three pillars, all must stay true:

1. **100% drop-in.** Existing `spec/`, `test/`, `.rspec`, `spec_helper.rb`, `rails_helper.rb`, `test_helper.rb`, `test/support/**` keep working untouched. Same CLI flags, same DSL, same matchers, same exit codes, same formatter output. Our RSpec/Minitest are clean reimplementations, so this is proven, never assumed: upstream's own suites (rspec-core features, rspec-expectations, rspec-mocks, minitest, plus every battery's suite) run against us in CI — `docs/idea/09-compat-oracles.md`.
2. **Zero config.** Detect what the app has (Rails, ActiveRecord, Sequel, Devise, Sidekiq/Wurk, Redis, ActiveJob, Capybara) and wire it. Hand-written config the user already has wins — we never double-configure. Every battery has an off switch.
3. **Measured.** Parallel by default is the claim; speed is the proof. `rake bench` vs our own past self (regression check) and `rake bench:vs_stock` vs stock `rspec` / `rails test` on real-shaped suites. **No "Nx faster" claim in README/llms.txt until `docs/benchmarks.md` has the numbers.**

Status (2026-10-31): **design phase.** Docs and agent setup only; no code yet. Start at [`docs/idea/00-seed.md`](docs/idea/00-seed.md).

## Core decision: our own lean RSpec + Minitest, upstream batteries

**RSpec and Minitest are reimplemented** — clean, lightweight, built for speed — on one shared engine. Same public API (`RSpec.describe`, `expect(...).to`, `allow(...)`, `Minitest::Test`, `assert_*`, `ActiveSupport::TestCase`), same constants, same `require` paths, same CLI. Users remove `rspec-*` gems; `require 'rspec/core'` / `require 'minitest'` resolve to ours.

Baseline we beat (2026-10-31, Ruby 3.4.7, this machine):

| | LOC | `require` | 10k trivial examples |
|---|---|---|---|
| rspec-core + -expectations + -mocks + -support 3.13 | ~32.5k | 216 ms, 84k allocs | 2.71 s, 72 MB RSS |
| minitest 6.0.6 | ~5.3k | 92 ms, 48k allocs | 0.45 s, 34 MB RSS |

**Most batteries are ours too** — same public API, lean internals, **zero runtime dependencies** in the gemspec. Rebuilt where upstream taxes every run or every test; shoulda + capybara are wired (auto-configured if in the user's Gemfile), not rebuilt. Verdict table: [`docs/idea/06-batteries.md`](docs/idea/06-batteries.md#️-which-ones-are-worth-rebuilding-decided-2026-10-31). `require` cost of upstream (same machine):

| Upstream | LOC | `require` | Note |
|---|---|---|---|
| webmock | ~5.6k | 1291 ms, 381k allocs | pulls addressable, public_suffix, crack, hashdiff |
| capybara | ~26.9k | 553 ms, 171k allocs | + driver gems |
| faker | ~22.4k + 318 YAML | 428 ms + **1016 ms first call** | parses every locale |
| factory_bot | ~3.0k | 213 ms (with activesupport) | |
| vcr | ~4.9k | 145 ms | |
| simplecov / database_cleaner / shoulda | small–medium | — | |

Each is rebuilt against its public API (documented in `docs/target/`) and proven by **its own upstream test suite** as an oracle. Until ours passes its oracle, a battery may delegate to the upstream gem if the user has it installed (`FastRspec::Battery#fallback`). Rationale + design: [`docs/idea/02-architecture.md`](docs/idea/02-architecture.md).

## Commands

Planned — fill in as each lands. Keep this table true; a row for a command that does not exist is a bug.

| Task | Command |
|---|---|
| Install | `bundle install` |
| Pre-PR gate | `bin/check` (`fast` = lint + unit · `full` = + oracles + ecosystem) |
| Own suite (parallel, dogfooded) | `bin/rake test` |
| Single file | `bin/rake test TEST=test/path/file_test.rb` |
| Upstream oracle suites | `bin/rake test:oracles` |
| Sample apps (Rails rspec / Rails minitest / plain Ruby) | `bin/rake test:apps` |
| Benchmarks | `bin/rake bench` · `bin/rake bench:vs_stock` |
| Lint | `bundle exec rubocop` |
| Build + install smoke | `bin/rake smoke` |

## Layout (planned)

| Layer | Owns | Path |
|---|---|---|
| Entry | `require 'fast_rspec'`, autoload, version, load-path shadowing | `lib/fast_rspec.rb` |
| Engine | Example/Group structs, hooks, `let` memo, world, filtering, ordering — framework-neutral | `lib/fast_rspec/engine/` |
| RSpec frontend | `RSpec` DSL → engine; expectations, matchers, mocks, `RSpec.configure` | `lib/fast_rspec/rspec/` |
| Minitest frontend | `Minitest::Test` / `Spec` → engine; assertions, plugins, reporters | `lib/fast_rspec/minitest/` |
| Rails frontend | rspec-rails spec types + `ActiveSupport::TestCase` integration | `lib/fast_rspec/rails/` |
| Shims | `lib/compat/{rspec,minitest}/**` — upstream `require` paths that load ours | `lib/compat/` |
| Detect | What the host has (Rails? AR? Devise? …) — pure, no side effects | `lib/fast_rspec/detect.rb` |
| Batteries | Our webmock / faker / vcr / database_cleaner / simplecov / factory_bot, each behind its upstream constant (`WebMock`, `Faker`, …) + auto-wiring (`applies?` · `configured_by_user?` · idempotent `install!`) | `lib/fast_rspec/batteries/<name>/` |
| Wiring | Auto-config for upstream gems we don't rebuild: shoulda, capybara/cuprite, devise, sidekiq/wurk, ActiveJob | `lib/fast_rspec/wiring/<name>.rb` |
| Runner | Preload, fork pool, supervision, work-stealing queue | `lib/fast_rspec/runner/` |
| Scheduler | Runtime log, longest-first, file → example splitting | `lib/fast_rspec/scheduler.rb` |
| Isolation | Per-worker DB (template clone), Redis DB, tmp dir, ports, ENV | `lib/fast_rspec/isolation/` |
| Reporter | Ordered, de-interleaved output; JSON/JUnit; merged coverage | `lib/fast_rspec/reporter/` |
| CLI | `exe/rspec`, `exe/fast_rspec` | `exe/` |

**Plain Ruby must run without loading Rails.** Rails bits load only when `defined?(Rails::Railtie)`.

## Conventions

- **SOLID, especially SRP.** Detect knows nothing about install; a battery knows nothing about the runner.
- **Drop-in is sacred.** Never change an upstream DSL, flag, exit code, or output format. A perf win that breaks compat is dropped.
- **Lean by construction.** Every RSpec/Minitest feature is implemented against `docs/target/*.md`, lazily loaded, and allocation-checked. No upstream internals copied in — public behavior only.
- **Idempotent batteries.** Before configuring X, check whether the user already did. Theirs wins. Log what we wired at `FAST_RSPEC_DEBUG=1`.
- **Fork safety.** Close DB/Redis/HTTP sockets before fork; reconnect in the child. Never share a socket across forks.
- **Deterministic.** Same `--seed` → same order per worker, same Faker values. Failures print a one-line repro command.
- **Frozen string literals everywhere.** Hot-loop allocations matter.
- **Low overhead.** Minimal allocations and syscalls in the scheduler/reporter loop; one IPC message per file, not per example; no per-test process spawn.
- **No comments that restate code.** Only the non-obvious *why*.

## Platforms

Every Ruby is first class, each on its fastest path. Same behavior everywhere; the oracle suites run on all three.

| Ruby | Parallelism | Hot paths |
|---|---|---|
| CRuby >= 3.2 | fork pool after preload (copy-on-write) | C extension `ext/fast_rspec/` (`FastRspec::Native`) |
| JRuby 10+ | thread pool — no GVL, real parallel threads | pure-Ruby twin `FastRspec::PureRuby` |
| TruffleRuby 24+ | thread pool (no GVL) | pure-Ruby twin (Graal JIT) |
| Windows / no `fork` | thread pool, or spawn pool (`FAST_RSPEC_POOL=spawn`) | C ext if it builds |

- C ext and pure-Ruby twin are **byte-identical in output**; a parity test runs each case against both. `FAST_RSPEC_DISABLE_EXT=1` forces the twin.
- C ext only for measured hot paths (runtime log parse, result serialization, output buffering). No C without a benchmark.
- Rails 7.1+. Rubocop `TargetRubyVersion` = gemspec floor.

## Testing

- Our own suite is written in Minitest style and run by **our** Minitest (dogfood). Bootstrap: `test/bootstrap/` runs on plain Ruby with zero framework until the engine is trustworthy.
- Layers: unit · adapter (rspec + minitest) · sample apps (`test/apps/{rails_rspec,rails_minitest,plain_ruby}`) · oracles (upstream suites) · bench.
- **Oracles are truth.** Upstream's suites are the spec. If one fails against us, we're wrong unless the divergence is listed in `docs/idea/parity-divergences.md`.
- Real Postgres, MySQL, SQLite, Redis in integration tests. Never mock the DB layer we isolate.

## Never

- Add a runtime dependency to the gemspec.
- Copy upstream source code. Implement public behavior from `docs/target/` + oracles only.
- Require any change to a user's existing spec/test files to get the speedup.
- Add a "faster than" claim without benchmark numbers in `docs/benchmarks.md`.
- Mock the database or Redis in isolation tests.
- Backwards-compat shims, dead code, speculative abstractions.
- `--no-verify`, force-push to `main`, `git stash`.

## Note

Do not use git worktrees — work directly in this checkout. If a task is big enough to need subagents, run them as a team in this same checkout: split the work into disjoint pieces so no two agents touch the same files.
