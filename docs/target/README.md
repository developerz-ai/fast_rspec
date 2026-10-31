# 🎯 Compat targets

**Authoritative spec.** Every file here defines a public API our own implementation must match exactly — RSpec, Minitest and every battery. When upstream changes, update the doc first. Sections about "driving upstream internals" (e.g. `RSpec::Core::Runner`, `Minitest.parallel_executor` hooks) are now reference for behavior to reproduce, not code we call.

| File | Covers |
|---|---|
| [rspec.md](rspec.md) | rspec-core CLI/config/runner/reporter, -expectations, -mocks, -rails |
| [minitest-rails.md](minitest-rails.md) | minitest 5 + 6, `ActiveSupport::TestCase`, `parallelize`, `rails test` |
| [factories-faker-http.md](factories-faker-http.md) | factory_bot(_rails), faker, vcr, webmock |
| [db-matchers-system-coverage.md](db-matchers-system-coverage.md) | database_cleaner, shoulda, capybara/cuprite, simplecov |
| [field-notes.md](field-notes.md) | Upstream quirks found building the demo apps |
