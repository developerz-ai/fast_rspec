# FastRspec

**One gem line. Your whole test stack. Every core.**

Drop-in replacement for RSpec **and** Minitest (including Rails' `ActiveSupport::TestCase`), rebuilt lean: same API, a fraction of the overhead. Runs in parallel on all cores by default, and ships with batteries included and auto-configured: factories, Faker, VCR, WebMock, database cleaning, shoulda, time helpers, Capybara and coverage. Works with Rails and with plain Ruby. Runs on CRuby, JRuby and TruffleRuby.

> **Status: design phase (2026-10).** Gem skeleton only, nothing is implemented yet. See [`docs/idea/`](docs/idea/00-seed.md).

## Install

```ruby
# Gemfile
group :development, :test do
  gem 'fast_rspec'
end
```

Then delete the gems it replaces:

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

## Run

Your commands stay the same:

```bash
bundle exec rspec          # all cores
bin/rails test             # all cores; `parallelize` is handled for you
bundle exec rake test      # plain Ruby + Minitest
bundle exec fast_rspec     # auto-detects RSpec / Minitest / both
```

You don't need to change any spec, test, `spec_helper.rb`, `rails_helper.rb`, `test_helper.rb` or `test/support/**` file. If you already configured something yourself, your configuration wins.

## What's included

✅ = FastRspec's own lean implementation of the upstream API (zero runtime dependencies). 🔌 = keep the upstream gem in your Gemfile; FastRspec auto-configures it.

| Battery | Same API as | Auto-configured |
|---|---|---|
| 🧪 RSpec ✅ | rspec-core, -expectations, -mocks, -rails | `.rspec` honoured, type inference on Rails |
| 🧪 Minitest ✅ | minitest 5 + 6, `ActiveSupport::TestCase` | `parallelize` routed to our pool |
| 🏭 Factories ✅ | factory_bot (+ rails) | definitions found, `create`/`build` included |
| 🎲 Fake data ✅ | faker | deterministic per `--seed`, unique reset per test |
| 📼 HTTP ✅ | vcr + webmock | cassettes in `spec/cassettes` or `test/cassettes`, real net blocked, localhost allowed |
| 🧹 DB ✅ | transactional tests + database_cleaner | per-worker DB, cloned from a template |
| 🔍 Matchers 🔌 | shoulda-matchers / -context | integrated with the framework in use |
| ⏱️ Time 🔌 | ActiveSupport `TimeHelpers` | included everywhere |
| 🌐 System 🔌 | capybara + cuprite | headless Chrome, unique port per worker |
| 📊 Coverage ✅ | simplecov | merged across workers (`COVERAGE=1`) |
| 🔐 Auth / jobs 🔌 | Devise, Sidekiq / Wurk, ActiveJob | test helpers, fake/inline modes, per-worker Redis DB |

Turn any of them off:

```ruby
FastRspec.configure { |c| c.batteries.disable :vcr, :capybara }
```

## Parallelism

| Ruby | How it runs |
|---|---|
| CRuby | boots once, forks N workers (copy-on-write), work-stealing queue, C extension on hot paths |
| JRuby / TruffleRuby | a real parallel thread pool (no GVL), using the pure-Ruby implementation |

`N` is the number of cores by default. Use `FAST_RSPEC_WORKERS=4` to change it, or `-n 1` for a serial run. Each worker gets its own database, Redis DB, tmp dir and ports. When a test fails, you get a one-line command that reproduces it, including the seed and the worker's files.

## Docs

- [`docs/idea/`](docs/idea/00-seed.md): design and roadmap
- [`AGENTS.md`](AGENTS.md): conventions for contributors and AI agents
- `llms.txt`: one-file reference for coding agents (lands with the first release)

## License

MIT
