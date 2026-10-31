# 🧱 Isolation

Everything a worker can collide on gets a per-worker slot. `TEST_ENV_NUMBER` set for compat with parallel_tests-aware code.

| Resource | Fork pool (CRuby) | Thread pool (JRuby/Truffle) |
|---|---|---|
| SQL DB | per-worker DB cloned from a template (`CREATE DATABASE … TEMPLATE` on PG, file copy on SQLite, dump-load on MySQL); schema loaded once; names keep `_test` | per-thread connection handler + per-thread DB clone (see below) |
| Redis | logical DB per worker (1..15); >15 workers → refuse to wrap, fall back to key namespace | key namespace per thread |
| tmp / storage | `tmp/fast_rspec/w<N>/` | same, per thread |
| ports (Capybara, servers) | base + N | base + N |
| FactoryBot sequences | untouched — per-worker DB means no collision; offset only in shared-DB mode (breaks exact-value asserts + cassettes) | offset per thread (shared DB) |
| Faker | seed = suite seed + worker id | per-thread `Random` |
| VCR cassettes | lock + tmp + atomic rename; `:once` skips if file appeared | same |
| ActiveStorage / uploads / search indexes / S3 prefixes | per-worker root/prefix | per-thread |
| ENV | snapshot/restore per test (opt-in) | n/a (process-global: warn) |

Template DB is rebuilt only when `db/schema.rb` / `structure.sql` / migrations digest changes.

## ⚠️ Thread pool reality (from [`../target/db-matchers-system-coverage.md`](../target/db-matchers-system-coverage.md), [`../target/rspec.md`](../target/rspec.md))
- Rails `pin_connection!` pins ONE connection per pool; DatabaseCleaner's transaction `clean` rolls back every pinned connection → threads sharing a pool clobber each other. Ecto-style shared sandbox does **not** map 1:1. Need a connection handler + DB per thread, and Capybara server threads routed to their owner's DB.
- rspec-mocks, `stub_const`, `allow_any_instance_of`, `$stdout` swaps, Sidekiq fake queues, Warden `login_as` are process-global → unsafe across threads.
- Policy: thread pool only when the suite passes a safety probe; otherwise **spawn pool** (`FAST_RSPEC_POOL=spawn`: N preloaded processes via `Process.spawn`, works on JRuby/Truffle/Windows). Documented in [parity-divergences.md](parity-divergences.md) if it ever differs.

## Template DB gotchas
- PG refuses `CREATE DATABASE … TEMPLATE` while anyone is connected to the template → parent disconnects first.
- Reuse `ActiveRecord::TestDatabases.create_and_load_schema` naming (`db_0` on 8.1, `db-0` on 7.2) so user `parallelize_setup` code keeps working.
- `maintain_test_schema!` runs once in the parent, before cloning.

## Coverage gotchas
- SimpleCov's at_exit is pid-guarded and skips on non-zero exit → workers need `SimpleCov.at_fork` + explicit result write. Never set `PARALLEL_TEST_GROUPS` (makes SimpleCov require parallel_tests).
- Coverage must start before app code → with `COVERAGE=1` start it in the parent before preload.
