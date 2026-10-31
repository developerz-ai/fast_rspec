# Prior art: fast parallel test running

As of 2026-10. We take mechanisms from these tools, not their marketing. Each section ends with what to steal and what to avoid. Local gem sources were read from `~/.local/share/mise/installs/ruby/3.4.7/lib/ruby/gems/3.4.0/gems/` (parallel_tests 5.6.0, activesupport/activerecord 8.1.4, minitest-parallel_fork 2.1.1). Remote sources were read on GitHub or hexdocs.

## Summary table

| Tool | Model | Scheduling | DB isolation | Result transport | Boot cost |
|---|---|---|---|---|---|
| ExUnit (Elixir) | BEAM processes in one VM: one per async module, one per test | Pull: async modules up to `max_cases`, then a barrier, then sync modules one at a time | Ecto SQL Sandbox: one DB, one transaction per test, owned by a process | Messages in the VM | 1× (one VM) |
| parallel_tests | `IO.popen` spawns N separate `rspec`/`ruby` processes | Static groups, greedy longest-first from runtime log, falls back to file size | `TEST_ENV_NUMBER`: DB per process, created by the user | Child stdout text, parsed by regex | N× full boot |
| turbo_tests | `Open3.popen3` spawns N `rspec` processes | Static groups (reuses parallel_tests grouper) | `TEST_ENV_NUMBER` | JSON rows on stdout, UUID-delimited | N× full boot |
| flatware | Fork N workers after an optional `before_fork` preload | Chunks balanced by last runtime (`example_status_persistence`) | `TEST_ENV_NUMBER` + `after_fork` reconnect | DRb (v2+; ZeroMQ before) | 1× when preloaded |
| test-queue | Preload, then fork N; master plus a discovery fork | **Pull queue over Unix/TCP socket**, slowest first from stats, unknown suites first | `after_fork(num)` + `prepare(concurrency)` hooks (user-written) | Marshal over socket + per-worker tmp files | 1× |
| Rails `parallelize` | Fork N after loading the tests (or Minitest threads) | Pull queue over DRb, **one job per test method**, no runtime ordering | `db_N`, rebuilt from schema **on every run** | DRb: the reporter is a `DRbObject`, so every report is an RPC | 1× |
| minitest-parallel_fork | Fork N after loading | Static: suites shuffled, then round-robin `j % n == i` | `after_parallel_fork(i)` hook | Marshal over a pipe, once at the end | 1× |
| knapsack (OSS) | One process per CI node | Static split from `knapsack_rspec_report.json` | Per node | n/a | 1× per node |
| knapsack_pro Queue Mode | One long-lived RSpec process per CI node | **Pull batches from SaaS API**; slow files split by example | Per node | API + local formatter | 1× per node |
| ci-queue / rspec-queue / minitest-queue | One process per CI node (or local workers) | **Pull queue in Redis**; leader populates; lost work requeued; flaky failures requeued | Per node | Redis + `report` aggregator | 1× per node |
| Spring | Long-lived preloaded server, fork per command | n/a | n/a | Unix socket, fd passing | 0 after warm-up, plus stale-code risk |
| bootsnap | Cache (ISeq, YAML, `$LOAD_PATH` index) | n/a | n/a | n/a | Cuts each boot by ~50–75% |
| pytest-xdist | Spawn N interpreters (execnet) | `load`/`loadscope`/`loadfile`/`loadgroup`/`worksteal` | User fixtures (`worker_id`) | execnet channels | N× import |
| Jest | jest-worker child processes | Per file; failed first, then slowest first from cache; runs in band below a threshold | n/a | IPC | N× module graph |
| Go `go test` | One binary per package, `-p` packages at a time; `t.Parallel()` goroutines inside | Package-level static; inside a package, parallel tests pause until the serial ones finish | n/a | Text / `test2json` | Compile per package; cached |

---

## ExUnit (Elixir)

