# Compat target — Minitest 5/6 + Rails testing

As of 2026-10. Sources read: `minitest-5.27.0`, `minitest-6.0.6`, `activesupport-8.1.4` / `7.2.3` / `8.0.5`, `railties-8.1.4` / `7.2.3`, `activerecord-8.1.4` / `7.2.3`, `actionpack-8.1.4`, `actioncable/actionmailer/activejob-8.1.4`.

Path shorthands in citations:

| Short | Real path (gem root) |
|---|---|
| `mt6/` | `minitest-6.0.6/lib/` |
| `mt5/` | `minitest-5.27.0/lib/` |
| `as/` | `activesupport-8.1.4/lib/active_support/` |
| `as72/` | `activesupport-7.2.3/lib/active_support/` |
| `ar/` | `activerecord-8.1.4/lib/active_record/` |
| `rt/` | `railties-8.1.4/lib/` |
| `rt72/` | `railties-7.2.3/lib/` |

Gemspec floor everywhere: `minitest >= 5.1` (activesupport 7.2.3, 8.0.5, 8.1.4). **No upper bound** — Bundler will happily resolve Rails 7.2 + minitest 6, which is broken (see §6).

---

## 1. Minitest runtime

### 1.1 Run path — MT5 vs MT6 (the big refactor)

| Step | MT5 (5.27) | MT6 (6.0.6) |
|---|---|---|
| Register at exit | `Minitest.autorun` `mt5/minitest.rb:70` | `Minitest.autorun` `mt6/minitest.rb:69` — nested `at_exit` runs `@@after_run`, `exit exit_code \|\| false`; skipped in forked child unless `Minitest.allow_fork` (`:79`) |
| Plugin discovery | **automatic**: `Minitest.run` calls `load_plugins` unless `--no-plugins`/`MT_NO_PLUGINS` `mt5/minitest.rb:283` | **opt-in**: `Minitest.load :name` `mt6/minitest.rb:102`, `Minitest.register_plugin mod` `:113`, or manual `Minitest.load_plugins` `:118`. `--no-plugins` is a warned no-op `:158` |
| Entry | `Minitest.run(args)` `mt5/minitest.rb:282` | `Minitest.run(args)` `mt6/minitest.rb:299` |
| Arg parse | `process_args` `mt5/minitest.rb:142` | `process_args` `mt6/minitest.rb:152` |
| All suites | `Minitest.__run(reporter, options)` `mt5/minitest.rb:337` | `Minitest.run_all_suites(reporter, options)` `mt6/minitest.rb:352` |
| Per class | `Runnable.run(reporter, options)` `mt5/minitest.rb:419` (filters inline via `options[:filter]`) | `Runnable.run_suite(reporter, options)` `mt6/minitest.rb:452` + `Runnable.filter_runnable_methods(options)` `:434` (via `options[:include]`) |
| Per method | `Runnable.run_one_method(klass, name, reporter)` `mt5/minitest.rb:460` → `Minitest.run_one_method(klass, name)` `:1222` (asserts `Result === result`) | `Runnable.run(klass, name, reporter)` `mt6/minitest.rb:484`; `Minitest.run_one_method` **removed** |
| Order hook | `Runnable.test_order` `mt5/minitest.rb:469` | `Runnable.run_order` `mt6/minitest.rb:493` (renamed) |
| Order split | `__run` partitions `test_order == :parallel`; serial first, then parallel | same, `run_order == :parallel` `mt6/minitest.rb:354-362` |
| Instance | `Test#run` → returns `Result.from self` | `Test#run` `mt6/minitest/test.rb:84` → `Result.from self` "per contract" |

Run sequence (MT6 `mt6/minitest.rb:299-330`): `process_args` → `Minitest.seed = options[:seed]; srand` → build `CompositeReporter[SummaryReporter, ProgressReporter]` (Progress omitted with `-q`) → `self.reporter = reporter; init_plugins(options); self.reporter = nil` → `parallel_executor.start if respond_to?(:start)` → `reporter.start` → `run_all_suites` (rescues `Interrupt` → "Interrupted. Exiting...", `finished` stays nil) → `parallel_executor.shutdown` → `reporter.report` → return `empty_run!` if 0 ran, else `finished and reporter.passed?`. Exit code is that boolean (`true`→0, `false`→1).

`empty_run!` `mt6/minitest.rb:332`: nothing ran + include filter → warn "Nothing ran for filter" + DidYouMean suggestions, returns nil → exit 1. MT5 reads `options[:filter]` (`mt5/minitest.rb:318`).

### 1.2 CLI options (`process_args`)

| Flag | MT5 | MT6 | Key in `options` |
|---|---|---|---|
| `-h/--help` / `-V/--version` | `-h` only `mt5/minitest.rb:158` | both `mt6/minitest.rb:170,175` (exit 0 since 6.0.1) | — |
| `-s/--seed SEED` (Integer) | `mt5/minitest.rb:166` | `mt6/minitest.rb:181` | `:seed` |
| `-v/--verbose` | `:170` | `:185` | `:verbose` |
| `-q/--quiet` | `:174` | `:189` | `:quiet` |
| `--show-skips` | `:178` | `:193` | `:show_skips` |
| `-n/--name PATTERN` | **primary** `mt5/minitest.rb:182` | hidden alias of `-i/--include` `mt6/minitest.rb:213-214` | MT5 `:filter`; MT6 `:include` |
| `-i/--include PATTERN` | — | `mt6/minitest.rb:200` | `:include` |
| `-e/--exclude PATTERN` (MT6 alias `-x`) | `mt5/minitest.rb:186` | `mt6/minitest.rb:204,215` | `:exclude` |
| `-S/--skip CODES` | `:199` | `:217` | `:skip` (chars) |
| `-W[error]` | `:203` | `:221` | `:Werror` |
| `-b/--bisect` | — | only when `$0` matches `/minitest/` `mt6/minitest.rb:197` | — |
| `-p/--pride` | pride plugin | **pride plugin** `mt6/minitest/pride_plugin.rb:5` — only if plugin loaded | — |
| `--no-plugins` | real `mt5/minitest.rb:163` | no-op warning | — |

