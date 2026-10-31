# 🗺️ Roadmap

| M | Scope | Done when |
|---|---|---|
| M0 | Skeleton, docs, agent setup, demo apps (upstream green) | ✅ 2026-10-31 |
| M1 | Engine + our Minitest (plain Ruby) + fork runner | minitest oracle ≥ 90%; own suite dogfooded on all cores |
| M2 | Our RSpec: core DSL + expectations + CLI + formatters | rspec-core/-expectations oracles ≥ 90% |
| M2.5 | Our RSpec mocks | rspec-mocks oracle ≥ 90% |
| M3 | Rails: `ActiveSupport::TestCase`, rspec-rails spec types, template DB clone, AR isolation | `demo/rails` green on the fast_rspec stack |
| M4 | Our factory_bot, faker, webmock, vcr, database_cleaner (each ≥ 90% of its upstream oracle) + wiring for time, devise, jobs | demo apps green on fast_rspec with their support files deleted |
| M5 | Wiring: upstream shoulda + capybara/cuprite (per-worker ports/browsers); our simplecov | system tests parallel; coverage = serial coverage |
| M6 | Our factory_bot (after profiling `create` hot path) | factory_bot oracle ≥ 90% + measured win |
| M7 | Thread pool + sandbox for JRuby/TruffleRuby | oracles green on all engines |
| M8 | C ext hot paths, bench vs stock, `llms.txt`, 1.0 | numbers in `docs/benchmarks.md` |
| Later | `--stale` (test impact), `--failed`, `--partition i/n`, distributed queue | |
