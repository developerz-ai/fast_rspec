# AGENTS.md

Canonical guide for AI coding agents working on this repository.
`CLAUDE.md` is a symlink to this file. Edit only `AGENTS.md`; preserve the alias.

## Non-negotiables

- **Drop-in compatibility:** preserve existing spec/test files, helpers, support files, DSLs, constants, require paths, CLI flags, matchers, exit codes and formatter output. Reject speedups that break compatibility.
- **Zero runtime dependencies:** never add one to the gemspec. Implement public behavior from `docs/target/` and upstream oracles; never copy upstream source or internals.
- **User configuration wins:** detect the host stack, never double-configure, make installs idempotent, and give every battery an off switch.
- **Plain Ruby stays plain:** load Rails integration only when `defined?(Rails::Railtie)`.
- **Fork safety:** close DB/Redis/HTTP sockets before fork, reconnect in children, and never share sockets across forks.
- **Determinism:** the same `--seed` gives the same per-worker order and Faker values; failures print a one-line reproduction command.
- **Native/pure parity:** C and Ruby twins must produce byte-identical output, tested against both. `FAST_RSPEC_DISABLE_EXT=1` forces Ruby. No C hot path without a benchmark.
- **Real services:** use real Postgres, MySQL, SQLite and Redis in integration tests; never mock the database or Redis isolation layer.
- **Measured claims:** no “faster than” or “Nx faster” claim in README/llms.txt without numbers in `docs/benchmarks.md`.
- Never add dead code, speculative abstractions or backwards-compat shims. Planned upstream require-path adapters are part of the drop-in API, not permission for unrelated shims.
- Never use `--no-verify`, force-push to `main`, `git stash` or git worktrees. Work in this checkout; split team work into disjoint file ownership.

## Stack and status

**Scaffold exists; the shared engine, replacement frontends, parallel runner and batteries remain planned.** Do not describe the intended replacement stack as already operational.

| Area | Current stack / intended contract |
|---|---|
| Runtime | Ruby >= 3.2; development pin Ruby 3.4 (`mise.toml`, `apps/fast-rspec/.ruby-version`); no runtime gem dependencies |
| Tooling | Bundler, Rake, rake-compiler on CRuby, RuboCop with Minitest/performance/Rake plugins |
| Existing scaffold | Configuration/autoload entrypoint, detection, conditional Railtie, native/pure rendering, bootstrap tests and CLI scaffold |
| Planned frameworks | Clean RSpec + Minitest implementations on one engine, including `ActiveSupport::TestCase`; Rails 7.1+ |
| Planned batteries | Rebuild WebMock, Faker, VCR, database_cleaner, SimpleCov, factory_bot; wire upstream shoulda, Capybara/Cuprite, Devise, Sidekiq/Wurk and ActiveJob |
| Planned platforms | CRuby: preloaded fork pool; JRuby 10+ / TruffleRuby 24+: thread pool; Windows/no fork: threads or spawn (`FAST_RSPEC_POOL=spawn`) |

Until a rebuilt battery passes its oracle, it may delegate to an installed upstream gem via the planned `FastRspec::Battery#fallback` API. These are design contracts, not implemented capabilities.

## Commands

Keep this table aligned with `bin/check` and `apps/fast-rspec/Rakefile`. Unsupported tasks are not green gates.

| Task | Command and actual behavior |
|---|---|
| Install | `bundle install` (in `apps/fast-rspec/`) |
| Default pre-PR gate | `bin/check`: lint + compile on CRuby + bootstrap unit tests |
| Fast gate | `bin/check fast`: lint + bootstrap unit tests; skips compilation |
| Full gate | `bin/check full`: default stages + oracles + demo apps; oracle stage currently fails as unimplemented |
| Own suite | `bin/rake test`: plain-Ruby bootstrap harness over fixed `test/unit/**/*_test.rb` glob; not dogfooded Minitest or a parallel runner |
| Single-file filtering | `TEST=...` is not supported by the current Rake task; it still runs the fixed glob |
| Lint | `bundle exec rubocop` (in `apps/fast-rspec/`) |
| Demo stacks | `demo/rails/bin/stacks`, `demo/ruby/bin/stacks`; `bin/rake test:apps` runs both; `STRICT=1` also fails on fast_rspec failures |
| Build + install smoke | `bin/rake smoke`: builds first, then installs in a temporary GEM_HOME and requires without Rails |
| Oracles (unavailable) | `bin/rake test:oracles` aborts with “not implemented yet” |
| Benchmarks (unavailable) | `bin/rake bench` aborts with “not implemented yet”; no `bench:vs_stock` task exists |

