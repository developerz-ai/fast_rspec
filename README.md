# FastRspec

**One gem line. Your whole test stack. Every core.** *(target contract, not shipped)*

Target: a drop-in replacement for RSpec **and** Minitest (including Rails' `ActiveSupport::TestCase`), rebuilt lean with the same API, running in parallel on all cores by default, with batteries included and auto-configured: factories, Faker, VCR, WebMock, database cleaning, shoulda, time helpers, Capybara and coverage. Aimed at Rails and plain Ruby, on CRuby, JRuby and TruffleRuby. No speed claim is made until numbers land in [`docs/benchmarks.md`](docs/benchmarks.md).

> ## ⚠️ Status: design phase (2026-10)
>
> **Everything from here through [Parallelism](#parallelism-target) is a target contract, not shipped behavior.** Only a gem scaffold exists: configuration, host detection, a conditional Railtie, native/pure rendering and a CLI stub. There is no engine, no RSpec or Minitest replacement, no parallel runner and no battery yet. Milestones (M1-M8) are defined in [`docs/idea/11-roadmap.md`](docs/idea/11-roadmap.md); the design lives in [`docs/idea/`](docs/idea/00-seed.md).

## Install (target)

```ruby
# Gemfile
group :development, :test do
  gem 'fast_rspec'
end
```

Then delete the gems it replaces (each only once its battery ships, see the Milestone column below):

```diff
- gem 'rspec'
- gem 'rspec-rails'
- gem 'factory_bot_rails'
- gem 'faker'
- gem 'vcr'
- gem 'webmock'
- gem 'database_cleaner-active_record'
- gem 'simplecov'
- gem 'minitest-reporters'
+ gem 'fast_rspec'
```

## Run (target)

Your commands stay the same:

```bash
bundle exec rspec          # all cores
bin/rails test             # all cores; `parallelize` is handled for you
bundle exec rake test      # plain Ruby + Minitest
bundle exec fast_rspec     # auto-detects RSpec / Minitest / both
```

The goal is that you don't change any spec, test, `spec_helper.rb`, `rails_helper.rb`, `test_helper.rb` or `test/support/**` file. If you already configured something yourself, your configuration wins.

## What's included (target)

✅ = FastRspec's own lean implementation of the upstream API (zero runtime dependencies is a design constraint). 🔌 = keep the upstream gem in your Gemfile; FastRspec will auto-configure it. None of these ship yet; the Milestone column says when each is planned (`docs/idea/11-roadmap.md`).

| Battery | Same API as | Auto-configured | Milestone |
|---|---|---|---|
| 🧪 RSpec ✅ | rspec-core, -expectations, -mocks, -rails | `.rspec` honoured, type inference on Rails | M2-M3 |
| 🧪 Minitest ✅ | minitest 5 + 6, `ActiveSupport::TestCase` | `parallelize` routed to our pool | M1, M3 |
| 🏭 Factories ✅ | factory_bot (+ rails) | definitions found, `create`/`build` included | M6 (upstream wired until then) |
| 🎲 Fake data ✅ | faker | deterministic per `--seed`, unique reset per test | M4 |
| 📼 HTTP ✅ | vcr + webmock | cassettes in `spec/cassettes` or `test/cassettes`, real net blocked, localhost allowed | M4 |
| 🧹 DB ✅ | transactional tests + database_cleaner | per-worker DB, cloned from a template | M3 |
| 🔍 Matchers 🔌 | shoulda-matchers / -context | integrated with the framework in use | M5 |
| ⏱️ Time 🔌 | ActiveSupport `TimeHelpers` | included everywhere | M4 |
| 🌐 System 🔌 | capybara + cuprite | headless Chrome, unique port per worker | M5 |
| 📊 Coverage ✅ | simplecov | merged across workers | M5 |
| 🔐 Auth / jobs 🔌 | Devise, Sidekiq / Wurk, ActiveJob | test helpers, fake/inline modes, per-worker Redis DB | M4-M5 |

Target API for turning any of them off (the `FastRspec.configure` object exists in the scaffold; per-battery switches take effect as each battery lands):

```ruby
FastRspec.configure { |c| c.batteries.disable :vcr, :capybara }
```

## Parallelism (target)

| Ruby | How it is planned to run | Milestone |
|---|---|---|
| CRuby | boots once, forks N workers (copy-on-write), work-stealing queue, C extension on hot paths | M1, M8 |
| JRuby / TruffleRuby | a real parallel thread pool (no GVL), using the pure-Ruby implementation | M7 |

`N` defaults to the number of cores. `FAST_RSPEC_WORKERS` and `FAST_RSPEC_POOL` (`fork` or `thread`) are read by the scaffold's configuration today, but there is no runner to act on them yet. Planned: `-n 1` for a serial run, per-worker database, Redis DB, tmp dir and ports, and a one-line reproduction command (seed and the worker's files) on failure.

## Contributing

The gem lives in `apps/fast-rspec/`; the repository root holds the shared tooling (`bin/`, CI, docs, demos) — **not an application server**. Its contributor cycle is setup → tests → pre-PR checks:

```bash
./bin/setup
./bin/dev
./bin/check
```

### Prerequisites and setup

- Bash, Ruby and Bundler, plus access to RubyGems to install the development bundle. The gem requires Ruby >= 3.2; `mise.toml` and `apps/fast-rspec/.ruby-version` both select Ruby 3.4.
- With `mise` installed, setup installs and selects the configured toolchain. Without `mise`, setup uses the Ruby already on `PATH`; provide a supported Ruby and Bundler yourself.
- CRuby needs a C compiler, make and Ruby development headers for the native extension. Setup's build-tool provisioning uses Debian/Ubuntu's `dpkg` and `apt-get`; if `build-essential` is missing, it requires passwordless `sudo` and package-repository access. This is not a portable OS provisioning script.

`./bin/setup` installs the bundle and compiles the native extension on CRuby. JRuby and TruffleRuby use the pure-Ruby path and skip that compilation step. Toolchain or dependency installation failures must be resolved before continuing.

`./bin/dev` runs `bundle exec rake test`, this gem's own development test suite, and then exits. It does not start a server or persistent services. `./bin/stop` is an idempotent no-op; there is currently nothing at the root to stop.

### Checks and packaging

| Command | Stages |
|---|---|
| `./bin/check` | RuboCop lint, native compilation on CRuby, unit tests |
| `./bin/check fast` | RuboCop lint and unit tests; skips compilation |
| `./bin/check full` | Default stages, then upstream oracles and demo-app suites |

There is **no configured static typechecker**. The gate returns nonzero if a stage fails. Full mode is not currently a green acceptance gate: the oracle task deliberately aborts with `test:oracles: not implemented yet — see docs/idea/09-compat-oracles.md`. Demo apps have their own dependencies and dual-stack harness; they are not a root development server.

For a build-plus-install smoke test, use:

```bash
./bin/rake smoke
```

That task builds the gem before invoking `./bin/gem-smoke`, which installs it into a temporary gem home and requires it without Rails. Direct `./bin/gem-smoke` needs an already-built `apps/fast-rspec/pkg/fast_rspec-*.gem`; it is not a standalone fresh-checkout gate.

## Docs

- [`docs/idea/`](docs/idea/00-seed.md): design and roadmap
- [`AGENTS.md`](AGENTS.md): conventions for contributors and AI agents
- [`llms.txt`](llms.txt): one-file reference for coding agents (target contract; status per milestone)

## License

MIT
