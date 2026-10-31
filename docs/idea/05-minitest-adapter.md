# 🧪 Minitest frontend

Our own Minitest: `Minitest::Test`, `Minitest::Spec`, assertions, expectations, `Minitest::Mock`, plugins, reporters. API-compatible with minitest 5.2x **and** 6.x (both surfaces). Spec: [`../target/minitest-rails.md`](../target/minitest-rails.md). Oracle: upstream minitest's own tests.

- Shipped first (smaller surface, ~5.3k upstream LOC; most of our users' Rails apps are Minitest).
- All `Minitest::Test` classes are eligible for the pool (not only `parallelize_me!`), unless `i_suck_and_my_tests_are_order_dependent!` or opted out.
- Third-party plugins (`minitest-reporters`, `Minitest.extensions`, `plugin_*_init`) keep working.
- Rails: `ActiveSupport::TestCase.parallelize(...)` calls are honored but routed to our pool (workers count respected if the user set a number; `:number_of_processors` → ours). `parallelize_setup` / `parallelize_teardown` still fire per worker.
- `rails test file:line`, `-n /re/`, `--fail-fast`, `--seed` unchanged.
- Results: our transport, not DRb (no unmarshalable-exception crashes).

## Rails integration points (from [`../target/minitest-rails.md`](../target/minitest-rails.md))
- `ActiveSupport::TestCase.parallelize` is routed to our pool (it only sets `Minitest.parallel_executor`, which is ours). Our executor must pass `is_a?(ActiveSupport::Testing::ParallelizeExecutor)` (Isolation checks it).
- Rails calls both minitest 5 (`__run`, `run_one_method`, `test_order`) and 6 (`run_all_suites`, `run_suite`, `run_order`) names depending on version → we implement both surfaces, so Rails 7.2/8.0/8.1 all work (fixes the upstream 7.2 + minitest 6 breakage for free).
- Rails threshold (50 tests, counted pre-filter) and `PARALLEL_WORKERS` semantics honored.
- `parallelize_setup` per worker; `parallelize_teardown` per worker (+ parent on 8.1).
- `--fail-fast` = `Interrupt` from the reporter → drain pool, exit 1. `rails test -e` = environment, `-x` = exclude.