## Layout (planned)

This heading preserves the `#layout-planned` design-document link. The gem lives under `apps/fast-rspec/`; gem-code paths in this table are relative to it, while `bin/`, `demo/` and `docs/` stay at the repository root. Rows explicitly separate scaffold from planned layers; a scaffold file does not imply a completed subsystem.

| State | Path | Responsibility |
|---|---|---|
| Scaffold | `lib/fast_rspec.rb`, `lib/fast_rspec/{configuration,detect,render}.rb` | Entry, configuration, host detection, native/pure render dispatch |
| Scaffold | `lib/fast_rspec/rails/railtie.rb`, `ext/fast_rspec/`, `exe/fast_rspec` | Conditional Rails wiring, native extension, CLI |
| Existing tooling (gem) | `Rakefile`, `test/` | Rake gates, bootstrap tests |
| Existing tooling (repo root) | `bin/`, `demo/{rails,ruby}/` | Gate scripts, dual-stack demo harnesses |
| Planned | `lib/fast_rspec/engine/` | Framework-neutral examples/groups, hooks, memoization, filtering, ordering |
| Planned | `lib/fast_rspec/{rspec,minitest,rails}/` | Full frontend DSLs, assertions, mocks, reporters and Rails test integration |
| Planned | `lib/compat/`, `exe/rspec` | Upstream require paths and CLI; do not shadow installed frameworks before replacements work |
| Planned | `lib/fast_rspec/batteries/<name>/` | Upstream constants and `applies?`, `configured_by_user?`, idempotent `install!` |
| Planned | `lib/fast_rspec/wiring/<name>.rb` | Auto-configuration for upstream integrations not rebuilt |
| Planned | `lib/fast_rspec/runner/`, `scheduler.rb` | Preload, pool supervision, work stealing, runtime log, longest-first and file-to-example splitting |
| Planned | `lib/fast_rspec/isolation/`, `reporter/` | Worker DB/Redis/tmp/ports/ENV isolation; ordered output, JSON/JUnit, merged coverage |

## Conventions

- SOLID, especially SRP: detection has no installation side effects; batteries know nothing about the runner.
- Build against `docs/target/*.md`; load lazily and check allocations. Keep RuboCop `TargetRubyVersion` aligned with the gemspec floor.
- Before wiring anything, check for user configuration. Log automatic wiring at `FAST_RSPEC_DEBUG=1`.
- Use frozen string literals everywhere. Comments explain non-obvious reasons, not the code itself.
- Minimize allocations/syscalls in scheduler/reporter loops: one IPC message per file, not per example; no per-test process spawn.

## Testing rules

- Current unit tests use the plain-Ruby bootstrap harness. Minitest-style tests dogfooded through our own Minitest are the goal, not today's runner.
- Grow coverage through unit → frontends → demo apps → upstream oracles → benchmarks. Prove identical behavior on CRuby, JRuby and TruffleRuby as implementations land.
- Demo apps are acceptance tests: Rails 8.1 and plain Ruby each have RSpec and Minitest suites, unchanged across `STACK=upstream|fast_rspec` via `gemfiles/*.gemfile`. Keep upstream green; never weaken demo tests to make fast_rspec pass.
- Upstream suites are the compatibility specification. A failure is our defect unless documented in `docs/idea/parity-divergences.md`; oracle execution is not implemented yet.
- Test native/pure output parity and real-service isolation, not mocks of the behavior being implemented.

## Design references

- [Design index](docs/idea/00-seed.md) · [Architecture](docs/idea/02-architecture.md) · [Battery decisions](docs/idea/06-batteries.md)
- [Performance](docs/idea/08-performance.md) · [Compatibility oracles](docs/idea/09-compat-oracles.md) · [Accepted divergences](docs/idea/parity-divergences.md)
- Public API contracts: `docs/target/`. Update the relevant contract when upstream behavior changes, then implement and prove it against the oracle.