Mechanism, from `lib/ex_unit/lib/ex_unit/runner.ex` (`async_loop/4`, ~L104–138) and https://ex-unit.hexdocs.pm/ExUnit.html:
- `use ExUnit.Case, async: true` opts a **module** in. Tests inside one module always run serially. Parallelism happens only between modules.
- `async_loop`:
  1. Computes `available = max_cases - map_size(running)` and calls `ExUnit.Server.take_async_modules(available)`.
  2. Spawns one monitored process per `{group, modules}`. Modules in the same `group:` run sequentially in that one process (`spawn_modules/4`, ~L165–186).
  3. When no async modules are left, a **barrier** waits for every running async module to finish.
  4. Then the sync modules run **one at a time**.
- `max_cases` defaults to `System.schedulers_online * 2`, meaning 2× cores, which over-subscribes to hide IO wait. `--trace` forces it to 1.
- Every test gets a fresh process (`spawn_test_monitor/4`). On timeout the runner kills the test process and records a `TimeoutError`. `on_exit` callbacks run in the parent.
- Seed:
  - Each module's tests are shuffled with `:rand.seed(alg, {seed, seed, seed})`.
  - Each test reseeds with `{phash2(module), phash2(name), seed}` (`generate_test_seed/3`, ~L430). The random stream therefore does not depend on which tests ran before it or which process ran it.
  - `--seed 0` means definition order.
