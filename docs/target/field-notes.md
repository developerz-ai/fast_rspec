# 🧪 Field notes — upstream quirks found building the demo apps

As of 2026-10-31. Found by making `demo/rails` (Rails 8.1.4) and `demo/ruby` green on the upstream stack. Each is a behavior fast_rspec must reproduce or handle without user edits.

| # | Quirk | Where | fast_rspec must |
|---|---|---|---|
| 1 | minitest 6 moved `Minitest::Mock` + `Object#stub` to the `minitest-mock` gem | both demos | answer `require 'minitest/mock'` itself (first thing that breaks on our stack) |
| 2 | shoulda-context 2.0.0 + Rails 8.1 `executable` NameError; in the parallel parent it surfaces as a DRb error and hides the real failure | rails | ship the fix, but skip it when the app already patched it |
| 3 | A gem shipping an `rspec` executable clobbers rspec-core's `GEM_HOME/bin/rspec` wrapper (Bundler warns "binstub created for a different gem"); `bundle install` of a `gemspec` path gem installs its executables too | repo + both demos | `exe/rspec` only from M2, and only when rspec-core isn't installed alongside — or install as a Bundler binstub, never the shared wrapper |
| 4 | factory_bot_rails loads `spec/factories` **and** `test/factories`; same factory in both → `DuplicateDefinitionError` | rails | load definitions once, from both dirs, de-duplicated by path |
| 5 | `bin/rails test` skips `test/system`; only `test:all` / `test:system` run it | rails | identical file selection per command |
| 6 | Rails names worker DBs `storage/test.sqlite3_N`; truncation strategies rely on `parallelize_setup` + per-test DatabaseCleaner | rails | keep naming; fire `parallelize_setup` per worker |
| 7 | simplecov resolved to **1.3.2** (new major, own parallel adapters); classic `command_name` + `SimpleCov.result` in `parallelize_teardown` still merges | rails | rebuilt simplecov targets 1.x **and** 0.22 behavior |
| 8 | `retry_on` re-enqueues kwargs → injected test doubles raise `ActiveJob::SerializationError` | rails | nothing (user-level), but mocks must not change serialization behavior |
| 9 | `after_create_commit` fires under DatabaseCleaner `:transaction`; `let` vs `let!` changes enqueued-mail counts | rails | transaction semantics identical to upstream |
| 10 | VCR hooked into WebMock pre-empts it: unstubbed request → `VCR::Errors::UnhandledHTTPRequestError`; `WebMock::NetConnectNotAllowedError` only inside `VCR.turned_off` | ruby | same exception class + order |
| 11 | Minitest classes that can't `parallelize_me!` today (global WebMock registry, `Time.stub(:now)`, fixed tmp paths) | ruby | process isolation parallelizes them with no file edits |
| 12 | Fixed paths like `tmp/exports/catalog.csv` collide across workers | ruby | per-worker tmp (or chdir-relative `tmp/` remap) |
| 13 | `Rake::TestTask` + `rescue LoadError` around `rspec/core/rake_task` | ruby | provide `rspec/core/rake_task` |
| 14 | `Faker::Config.random` seeded from `config.seed`; `Faker::UniqueGenerator.clear` after each test | ruby | keep both APIs |
| 15 | Ruby 3.4 no longer bundles `csv` | ruby | nothing (app dep) |