Pattern semantics (`filter_runnable_methods`): string `"/re/"` → `Regexp`; matched with `===` against `"meth"` **and** `"Klass#meth"`. Any object responding to `===` works — Rails relies on this (`CompositeFilter`, §4.3).

Seed: absent `--seed` → `(ENV["SEED"] || srand).to_i % 0xFFFF`, appended to `options[:args]` as `--seed N` (`mt6/minitest.rb:266-270`). `options[:args]` is the rerun string shown in the summary. Order within a class: `srand Minitest.seed; methods.sort.shuffle` for `:random`/`:parallel` (`mt6/minitest/test.rb:67-79`); suites shuffled in `run_all_suites` with the global RNG.

### 1.3 Env vars

| Var | MT5 | MT6 | Note |
|---|---|---|---|
| `MT_CPU` | thread-pool size `mt5/minitest.rb:37` | `mt6/minitest.rb:36` | default `Etc.nprocessors`; executor built at **require time** only if > 1 (`:38`) |
| `N` | CPU count fallback + deprecation warn `mt5/minitest.rb:36-37`; TestTask: `-n $N` | **removed** from core. TestTask maps `N` → `-i $N` (name filter!) `mt6/minitest/test_task.rb:175` | same var, different meaning per layer |
| `SEED` | yes | yes | |
| `TESTOPTS`, `A`, `FILTER` | TestTask `mt5/minitest/test_task.rb:179-181` | `mt6/minitest/test_task.rb:179-181` (+ `I`, `X`, `E`) | Rails also splices `TESTOPTS` in `run_from_rake` `rt/rails/test_unit/runner.rb:52` |
| `MT_NO_PLUGINS` | yes | gone | |
| `MT_NO_EXPECTATIONS` | gates `Object` expectations `mt5/minitest/spec.rb:351-353` | gone (no Object infection) | |
| `MT_COMPAT` | loads `MiniTest` alias `mt5/minitest/test.rb:238` | gone | |
| `MT_DEBUG` | full backtraces | — | |

### 1.4 Plugin protocol

| Form | Options hook | Init hook | Registration |
|---|---|---|---|
| name (String/Symbol) | `Minitest.plugin_<name>_options(opts, options)` | `Minitest.plugin_<name>_init(options)` | file `minitest/<name>_plugin.rb` (MT5 auto via `Gem.find_files`; MT6 `Minitest.load :<name>`) |
| Module | `mod.minitest_plugin_options(opts, options)` | `mod.minitest_plugin_init(options)` | `Minitest.register_plugin mod` |

- Dispatch: options `mt6/minitest.rb:237-250` (only if `extensions` non-empty), init `:134-150`.
- `Minitest.extensions` — Array of names/modules (`mt6/minitest.rb:55`).
- During init `Minitest.reporter` is the `CompositeReporter`; plugins mutate `reporter.reporters` (Rails replaces Summary/Progress, §4.4). Nil'd after init.
- Other globals: `Minitest.after_run {}` `mt6/minitest.rb:95`, `Minitest.backtrace_filter`, `Minitest.info_signal` ("INFO"), `Minitest.allow_fork`, `Minitest.seed`.

### 1.5 Reporter API

| Class | Ref | Surface |
|---|---|---|
| `AbstractReporter` | `mt6/minitest.rb:707` | `start`, `prerecord(klass, name)`, `record(result)`, `report`, `passed?`, `synchronize(&)` (own Mutex) |
| `Reporter < AbstractReporter` | `:753` | `io`, `options`, `initialize(io = $stdout, options = {})` |
| `ProgressReporter` | `:779` | dots / `-v` lines |
| `StatisticsReporter` | `:815` | `assertions count results start_time total_time failures errors warnings skips`; `record` keeps non-passing results |
| `SummaryReporter < StatisticsReporter` | `:917` | `statistics`, `aggregated_results(io)`, `summary`, `to_s`; prints `Run options: …` + `# Running:` on `start` |
| `CompositeReporter` | `:989` | `reporters`, `<<`, fans out all calls, `io` of first |

Thread-safety contract: serial suites run first and don't lock; parallel jobs wrap `prerecord`/`record` in `reporter.synchronize` (`mt6/minitest/parallel.rb:34-36`). `prerecord` receives a **class** (Rails DRb path sends a `Struct.new(:name)` stand-in, §3.3).

### 1.6 `Minitest::Result` — the wire object

| | MT5 | MT6 |
|---|---|---|
| Def | `mt5/minitest.rb:651` | `mt6/minitest.rb:659` |
| Fields | `name failures assertions time klass(String) source_location metadata` | same |
| `Result.from(runnable)` | `mt5/minitest.rb:670` | `mt6/minitest.rb:675` (`source_location` rescue `["unknown", -1]`) |
| Marshal | `Runnable#marshal_dump` exists (deprecated, drops klass) but `Result` **undefs** it `mt5/minitest.rb:654-655` → default ivar Marshal | no custom marshal anywhere ("Deleted all use of Marshal for serialization" — History 6.0.0) → default ivar Marshal |
| Failure payloads | `Assertion`, `Skip`, `UnexpectedError(error)` `mt6/minitest.rb:1078`, `UnexpectedWarning` `:1117` | same |

