# ✅ Testing & CI

- Own suite: Minitest, run by FastRspec itself (dogfood).
- Demo apps `demo/rails` + `demo/ruby`: RSpec + Minitest suites each, identical test files on `STACK=upstream` and `STACK=fast_rspec`; `bin/stacks` prints the matrix. Upstream green always; fast_rspec green per milestone; serial and parallel results must match.
- Real Postgres, MySQL, SQLite, Redis services in CI. Never mock them.
- CI matrix: CRuby 3.2 (floor) + latest, JRuby, TruffleRuby. Lint once on latest.
- C ext ⇄ PureRuby parity test runs every case through both.
- `bin/check` = what CI runs.