- Mix CLI (https://mix.hexdocs.pm/Mix.Tasks.Test.html):
  - `--partitions N` + `MIX_TEST_PARTITION=i`: files sorted, then dealt round-robin. Meant for CI fan-out. `MIX_TEST_PARTITION` is readable in config, typically for a per-partition DB name. Cover data goes to `cover/<partition>.coverdata` for a later merge.
  - `--stale`: runs a test file if it changed, or if any module it references (recursively, transitively) changed since the last `--stale` run. Driven by a manifest built from the compiler's dependency graph.
  - `--failed`: reruns failures from the manifest at `failures_manifest_path`.
  - `--slowest N` / `--slowest-modules N`: include `setup` time. Both force trace mode.
  - `--repeat-until-failure N`: for flaky hunts. `--max-failures`.
  - `file:LINE`: runs the closest test at or before the line. A `describe` line runs the whole block.
- Tags: `@tag`, `@moduletag`, `@describetag`, `--include`/`--exclude`/`--only`. `:tmp_dir` tag gives the test a unique directory.

Steal:
- **Async-first, then a barrier, then a serial lane.** This is the model for tests marked serial-only in thread mode.
- **Per-test seed = hash(file/group id, example id, global seed).** The order, and the Faker/`rand` stream, stay stable however work is spread across workers.
- `--partitions`-style deterministic CI split as the zero-infrastructure baseline. Coverage is written per partition, then merged.
- `--slowest` that includes setup time. Rerun-failed from a manifest (RSpec already has `example_status_persistence_file_path`; reuse it).
- A built-in `tmp_dir` per test, per worker.

Avoid:
- Requiring users to opt in per module (`async: true`). Our default is parallel. Opt-out is a tag, and process isolation makes the default safe on CRuby.
- Default 2× cores for CPU-bound Ruby processes. Use 1× cores for forks. Only the thread mode may over-subscribe for IO-heavy suites.

## Ecto.Adapters.SQL.Sandbox (ownership model)

Mechanism (https://ecto-sql.hexdocs.pm/Ecto.Adapters.SQL.Sandbox.html):
- **One DB.** The pool wraps the real connections. `checkout/2` makes the calling process the **owner** of one connection, opened inside a transaction (`sandbox: true`). The transaction rolls back at `checkin` or when the owner dies.
- Modes:
  - `:auto`: any process implicitly checks out.
  - `:manual`: an explicit checkout is required; `test_helper` sets this.
  - `{:shared, pid}`: every process uses `pid`'s connection. **Only valid for sync tests.**
- `allow(repo, owner, child)`: another process may use the owner's connection, which keeps async tests possible when the test talks to GenServers or Tasks. `$callers` propagation lets tasks inherit the allowance automatically.
- `start_owner!/2` + `stop_owner/1`: an unlinked owner process for resources that outlive the test, such as a LiveView. `ownership_timeout` (120 s) detects leaks.
- Caveats:
  - Concurrent tests are **Postgres-only**. MySQL deadlocks.
  - Tests that insert the same unique values serialize on row locks.
  - Opposite-order updates can deadlock.
  - Deferred constraints never fire. Workaround: `SET CONSTRAINTS ALL IMMEDIATE`.
  - "Owner exited" errors when a client outlives its owner.

How this maps to ActiveRecord on a thread pool:
- AR already has the building blocks:
  - `ConnectionPool#pin_connection!(lock_thread)` (`activerecord-8.1.4/lib/active_record/connection_adapters/abstract/connection_pool.rb:368`) pins **one connection per pool**, opens a non-joinable transaction, and sets `lock_thread`.
  - `TestFixtures#setup_transactional_fixtures` (`test_fixtures.rb:192`) calls it for every pool.
- Rails thread mode (`parallelize(with: :threads)`) sets `lock_threads = false` (`activesupport-8.1.4/lib/active_support/testing/parallelize_executor.rb:41`). The pin is still **per pool, not per test**, so every concurrent test thread shares **one connection and one transaction**. Writes leak between tests, and rollback at teardown is racy. That is not isolation.
- What we need is ownership keyed by **test**, not by pool:
  - `pin` keyed by the test's execution context (`ActiveSupport::IsolatedExecutionState.context`), with its own checkout and transaction.
  - Threads or fibers spawned by the test (Capybara server, `Thread.new` in the code under test, ActiveJob inline) inherit the owner through an **allowance**: we propagate the owner id to child threads, the equivalent of Elixir `$callers`.
  - Tests that cannot be scoped run in the **shared mode equivalent**: the serial lane after the async barrier, with one pinned shared connection, exactly as Rails does today.
- Postgres: safe. MySQL InnoDB: per-test transactions concurrently on one DB do deadlock on gap locks and unique keys, so in thread mode MySQL gets per-thread DBs (template clone), not one sandbox. SQLite: one writer, so use per-thread DB files.

Steal: the ownership + allowance + shared-mode trio, verbatim in concept. Ownership timeout as leak detection.
Avoid: Rails' current per-pool pin under threads. Running one shared DB with concurrent transactions on MySQL.

## parallel_tests (grosser, 5.6.0, read locally)

Mechanism:
- `cli.rb:56–69` `execute_in_parallel`: `Parallel.map_with_index(items, in_threads: N)`. One Ruby **thread per group**, each blocking on `IO.popen(env, cmd)` (`test/runner.rb:107`). Every group is a **fresh `rspec`/`ruby` process** that boots the whole app.
- Grouping, `test/runner.rb:47–77` `tests_with_size` and `--group-by`:
  - `found`: weight 1 each.
  - `filesize`.
  - `runtime`.
  - default: use the runtime log only if `runtimes.size * 1.5 > tests.size` (`:67`), else file size.
  - `steps`/`scenarios` for Cucumber.
- Packing, `grouper.rb:15–47`, `:112`, `:135`: **greedy LPT (longest-processing-time first)**. Files are sorted by size descending, and each goes to `smallest_group`. Unknown runtimes get the **average** of known ones (`test/runner.rb:308–314`).
- Groups are **static**: decided before start, so there is no rebalancing when an estimate is wrong.
- Runtime log `tmp/parallel_runtime_rspec.log` (`rspec/runner.rb:23`), one `path:seconds` per line:
  - Written by `ParallelTests::RSpec::RuntimeLogger` (`rspec/runtime_logger.rb:14–48`). It times top-level groups and sums per file.
  - Records only when `TEST_ENV_NUMBER` is set.
  - Each process appends under a file lock (`lock_output`).
  - The user must opt in with `--format ParallelTests::RSpec::RuntimeLogger --out tmp/...`.
- `TEST_ENV_NUMBER`: `''` for process 0, then `'2','3',…` (`test/runner.rb:139–145`). `--first-is-1` changes that to `'1'`. `PARALLEL_TEST_GROUPS` = N. `$TEST_ENV_NUMBER` is substituted in args. `database.yml` uses `myapp_test<%= ENV['TEST_ENV_NUMBER'] %>`, and the user runs `rake parallel:create parallel:prepare`.
- `--single`/`--isolate`/`--isolate-n`: pattern-matched files go to group 0 or to dedicated groups (`grouper.rb:20–44`). `--specify-groups`: manual groups.
- Output: raw child stdout, interleaved unless `--serialize-stdout`, which prints nothing until the group finishes. The summary comes from regexes over the text (`line_is_result?`). Fail-fast: `stop_all_processes` kills via the PID file (`cli.rb:63`).
- `ParallelTests.wait_for_other_processes_to_finish` (`parallel_tests.rb:98`) is a `sleep 1` poll on the PID file count. It exists for "last process does the after-suite work" hacks.

Why separate processes: it is generic (any command via `-e`), needs no fork safety, and works on Windows. Cost: **N × boot** (Rails boot is often 3–15 s), N × memory with no copy-on-write, and static groups whose tail grows with estimate error.

Steal:
- LPT packing as the **initial order** of a dynamic queue. Average-of-known for unknown files. A coverage threshold for trusting the log.
- `TEST_ENV_NUMBER` / `PARALLEL_TEST_GROUPS` **as a compatibility surface**. Existing `database.yml` files and CI scripts already key on them.
- The isolate lane concept.

Avoid:
- Spawn-per-group.
- Static groups.
- Regex-parsing human output.
- An opt-in runtime formatter: we record always.
- Per-process log appends under a lock: the parent records.
- `sleep`-polling coordination.
- The default of interleaved output.

## turbo_tests (serpapi)

Mechanism (`lib/turbo_tests/runner.rb`, read on GitHub):
- **Uses parallel_tests' grouper** (`tests_in_groups`, ~L80) with `tmp/turbo_rspec_runtime.log`.
- `Open3.popen3` spawns one `rspec` per group (~L176) with `TEST_ENV_NUMBER=i+1` and `RUBYOPT` to inject its formatter.
- `TurboTests::JsonRowsFormatter` writes one JSON row per event to stdout, prefixed by a per-process UUID delimiter (`RSPEC_FORMATTER_OUTPUT_ID`). A reader thread per child splits on the UUID. Text before the delimiter is the user's stray output; after it is JSON.
- Messages go onto one `Queue`. The main thread dispatches `example_passed`/`failed`/`pending`/`group_*` into a **single real RSpec reporter**, so the output looks like one `rspec` run (`handle_messages`, ~L223–276).
- Fail-fast kills only the reader threads (~L249). The child `rspec` processes keep running. `@error` (load errors outside examples) is set but never affects the exit code.

Steal: **re-hydrating worker events into a real RSpec reporter in the parent.** This is how drop-in formatter output works: any user formatter runs once, in the parent, on merged notifications. Separate the user's stray stdout from the structured channel.
Avoid: JSON over stdout (fragile, slow to serialize). Spawn per group. Fail-fast that leaves orphans. Load errors that don't fail the run.

## flatware (briandunn)

Mechanism (https://github.com/briandunn/flatware):
- The main process forks one worker per CPU (`-w N`).
- Preloading is optional through `Flatware.configure { before_fork { require 'rails_helper' } }`. The README warns that "if ActiveRecord connects before flatware forks off workers, each will die messily".
- `after_fork { |n| ActiveRecord::Base.establish_connection(db + n) ; SimpleCov.at_fork.call(n) }`.
- Jobs are spec-file chunks balanced by last run times from RSpec's own `example_status_persistence_file_path`.
- Workers report through a message layer (DRb in v2, ZeroMQ before). The sink prints progress and then the final summary. `flatware fan <cmd>` runs a command once per `TEST_ENV_NUMBER`, for example `db:test:prepare`.

Steal:
- Reuse **RSpec's own persistence file** as a runtime source when present.
- A `fan` equivalent for per-worker setup (`fast_rspec fan rake db:prepare`).
- `SimpleCov.at_fork` as the coverage hook.

Avoid: preload as opt-in. Pre-chunked work instead of per-file pull. The "connected before fork, dies messily" failure mode: we disconnect every known client before fork ourselves.

## test-queue (tmm1) — closest to our design

Mechanism (`lib/test_queue/runner.rb`, read on GitHub):
- The master preloads the app, then forks N workers (`spawn_workers`, ~L280). `TEST_QUEUE_WORKERS` defaults to all cores.
- **Discovery runs in a separate forked process** (`discover_suites`, ~L298). It loads spec files and streams `NEW SUITE` messages to the master, so workers start before discovery ends.
- The master runs a `UNIXServer` (or a `TCPServer` for `host:port`) (`start_master`, ~L233). Protocol (`distribute_queue`, ~L452–525):
  - Every line is prefixed with `TOKEN=<run_token>`.
  - `POP host pid` gets back a Marshaled suite or `WAIT`.
  - `WORKER <bytes>` carries final worker data.
  - `KABOOM` aborts.
- Queue order: `sort_by { -suite.duration }` from `.test_queue_stats`, i.e. **slowest first** (~L60). **Unknown suites go to the front** (`@queue.unshift`, ~L341), because they might be long.
- `TEST_QUEUE_SPLIT_GROUPS=1` splits RSpec suites per example rather than per group. `:no_split` tag opts a group out.
- Worker stdout/stderr go to `/tmp/test_queue_worker_<pid>_output`. Suite timings go to `/tmp/…_suites` (Marshal). The master reads both after `waitpid` (`collect_worker_data`, ~L433). Output is printed only on failure or with `TEST_QUEUE_VERBOSE`.
- The master records assignments and flags suites that were never run or were run by the wrong worker.
- Hooks:
  - `prepare(concurrency)` in the master before fork: create N DBs.
  - `after_fork(num)` in the worker: switch DB/Redis.
  - `around_filter(suite)`.
  - `cleanup_worker`.
- Distributed mode: `TEST_QUEUE_RELAY=host:port` remote masters join a central queue with `TEST_QUEUE_RELAY_TOKEN`.
- `TEST_QUEUE_EARLY_FAILURE_LIMIT`.
- Bug seen: the final exit status is recomputed as the sum of worker exit codes (~L208), which overwrites the unassigned/misrun penalties.

Steal:
- **Almost all of it**: preload → fork → pull-per-suite over a Unix socket, slowest first from stats, unknown first.
- Per-example split for huge groups.
- Assignment audit, so no suite is silently dropped.
- Run token. Relay mode as the multi-machine roadmap.

Avoid:
- Results only at worker exit through tmp files: there is no live progress and a worker crash loses its results. Stream per file instead.
- Marshal of arbitrary objects (version-fragile). Use a fixed schema.
- Hooks the user must write: we auto-wire.
- Exit-code summing.

## Rails `parallelize` (activesupport 8.1.4, read locally)

Mechanism:
- `ActiveSupport::TestCase.parallelize(workers: :number_of_processors, with: :processes, threshold: 50)` (`test_case.rb:113`). It installs `ParallelizeExecutor` as `Minitest.parallel_executor`.
- Parallelism turns on only if `tests_count > threshold` or `PARALLEL_WORKERS` is set (`parallelize_executor.rb:58`).
- `Parallelization#start` (`parallelization.rb:47`) runs the `before_fork` hooks, then forks N `Worker`s. `DRb.start_service("drbunix:", Server.new)` is the queue (`:40`).
- The parent `<<`s every `[klass, method, reporter]`. The **reporter is wrapped as a `DRbObject`** (`server.rb:32`).
- `Worker#work_from_queue` loops on `@queue.pop` (`worker.rb:36`). Each job runs `Minitest.run_one_method` and then `@queue.record(reporter, result)`. That is **2+ DRb round-trips per test method**, plus reporter callbacks.
- `in_flight` tracking (`server.rb:39`). `remove_dead_workers` on shutdown. A setup exception in `after_fork` is reported as a test failure.
- AR hooks (`activerecord-8.1.4/lib/active_record/test_databases.rb`):
  - `before_fork`: `clear_all_connections!`.
  - `after_fork(i)`: `db_config._database = "#{db}_#{i}"`, then `DatabaseTasks.reconstruct_from_schema` (`:23–36`). This **reloads the schema into every worker DB on every run**.
- `with: :threads`: uses Minitest's own `Parallel::Executor` and sets `lock_threads = false`. As covered in the Ecto section, all test threads share one pinned connection.
- `parallelize_setup` / `parallelize_teardown` are user hooks per worker.

Steal:
- The size threshold (don't fork for tiny runs).
- `before_fork`/`after_fork`/`run_cleanup` hook registries, so other gems can plug in. We should **fire Rails' own hooks** so `parallelize_setup` users keep working.
- `in_flight` plus dead-worker accounting.
- Turning an `after_fork` exception into a reported failure.

Avoid:
- Per-test-method queue granularity plus a DRb reporter: syscall- and allocation-heavy, and it breaks "one IPC message per file".
- Schema reload per worker per run: use template clone plus a schema fingerprint.
- No runtime ordering: random order means a long tail.
- The shared-connection threads mode.

## minitest-parallel_fork (jeremyevans, read locally)

Mechanism: overrides `Minitest.run_all_suites`. `Runnable.runnables.shuffle`, then forks `NCPU` (default 4) children. Child `i` runs suites where `j % n == i` (`parallel_fork.rb:98–114`), then writes `Marshal.dump([count, assertions, results])` to a pipe at exit. The parent merges into the stat reporter. Hooks: `before_parallel_fork`, `after_parallel_fork(i)`, `on_parallel_fork_marshal_failure`.
Steal: how small a correct fork runner can be (~150 lines). A pipe per child. Unparallelizing `parallelize_me!` suites inside a child.
Avoid: static round-robin, results only at exit, `NCPU` default of 4, no live output.

## knapsack / knapsack_pro

Mechanism:
- **knapsack (OSS)**: a static split per CI node from a committed `knapsack_rspec_report.json` (file → seconds), with `CI_NODE_TOTAL`/`CI_NODE_INDEX`.
- **knapsack_pro Queue Mode** (https://docs.knapsackpro.com):
  - Each CI node runs **one long-lived RSpec process** and repeatedly asks the API for the next **batch** of files until the queue drains.
  - Between batches it resets `RSpec.world` and runs the next subset in the same process, firing `before_queue`/`after_subset_queue`/`after_queue` hooks.
  - Fallback mode, when the API is unreachable, is a deterministic file-name split.
  - "Split by test examples" turns slow files into `file[1:2:3]` example IDs.
  - Integrates with parallel_tests for queue mode across local CPUs.

Steal:
- **Batches** (pull k files at a time when the queue is long, 1 at a time near the end), which reduces round-trips.
- Split slow files by example ID (`path[1:2:3]`, RSpec's native id filter).
- Deterministic fallback when the coordinator is unavailable.

Avoid: a SaaS dependency in the default path. Hooks the user must add. Running many `RSpec::Core::Runner.run` calls in one process without a full world reset (known leaks of `before(:suite)` and shared state).

## ci-queue (Shopify) — rspec-queue / minitest-queue

Mechanism (https://github.com/Shopify/ci-queue):
- Redis-backed. Workers run **leader election**, and the leader pushes the test list. Everyone reserves tests until the queue is empty.
- A dead worker's reserved tests go back into the queue.
- Optional **requeue of failures** (`--max-requeues`, `--requeue-tolerance`) so a flaky failure is retried on another worker before failing the build.
- `--max-consecutive-requeues` circuit breaker.
- A separate `report` process waits for the queue to drain and aggregates errors.
- `bisect --queue test_order.log --failing-test X` for **leaky-test bisection** using the recorded per-worker order.
- Test id = `Class#method|path`. Redis must use `allkeys-lru`.

Steal:
- **Record each worker's exact execution order** so a failure can be reproduced and bisected locally (`fast_rspec bisect`; RSpec has `--bisect`, but only for single-process runs).
- Requeue lost work.
- Flaky retry as opt-in, always reported as flaky, never hidden.

Avoid: Redis as a dependency for local runs. Flaky retry on by default (masks bugs).

## Spring / bootsnap

- **Spring**: a background server preloads the app and **forks a child per command** (`rspec`, `rails test`) over a Unix socket, passing the tty file descriptors. File watchers restart it on change. The known pain is stale code and stale constants after edits and gem changes, which is why it was removed from new Rails apps by default (Rails 7.0).
- **bootsnap**: caches `$LOAD_PATH` resolution (removes an O(paths × requires) scan), compiled ISeq, and YAML/JSON. It makes cold boot cheaper, and it helps every boot including ours.

Steal: bootsnap is free and on by default when present. Respect it, and make sure the cache dir is per-worker-safe.
Avoid: a persistent daemon in the default path. Preload per invocation; a fork server (`fast_rspec --watch`) is a later opt-in.

## pytest-xdist / Jest / Go (brief)

- **pytest-xdist** (https://pytest-xdist.readthedocs.io/en/stable/distribution.html):
  - `load`: send to any free worker in chunks (`--maxschedchunk`).
  - `loadscope`: per module or class, keeping costly fixtures on one worker.
  - `loadfile`: per file.
  - `loadgroup`: `xdist_group` marker pins a group to one worker.
  - `worksteal`: even initial split, then idle workers steal from busy ones' queues when they have ≥2 left.
  - Steal: **`loadfile` as our default unit** (keeps `before(:all)`/`setup_all` semantics). A `group` tag maps to ExUnit `group:` and xdist `loadgroup`.
- **Jest**:
  - The test sequencer orders **previously failed files first**, then slowest from its cache, then file size.
  - Runs **in band** (no workers) when the estimated run is small.
  - `--onlyChanged`/`--changedSince` use the module graph plus git.
  - Steal: failed-first ordering, the in-band threshold from estimated runtime (not test count).
- **Go**:
  - `t.Parallel()` **pauses** the test until all serial tests in the package finish, then runs it with the others up to `-parallel` (default GOMAXPROCS). This is ExUnit's barrier in reverse.
  - Packages run as separate binaries, up to `-p` at a time.
  - **The test result cache** (successful results keyed by binary hash, flags, env vars and files read) is the strongest zero-config "skip unchanged".

## Test impact analysis (roadmap, not v1)

| Tool | Mechanism | Fit |
|---|---|---|
| `mix test --stale` | Compiler dependency graph manifest; file or transitive module change → rerun | Ruby has no static graph. Approximate it with Coverage |
| Crystalball (toptal) | Runs suite with `Coverage` per example → map example → source files; `git diff` selects examples | Closest Ruby analog. Map is costly to build and goes stale. Must treat `config/`, `db/schema.rb`, `Gemfile.lock` as "run all" |
| Jest `--onlyChanged` | Module graph plus git status | Same idea, static |
| Go test cache | Hash of binary + inputs read | Needs hermeticity Ruby lacks |
| ci-queue bisect | Recorded order → bisect leaky test | v1-adjacent: we record order anyway |

Plan: v1 records a per-file `Coverage.result` digest in the same runtime log behind `FAST_RSPEC_IMPACT=1` (method-level `Coverage` to keep overhead low; unmeasured). v2 adds `--changed`, which uses the map plus git diff, falling back to the full run on unknowns. Measure overhead first.

---

## Decisions for fast_rspec

| # | Decision | Why (one line) | Source |
|---|---|---|---|
| 1 | **CRuby: preload app + spec files once in the parent, then fork N = cores** | One boot, copy-on-write memory; loading specs in the parent gives exact example counts and ids for drop-in output | test-queue, Rails, parallel_fork |
| 2 | Close every known socket (AR, Redis, HTTP pools) before fork; reconnect lazily in the child | flatware's "dies messily"; Rails `clear_all_connections!` | flatware, Rails |
| 3 | **Pull queue (work stealing from a central queue), unit = file**, one message per file | Self-balancing; file keeps `before(:all)`/`setup_all` semantics; meets the IPC budget | test-queue, xdist `loadfile` |
| 4 | Initial order: failed-last-run first, then **longest first (LPT)**, unknown files first | Failures surface early; LPT minimizes the tail; unknowns might be long | Jest, parallel_tests, test-queue |
| 5 | Split files whose estimate > total/N into example-id chunks (`path[1:2:3]`), unless tagged `:no_split` | One huge file is otherwise the critical path | knapsack_pro, test-queue `SPLIT_GROUPS` |
| 6 | Batch pulls: k files per pull while the queue is long, 1 near the end | Fewer round-trips without hurting the tail | knapsack_pro batches, xdist chunks |
| 7 | Runtime log written **by the parent**, always on, atomic rename; EWMA per file, per example for split files; seeded from RSpec's persistence file or parallel_tests' log if present | No opt-in formatter, no lock contention; zero-config warm start | parallel_tests, flatware |
| 8 | Transport: `socketpair` per worker, length-prefixed fixed-schema binary (C ext packs, pure-Ruby twin); **no DRb, no JSON on stdout, no Marshal of user objects** | Rails' per-test DRb RPC and turbo_tests' JSON-on-stdout are the costs to beat | Rails, turbo_tests |
| 9 | Parent re-hydrates notifications into the **real RSpec reporter / Minitest reporter**, so user formatters run once on merged events | Byte-identical drop-in output | turbo_tests |
| 10 | Worker stdout/stderr captured per file and printed with that file's result; never interleaved | Readable output without `--serialize-stdout` waits | test-queue, parallel_tests |
| 11 | Per-test seed = hash(global seed, file, example id); same `--seed` gives the same per-file order wherever it runs | Order and Faker reproducible regardless of worker placement | ExUnit |
| 12 | Record each worker's execution order; failure prints a repro (`--seed S` + file list) and `fast_rspec bisect` replays it | Leaky-test debugging in parallel mode | ci-queue |
| 13 | In-flight tracking + assignment audit; a crashed worker → its file is reported as an error, the parent re-forks a replacement from the preloaded image | No silent drops; parent is the template | Rails `in_flight`, test-queue |
| 14 | Fail-fast: parent stops dispatch, SIGTERM then SIGKILL to the process group, then reaps | turbo_tests leaves orphans | turbo_tests (anti) |
| 15 | Below a threshold (estimated runtime < fork + DB setup cost, or a single file), run in-process with no pool | Small runs must not get slower than stock | Rails threshold, Jest in-band |
| 16 | Per-worker DB: `<db>_<n>` created by **template clone** (PG `CREATE DATABASE … TEMPLATE`, MySQL schema-only copy, SQLite file copy), kept across runs and rebuilt only when the schema fingerprint changes | Rails' per-run `reconstruct_from_schema` is pure overhead | Rails (anti), parallel_tests `parallel:prepare` |
| 17 | Set `TEST_ENV_NUMBER` (`''`,`2`,…) and `PARALLEL_TEST_GROUPS`; honor a `database.yml` that already uses them; also fire Rails' `parallelize_setup`/`after_fork` hooks | Existing configs and CI scripts keep working (drop-in) | parallel_tests, Rails |
| 18 | **Thread pool (JRuby/TruffleRuby): ExUnit-style sandbox**: per-test connection ownership (pin keyed by execution context, not pool), allowance propagated to child threads, PG only; MySQL/SQLite use per-thread DBs | Rails' threads mode shares one transaction across tests | Ecto Sandbox, Rails (anti) |
| 19 | Opt-out tag (`:serial` / `parallelize false`) → serial lane: async files first, **barrier**, then serial files one at a time in one worker | Same model in fork and thread modes; explicit and visible | ExUnit, Go `t.Parallel` |
| 20 | `group:` tag pins files to the same worker in sequence | Shared expensive fixtures or external resources without full serialization | ExUnit `group:`, xdist `loadgroup` |
| 21 | Fork-mode N = cores; thread-mode default N = cores, `FAST_RSPEC_WORKERS` overrides | Ruby workers are CPU-bound; 2× only helps IO-heavy suites | ExUnit `max_cases` (adjusted) |
| 22 | CI fan-out v1: `--partition i/N` deterministic LPT split over the runtime log (ExUnit/knapsack OSS); v2: relay queue over TCP with a run token | Zero-infra first, dynamic cross-machine later | Mix, test-queue relay, ci-queue |
| 23 | Per-worker coverage files merged by the parent | Coverage must work by default | Mix `--partitions`, `SimpleCov.at_fork` |
| 24 | No Spring-style daemon in the default path; bootsnap respected; `--watch` fork server later | Stale-code bugs outweigh boot savings once we boot only once | Spring (anti) |
| 25 | Flaky retry/requeue: opt-in only, always reported as flaky | Never hide nondeterminism by default | ci-queue |
| 26 | Test impact (`--changed`): roadmap, Coverage-based map + git diff, falls back to the full run | Big win, but must be measured and never skip wrongly | Crystalball, `mix --stale`, Go cache |
