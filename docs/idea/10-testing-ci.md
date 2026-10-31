# ✅ Testing & CI

- Own suite: Minitest, run by FastRspec itself (dogfood).
- Sample apps in `test/apps/`: `rails_rspec`, `rails_minitest`, `plain_ruby_rspec`, `plain_ruby_minitest` — each run serial and parallel, results must match.
- Real Postgres, MySQL, SQLite, Redis services in CI. Never mock them.
- CI matrix: CRuby 3.2 (floor) + latest, JRuby, TruffleRuby. Lint once on latest.
- C ext ⇄ PureRuby parity test runs every case through both.
- `bin/check` = what CI runs.