Marshal-safety is **still enforced at capture time** in both: `Test#capture_exceptions` → `sanitize_exception` does `Marshal.dump e`, on failure `neuter_exception` rebuilds same class, else `RuntimeError "Neutered Exception …"` with ivars stripped (`mt6/minitest/test.rb:186-226`). Holes: `Assertion` subclasses are **not** sanitized (only `rescue Exception` branch), and `metadata` must be plain data (doc only, `mt6/minitest.rb:546`). `Result` is JSON-able too (Rails `ProfileReporter` round-trips `result.to_json`, `rt/minitest/rails_plugin.rb:38-44`).

### 1.7 Parallel (threads) — built in

| API | Ref | Behavior |
|---|---|---|
| `Minitest.parallel_executor` (cattr) | `mt6/minitest.rb:34-38` | duck type: `start`(opt), `<<([klass, method, reporter])`, `shutdown`(opt), `size` (Rails prints it) |
| `Minitest::Parallel::Executor.new(size)` | `mt6/minitest/parallel.rb:9` | N threads on `Thread::Queue`; job does `synchronize{prerecord}` → `klass.new(method).run` → `synchronize{record}`; `shutdown` pushes N nils + joins |
| `Minitest::Parallel::Test` | `:58` | `_synchronize` via `Minitest::Test.io_lock` |
| `Parallel::Test::ClassMethods` | MT5 `run_one_method` + `test_order :parallel` (`mt5/minitest/parallel.rb:62,66`); MT6 `run` + `run_order :parallel` (`mt6/minitest/parallel.rb:62,66`) | enqueue instead of run |
| `parallelize_me!` | `mt6/minitest/test.rb:56` (`mt5/…:60`) | no-op if `parallel_executor` nil; else include/extend the above. Called on `Minitest::Test` it parallelizes **every** subclass |
| `i_suck_and_my_tests_are_order_dependent!` | `mt6/minitest/test.rb:31` (`mt5/…:35`) | redefines `run_order`/`test_order` → `:alpha` (wins over parallel since it's a singleton redefine) |
| `make_my_diffs_pretty!` | `mt6/minitest/test.rb:44` | |

### 1.8 MT6 breaking changes (History.rdoc 6.0.0)

| Change | Impact on us |
|---|---|
| `MiniTest` / `MiniTest::Unit::TestCase` namespaces deleted | old suites using `MiniTest::` break under MT6 regardless of us — not ours to fix |
| Expectations removed from `Object` — only `_(x)`, `value(x)`, `expect(x)` | `x.must_equal` fails on MT6 |
| `minitest/mock` extracted → `minitest-mock` gem | `as/testing/method_call_assertions.rb:3` does `require "minitest/mock"` |
| `assert_equal nil, x` → error (use `assert_nil`); 6.0.3 also `assert_same nil, x` | |
| `assert_send` removed; `Test#class_name` removed | |
| `__run`→`run_all_suites`; `Runnable.run`→`run_suite`+`filter_runnable_methods`; `run_one_method`→`run`; `Minitest.run_one_method` removed | adapter must branch on version |
| `ENV["N"]` parallelism removed → `MT_CPU` | |
| `options[:filter]` → `options[:include]`; `--include`, `-n` hidden alias | |
| `test_order` → `run_order` | |
| `message(proc)` overrides instead of chains | |
| `with_info_handler` reporter arg removed (kept as ignored optional) | |
| Plugins opt-in | **our plugin must be explicitly loaded/registered on MT6** |
| Adds `bin/minitest` (sprint, `file:line`), `--bisect`, `minitest/server`, `minitest/complete`, vendored `path_expander`; Ruby ≥ 3.2 | `minitest file.rb:12` is a new entry point to support |

## 2. Assertions + Spec DSL (names)

`Minitest::Assertions` (MT6, `mt6/minitest/assertions.rb`): `assert assert_empty assert_equal assert_in_delta assert_in_epsilon assert_includes assert_instance_of assert_kind_of assert_match assert_nil assert_operator assert_output assert_path_exists assert_pattern assert_predicate assert_raises assert_respond_to assert_same assert_silent assert_throws capture_io capture_subprocess_io flunk pass skip skip_until skipped? message diff mu_pp mu_pp_for_diff` + `refute_*` twins (`refute refute_empty refute_equal refute_in_delta refute_in_epsilon refute_includes refute_instance_of refute_kind_of refute_match refute_nil refute_operator refute_path_exists refute_pattern refute_predicate refute_respond_to refute_same`). MT5 adds `assert_send`.

Lifecycle (`Minitest::Test::LifecycleHooks`, `mt6/minitest/test.rb:144-183`): `before_setup setup after_setup before_teardown teardown after_teardown`. Teardown hooks each wrapped in their own `capture_exceptions`.

Spec DSL (`mt6/minitest/spec.rb`): `describe` (Kernel, `:74`), `it`/`specify` (`:207`), `before`/`after` (`:175,189`), `let` (`:231`), `subject` (`:250`), `register_spec_type`/`spec_type` (`:130,144`), `_`/`value`/`expect` (`:302`). Expectations (`Minitest::Expectation` only in MT6; also on `Object` in MT5): `must_be must_be_close_to must_be_empty must_be_instance_of must_be_kind_of must_be_nil must_be_same_as must_be_silent must_be_within_delta must_be_within_epsilon must_equal must_include must_match must_output must_pattern_match must_raise must_respond_to must_throw path_must_exist` + `wont_be wont_be_close_to wont_be_empty wont_be_instance_of wont_be_kind_of wont_be_nil wont_be_same_as wont_be_within_delta wont_be_within_epsilon wont_equal wont_include wont_match wont_pattern_match wont_respond_to path_wont_exist`.

## 3. `ActiveSupport::TestCase`

### 3.1 Class surface (`as/test_case.rb`)

| API | Ref | Notes |
|---|---|---|
| `class TestCase < ::Minitest::Test` | `:23` | `Assertion = Minitest::Assertion` |
| `parallel_worker_id` (class + instance) | `:34,199` | 8.1 only; set in worker `after_fork`. nil when serial |
| `test_order=` / `test_order` | `:51,61` | stored in `ActiveSupport.test_order` (`as/../active_support.rb:104`), default `:random` |
| `run_order` → `test_order` | `:65-69` | defined only if `Minitest::Runnable.respond_to?(:run_order)` (MT6). **8.0.5 checks `Minitest.respond_to?` (wrong receiver) — `test_order=` silently ignored on 8.0 + MT6** (`activesupport-8.0.5/…/test_case.rb:48`) |
| `parallelize(workers: :number_of_processors, with: :processes, threshold: ActiveSupport.test_parallelization_threshold, parallelize_databases: ActiveSupport.parallelize_test_databases)` | `:113-126` | see 3.2 |
| `parallelize_before_fork {}` | `:138` | 8.1 only (not in 7.2) — parent, before fork |
| `parallelize_setup { \|i\| }` | `:155` | child, after fork, before first test |
| `parallelize_teardown { \|i\| }` | `:172` | child before exit **and** (8.1) parent after shutdown, called with **no arg** (`as/testing/parallelization.rb:79`) |
| `method_name` alias of `name` | `:196` | |
| `assert_not_*` aliases of `refute_*` | `:215-357` | `assert_not_empty/equal/in_delta/in_epsilon/includes/instance_of/kind_of/nil/operator/predicate/respond_to/same`, `assert_no_match` |
| `run_load_hooks(:active_support_test_case)` | `:359` | where AR fixtures, TestDatabases, LineFiltering get mixed in |

Mixins `:203-214`: `TaggedLogging`, prepend `SetupAndTeardown`, prepend `TestsWithoutAssertions`, `Assertions`, `ErrorReporterAssertions`, `EventReporterAssertions` (8.1), `NotificationAssertions` (8.1), `Deprecation`, `ConstantStubbing`, `TimeHelpers`, `FileFixtures`, extend `Declarative`.

Config knobs: `ActiveSupport.test_parallelization_threshold` default **50** (`active_support.rb:105`, `config.active_support.test_parallelization_threshold`), `ActiveSupport.parallelize_test_databases` default **true** (`:106`, `config.active_support.parallelize_test_databases`, 8.1 only).

### 3.2 `parallelize` semantics

| Input | 8.1.4 (`as/test_case.rb:114-125`) | 7.2.3 (`as72/test_case.rb:81-85`) |
|---|---|---|
| `ENV["PARALLEL_WORKERS"]` set | wins, `.to_i` | wins, `.to_i` |
| `workers: :number_of_processors` | `(Concurrent.available_processor_count \|\| Concurrent.processor_count).floor` (cgroup-aware) | `Concurrent.processor_count` |
| `with: :processes` | also sets `ActiveSupport.parallelize_test_databases` | — |
| Effect | `Minitest.parallel_executor = ParallelizeExecutor.new(size:, with:, threshold:)` — **only** a global assignment; last call wins | same |

`ActiveSupport::Testing::ParallelizeExecutor` (`as/testing/parallelize_executor.rb`, identical 7.2 ↔ 8.1):

| Method | Line | Behavior |
|---|---|---|
| `start` | `:15` | `parallelize if should_parallelize?` → prints execution info (`puts`, stdout) → inner `start` |
| `should_parallelize?` | `:56-58` | `(ENV["PARALLEL_WORKERS"] \|\| tests_count > threshold) && size > 1` |
| `tests_count` | `:64-65` | `Runnable.runnables.sum { runnable_methods.size }` — **unfiltered** (ignores `-n`, `file:line`), counts every loaded runnable incl. non-AS |
| `parallelize` | `:47-50` | `@parallelized = true; Minitest::Test.parallelize_me!` — global, all `Minitest::Test` subclasses |
| `build_parallel_executor` | `:35-44` | `:processes` → `Testing::Parallelization.new(size)`; `:threads` → `lock_threads = false` + `Minitest::Parallel::Executor.new(size)`; else `ArgumentError` |
| `<<` / `shutdown` | `:22,26` | forward only if parallelized |
| `execution_info` | `:72-77` | "Running N tests in parallel using W processes" / "Running N tests in a single process (parallelization threshold is T)" |

Below threshold: `parallelize_me!` never called → every class runs serially in-process; `parallelize_setup` hooks **never fire** (no fork); DB stays the base test DB.

### 3.3 `ActiveSupport::Testing::Parallelization` — fork + DRb

`as/testing/parallelization.rb`, `…/parallelization/server.rb`, `…/parallelization/worker.rb`.

| Phase | Where | What |
|---|---|---|
| construct | `parallelization.rb:36-41` | `Server.new`; `DRb.start_service("drbunix:", server)` (Unix socket; `drb/unix` skipped on Windows) — **created lazily at `ParallelizeExecutor#start`, i.e. after all test files loaded** |
| start | `:47-52` | `before_fork_hooks.each(&:call)` (8.1), then `worker_count.times { Worker.new(i, url).start }` |
| enqueue | `server.rb:32-35` | `o[2] = DRbObject.new(o[2])` — reporter becomes a remote ref; job = `[klass, method_name, reporter]`; `klass` crosses DRb **by name** (Marshal of a Class) |
| worker boot | `worker.rb:14-33` | `fork { setproctitle; DRb.stop_service; @queue = DRbObject.new_with_uri(url); start_worker(uuid, pid); after_fork rescue => @setup_exception; work_from_queue } ensure run_cleanup; stop_worker` |
| after_fork | `worker.rb:84-90` | `TestCase.parallel_worker_id = n` (8.1); `after_fork_hooks.each { cb.call(n) }`. **Exception is swallowed** and prepended to *every* result from that worker (`add_setup_exception`, `:99-101`) |
| per job | `worker.rb:42-58` | `klass.with_info_handler(reporter) { Minitest.respond_to?(:run_one_method) ? Minitest.run_one_method(klass, m) : klass.new(m).run }` (8.1; 7.2 calls `run_one_method` unconditionally → NoMethodError on MT6) |
| record | `worker.rb:60-82` → `server.rb:21-30` | DRb marshals `Result` to parent; parent: if `DRb::DRbUnknown` (class not loadable in parent) → raises `DRbConnError`; else `reporter.synchronize { prerecord(PrerecordResultClass.new(result.klass), result.name); record(result) }` |
| unmarshalable fallback | `worker.rb:65-75` | on `DRbConnError`: every failure → `Minitest::UnexpectedError.new(DRb::DRbRemoteError.new(failure.error))` (or `failure.exception` pre-5.14) and re-sent. **Assertions/skips become "Error" with `DRb::DRbRemoteError`** — result_code changes F/S→E |
| Interrupt | `worker.rb:76-78` | `@queue.interrupt` (clears queue) and re-raise; `--fail-fast` raises `Interrupt` inside `record` in the parent, propagated over DRb |
| shutdown | `parallelization.rb:62-80`, `server.rb:72-94` | reap already-dead pids (`WNOHANG`) → server waits queue empty (`sleep 0.1` poll) → close → wait `active_workers` empty → each still-in-flight job recorded as `UnexpectedError(RuntimeError "result not reported")` (crashed worker) → `waitpid` all → `DRb.stop_service` → parent cleanup hooks (8.1) |

Scheduling = single shared FIFO, one test method per DRb round-trip (2 RPCs/test: `pop`, `record`). No file affinity, no runtime ordering. Order = suites shuffled, methods per `runnable_methods`.

### 3.4 Per-worker databases (`ActiveRecord::TestDatabases`)

Mixed in by `rt/rails/test_help.rb:18` on `:active_support_test_case`; hooks registered at module-body load.

| Hook | 8.1 `ar/test_databases.rb` | 7.2 |
|---|---|---|
| before_fork | `:7-11` `connection_handler.clear_all_connections!` if `parallelize_test_databases` | — |
| after_fork(i) | `:13-17` `create_and_load_schema(i, env_name: DEFAULT_ENV.call)` if `parallelize_test_databases` | unconditional |
| cleanup | `:19-21` `each_connection_pool.each(&:discard!)` | — |
| `create_and_load_schema` | `:23-36`: `VERBOSE=false`; for each `configs_for(env_name:, include_hidden: true)`: `db_config._database = "#{database}_#{i}"`; if `database_tasks?` → `DatabaseTasks.reconstruct_from_schema(db_config, nil)`; ensure `establish_connection` | suffix **`-#{i}`**, no hidden configs, `reconstruct_from_schema(db_config, ActiveRecord.schema_format, nil)` |

Workers number 0..N-1 → `app_test_0`, `app_test_1`. 7.2: `app_test-0`. `reconstruct_from_schema` = purge + load schema if schema changed (cheap reuse when unchanged). SQLite `:memory:` / file DBs get the suffix too.

### 3.5 Fixtures, callbacks, declarative, helpers

- `ActiveRecord::TestFixtures` (`ar/test_fixtures.rb`): `before_setup → setup_fixtures` (`:9`), `after_teardown → teardown_fixtures` (`:14`). Class attrs `:31-39`: `fixture_paths fixture_table_names fixture_class_names use_transactional_tests(true) use_instantiated_fixtures pre_loaded_fixtures lock_threads(true) fixture_sets database_transactions_config`. `fixtures :all` / `fixtures :users` `:71`, `set_fixture_class` `:60`, `use_transactional_tests_for_database` `:55`. Transactional tests pin connection (`pool.pin_connection!(lock_threads)` `:202`). `fixture_paths << "#{Rails.root}/test/fixtures/"` + `file_fixture_path` set in `rt/rails/test_help.rb:22-23`.
- `SetupAndTeardown` (`as/testing/setup_and_teardown.rb`): `define_callbacks :setup, :teardown` (`:23`); class-level `setup(*args, &blk)` → `set_callback(:setup, :before)` (`:29`), `teardown` → `:after` (`:34`); run from `before_setup`/`after_teardown` (`:39,44`).
- `Declarative#test(name, &blk)` (`as/testing/declarative.rb:13`): method `"test_#{name.gsub(/\s+/, '_')}"`; raises on duplicate; no block → `flunk "No implementation provided for …"`.
- `Isolation` (`as/testing/isolation.rb`): on include, `parallelize_me!` unless executor is a `ParallelizeExecutor` (`:10-14`); forks per test (`NO_FORK` → subprocess), Marshal round-trip of result (`:32,58`).
- `TimeHelpers`: `travel travel_to travel_back freeze_time` (+ `unfreeze_time` alias).
- `Assertions`: `assert_not assert_raises(alias assert_raise) assert_nothing_raised assert_difference assert_no_difference assert_changes assert_no_changes`. Error reporter: `assert_error_reported assert_no_error_reported capture_error_reports`. Events (8.1): `assert_event_reported assert_events_reported assert_no_event_reported with_debug_event_reporting`. Notifications (8.1): `assert_notification assert_notifications_count assert_no_notifications capture_notifications`. Deprecation: `assert_deprecated assert_not_deprecated collect_deprecations`. `stub_const`, `file_fixture`. MethodCall (internal): `assert_called assert_called_with assert_not_called assert_called_on_instance_of`.
- AR (`rt/rails/test_help.rb:16-20`): `ActiveRecord::Assertions::QueryAssertions` — `assert_queries_count assert_no_queries assert_queries_match assert_no_queries_match`.

## 4. `rails test`

### 4.1 Control flow (8.1)

1. `Rails::Command::TestCommand#perform(*args)` `rt/rails/commands/test/test_command.rb:28`: `$LOAD_PATH << test`; `Runner.parse_options(args)` strips `-e/--environment ENV` (sets `RAILS_ENV`, default `test`) and `-w/--warnings` (`rt/rails/test_unit/runner.rb:37-48`); runs `test:prepare` rake task unless an arg matches `EXACT_TEST_ARGUMENT_PATTERN = /^-n|^--name\b|<path>/` (`test_command.rb:70`).
2. `Runner.run(args)` `runner.rb:56-64`: `require "active_support/testing/autorun"`; `@@load_test_files = true`; `at_exit { ARGV.replace(args) }`.
3. `as/testing/autorun.rb`: `Minitest.load :rails if Minitest.respond_to?(:load)` (MT6 opt-in path) then `Minitest.autorun`.
4. At exit `Minitest.run(ARGV)` → `process_args` → `plugin_rails_options` (`rt/minitest/rails_plugin.rb:93-150`): positional args collected to `options[:test_files]` (`opts.on(/^[^-]/)`), and a trailing `opts.on do … end` **requires test files during option parsing** via `Runner.load_tests` (`:145-149`).
5. `plugin_rails_init` (`:154-179`) — only if `RAILS_ENV` or `RAILS_MINITEST_PLUGIN` set.

7.2 differs: `Runner.run` calls `load_tests(argv)` **eagerly** before autorun (`rt72/rails/test_unit/runner.rb:55-57`); `plugin_rails_init` requires `RAILS_ENV` only; autorun never calls `Minitest.load :rails` (`as72/testing/autorun.rb`) → on MT6 the rails plugin never loads.

Rake: `rake test` / `test:<folder>` / `test:all|generators|units|functionals|system` → `Runner.run_from_rake` = `system("rails", cmd, *argv, *TESTOPTS)` (`rt/rails/test_unit/testing.rake:9-38`, `runner.rb:50-54`). `test:db` = `db:test:prepare` + `test`.

Thor subcommands (`test_command.rb:37-66`): `bin/rails test:models|helpers|channels|controllers|mailers|integration|jobs|mailboxes` (`TEST_FOLDERS`, `runner.rb:26`), `test:all` → `test/**/*_test.rb`, `test:system` → `test/system`, `test:units`, `test:functionals`, `test:generators`.

Default glob `ENV["DEFAULT_TEST"] || "test/**/*_test.rb"`, exclude `ENV["DEFAULT_TEST_EXCLUDE"] || "test/{system,dummy,fixtures}/**/*_test.rb"` (only when no patterns) (`runner.rb:116-137`). Dir arg → `dir/**/*_test.rb`. Missing file → `InvalidTestError` with DidYouMean.

### 4.2 Rails CLI flags (added by `plugin_rails_options`)

| Flag | Ref | Option |
|---|---|---|
| `-w/--warnings`, `-e/--environment ENV` | `runner.rb:32-35` (pre-parsed, no-op in optparse) | — ⚠ `-e` collides with minitest `-e/--exclude`: Rails wins, use `-x`/`--exclude` |
| `-b/--backtrace` | `rails_plugin.rb:96` | `:full_backtrace` (skips `BacktraceFilterWithFallback`) |
| `-d/--defer-output` | `:100` | `:output_inline = false` |
| `-f/--fail-fast` | `:104` | `:fail_fast` → `raise Interrupt` in `TestUnitReporter#record` (`rt/rails/test_unit/reporter.rb:38-40`) |
| `-n/--name` (MT6 only) | `:108-113` | warns "switch to -i/--include", sets `:include` |
| `-c/--[no-]color` | `:115` | `:color` (default true) |
| `--profile [COUNT]` | `:119` | `:profile` (default 10) → `ProfileReporter`; `RAILTIES_OUTPUT_FILE` → JSON lines (8.1) |
| `--seed`, `-v`, `-q`, `-i`, `-x`, `-S`, `-W` | minitest | |

### 4.3 Line filtering

- `Rails::TestUnitRailtie` initializer `test_unit.line_filtering` → `ActiveSupport::TestCase.extend Rails::LineFiltering` (`rt/rails/test_unit/railtie.rb:15-19`). **Only `ActiveSupport::TestCase` descendants**; plain `Minitest::Test` classes ignore `file:line`.
- `LineFiltering.extended` picks by `Minitest::VERSION`: MT5 overrides `run(reporter, options)` merging `:filter`; MT6 overrides `run_suite` merging `:include` (`rt/rails/test_unit/line_filtering.rb:7-32`). 7.2 has only the MT5 `run` override (`rt72/…/line_filtering.rb:7-11`).
- `extract_filters` (`runner.rb:98-114`): `path:N`, `path:N-M`, `path:A:B` → `filters << [file, lines]`; plain file → `[file, []]`.
- `compose_filter` (`runner.rb:87-95`): normalizes `-n` (`"foo bar"` → `test_foo_bar`; `/re/` → also whitespace→underscore alt) and, if any line filters, returns `CompositeFilter` (`:154-188`) whose `===` ORs named filter + `Filter`s.
- `Filter#===(method)` (`:190-215`): `@runnable.method_defined?(method)`; line range → `TestParser.definition_for(instance_method)` (Prism; ripper fallback, `rt/rails/test_unit/test_parser.rb`) and `Range#overlaps?`; file-only → `source_location.first == file`.
- Rerun snippet: `"#{executable} #{relative_path}:#{line}"`, `executable = ENV.fetch("RAILS_TEST_EXECUTABLE", "bin/rails test")` (`reporter.rb:10,84-92`).

### 4.4 `Rails::TestUnitReporter` + plugin reporters

`Rails::TestUnitReporter < Minitest::StatisticsReporter` (`rt/rails/test_unit/reporter.rb:6`): replaces `ProgressReporter`; verbose `"Klass#name = 0.01 s = ."`; inline failure + rerun snippet unless `-d`; skips shown only with `-v`; `report` prints "Failed tests:" block when deferred; colors `.`=32 `E/F`=31 `S`=33 if tty. `SuppressedSummaryReporter` replaces `SummaryReporter` (suppresses `aggregated_results` when inline) (`rt/minitest/rails_plugin.rb:21-26,166-168`). `BacktraceFilterWithFallback(Rails.backtrace_cleaner, previous)` (`:8-19,158-163`). `app_root` from `RAILS_TEST_PWD` / `ENGINE_ROOT` / `Rails.root` / `Dir.pwd`.

### 4.5 Other Rails test classes (names)

| Class | Notes |
|---|---|
| `ActionDispatch::IntegrationTest` | `get post patch put delete head`, `follow_redirect!`, `open_session`, `assert_response assert_redirected_to assert_dom/assert_select`, `cookies session request response`; load hook `:action_dispatch_integration_test` (fixture_paths copied, `@routes` set — `rt/rails/test_help.rb:26-46`) |
| `ActionController::TestCase` | load hook `:action_controller_test_case` |
| `ActionDispatch::SystemTestCase < ActiveSupport::TestCase` | `driven_by(driver, using: :chrome, screen_size: [1400,1400], options: {}, &caps)` `actionpack-8.1.4/lib/action_dispatch/system_test_case.rb:158`; `served_by(host:, port:)` `:167` sets `Capybara.server_host/port`; `start_application` `:128` (Puma via Capybara) — Capybara server port must be per-worker |
| `ActionView::TestCase`, `ActionMailer::TestCase`, `ActiveJob::TestCase`, `ActionCable::Channel::TestCase`, `ActionCable::Connection::TestCase`, `Rails::Generators::TestCase` | |
| `ActiveJob::TestHelper` | `assert_enqueued_jobs assert_no_enqueued_jobs assert_performed_jobs assert_no_performed_jobs assert_enqueued_with assert_performed_with perform_enqueued_jobs queue_adapter queue_adapter_for_test` (swaps adapter in `before_setup`/`after_teardown`) |
| `ActionMailer::TestHelper` | `assert_emails assert_no_emails assert_enqueued_emails assert_enqueued_email_with assert_no_enqueued_emails deliver_enqueued_emails capture_emails` |
| `ActionCable::TestHelper` | `assert_broadcasts assert_no_broadcasts assert_broadcast_on capture_broadcasts pubsub_adapter` |

## 5. Drop-in contract for fast_rspec

### 5.1 Plug-in points

| Decision | Choice | Why |
|---|---|---|
| Primary hook | **Set `Minitest.parallel_executor` to our pool** (duck type `start`/`<<`/`shutdown`/`size`) | Public, version-stable seam used by both minitest and Rails; works for plain Minitest and AS |
| `parallelize(...)` | **Also override** (prepend on `ActiveSupport::TestCase.singleton_class`) → record `workers/with/threshold/parallelize_databases`, then install our executor instead of `ParallelizeExecutor` | `parallelize` just assigns the global; if we don't intercept, a later `parallelize` call in `test_helper.rb` replaces us |
| Load order | Install executor **after** `test_helper.rb` runs and before `Minitest.run` → do it in our plugin's `plugin_fast_rspec_init` (runs inside `Minitest.run`, after test files load in 8.1) | `parallelize` lives in user `test_helper`; init runs after it |
| MT6 plugin opt-in | `Minitest.register_plugin FastRspec::Minitest` from `require "fast_rspec"` (Railtie/`Bundler.require`) **and** ship `minitest/fast_rspec_plugin.rb` for MT5 autoload | MT6 never autoloads; MT5 does (would double-register → dedupe) |
| Ordering trigger | Call `Minitest::Test.parallelize_me!` (same as Rails) so jobs route to `<<`; leave `i_suck_and_my_tests_are_order_dependent!` classes serial in-parent | identical semantics to stock; serial-first ordering preserved by `run_all_suites` |
| Worker run of one test | MT6: `klass.new(m).run`; MT5: `Minitest.run_one_method(klass, m)` (keeps the `Result ===` check) | mirror `worker.rb:50-54` |
| Batching | Enqueue per method (forced by API), but ship **per-class batches** to workers and stream results back in one IPC frame per batch | AGENTS "one IPC message per file"; stock does 2 DRb RPCs per test |
| Result transport | Marshal `Minitest::Result` (both versions marshal by ivars); parent calls `reporter.synchronize { prerecord(stand-in, name); record(result) }` | reporters (Rails, minitest-reporters, SimpleCov hooks) see identical calls |

### 5.2 Must stay identical

| Surface | Requirement |
|---|---|
| Exit code | `Minitest.run` boolean → `exit` via autorun `after_run`; Interrupt → 1; empty run + filter → 1 |
| Reporter calls | parent-side `start`/`prerecord`/`record`/`report`, under `synchronize`; `prerecord` arg responds to `.name` |
| Output | "Running N tests in parallel using W processes" / "…single process (parallelization threshold is T)" line when user called `parallelize`; `Run options: --seed N`; Rails rerun snippets `bin/rails test path:line` |
| Seed | `--seed`/`SEED` → same shuffle (`methods.sort.shuffle` after `srand Minitest.seed`); our per-worker order must derive from it deterministically |
| Hooks | `parallelize_before_fork` (parent, once), `parallelize_setup { \|i\| }` (each worker, 0-based `i`, after fork, before tests, exceptions attached to every result of that worker), `parallelize_teardown { \|i\| }` (each worker on exit, plus parent once with no arg on 8.1) |
| `parallel_worker_id` | set to worker index in child (8.1) |
| Per-worker DB | names `"#{db}_#{i}"` (8.1) / `"#{db}-#{i}"` (7.2); reuse `ActiveRecord::TestDatabases.create_and_load_schema` — don't reimplement; respect `parallelize_databases: false` |
| `PARALLEL_WORKERS` | overrides `workers:` and forces parallel even under threshold |
| `with: :threads` | honored: thread pool, `lock_threads = false`, no per-worker DB, no setup hooks |
| `file:line`, `-n`, `-i`, `-x`, `--fail-fast`, `-b`, `-d`, `-c`, `--profile` | filtering happens in parent before enqueue → we receive only filtered methods; `--fail-fast` = `Interrupt` from `record` → must drain/kill workers and exit 1 |
| Crashed worker | in-flight test reported as `UnexpectedError(RuntimeError "result not reported")`, run continues |

### 5.3 Hard cases

| Case | Stock behavior | fast_rspec rule |
|---|---|---|
| `parallelize(workers: :number_of_processors)` already in `test_helper.rb` (generator default) | fork pool, cgroup-aware count | treat as "user opted in": keep their count; our default = same formula. Upgrade transport/scheduler only |
| `parallelize(workers: 2)` explicit | 2 processes | honor exactly (theirs wins) |
| No `parallelize` call (plain Minitest / old apps) | serial (MT `parallel_executor` exists but unused w/o `parallelize_me!`) | parallel by default = our value-add; must still fire `parallelize_setup` hooks + per-worker DB |
| Threshold (default 50, counts **unfiltered** loaded methods) | under → single process, no hooks, base DB | keep threshold when user set one; our default may be smarter (runtime-based) but the printed line must stay truthful |
| `with: :threads` on CRuby | Minitest thread executor | honor; on JRuby/TruffleRuby threads are our default anyway |
| Unmarshalable result (custom `Assertion` with Proc ivar, `metadata` with IO, exception class undefined in parent → `DRbUnknown`) | worker rewrites all failures to `UnexpectedError(DRb::DRbRemoteError)` — F becomes E | must not crash; preferred: degrade per-failure (keep F/S codes, stringify message+backtrace). Document if we diverge from E-rewrite in `parity-divergences.md` |
| `parallelize_setup` raises | swallowed; every result from that worker gets the error prepended | same |
| Worker segfault/OOM | "result not reported" error per in-flight test | same + one-line repro |
| `ActiveSupport::Testing::Isolation` tests | `parallelize_me!` + fork per test | must run inside worker without double-fork deadlock; respect `NO_FORK` |
| System tests (`SystemTestCase`) | processes OK; threads not supported | per-worker Capybara server port + `served_by` respect |
| MT6 + Rails 7.2 / 8.0 | 7.2: `Minitest.run_one_method` NoMethodError in workers, line filter override on dead `run`, rails plugin never loaded; 8.0.5: `test_order=` ignored | detect and fail fast with a clear message (or pin advice) — don't silently "fix" upstream |
| MT5 vs MT6 option keys | `:filter` vs `:include`; `-n` hidden alias on MT6; Rails re-adds `-n` w/ warning | read both keys; never add our own `-n`/`-e` (Rails `-e` = environment) |
| MT6 plugin opt-in | plugins not in `Minitest.extensions` don't run | register explicitly; also don't assume other plugins (pride, reporters) loaded |
| `minitest-reporters` / custom reporters | replace `reporter.reporters` in their init | they run in parent and see the same calls — never call reporters from workers |
| SimpleCov | `at_exit` in each fork; `Minitest.allow_fork` false prevents child `after_run` | our workers must exit via `exit!`-safe path and merge coverage (owned by coverage battery) |
| `ParallelizeExecutor` type checks | `Isolation` checks `is_a?(ParallelizeExecutor)` (`as/testing/isolation.rb:12`) | our executor should subclass or satisfy `is_a?` to avoid unwanted `parallelize_me!` side effect |
