# Compat target — DB cleaning, shoulda, Capybara/system, SimpleCov

As of 2026-10. Compat target for the batteries `database_cleaner`, `shoulda-matchers`, `shoulda-context`, `capybara` (+ `cuprite`, `selenium-webdriver`), `simplecov`, plus per-worker DB isolation.
Sources: installed gems, read locally. `$G` = `$(gem env gemdir)/gems`. Versions read: `database_cleaner` 2.1.0, `database_cleaner-core` 2.0.1, `database_cleaner-active_record` 2.2.2, `database_cleaner-sequel` / `-redis` (GitHub `main`), `shoulda-matchers` 8.0.1 + 7.0.1, `shoulda-context` 2.0.0, `capybara` 3.40.0, `cuprite` 0.18, `ferrum` 0.18.0, `simplecov` 0.22.0, `railties`/`activerecord`/`actionpack` 8.0.5 + 8.1.4, `sidekiq` 8.1.6, `devise` 5.0.4, `warden` 1.2.9.
Real-world patterns: ~60 helper/support files across private Rails apps under `~/workspace`, anonymized (§6).

## 1. database_cleaner

### 1.1 Gem layout

| Gem | Role | Entry side effect |
|---|---|---|
| `database_cleaner` 2.1.0 | meta gem | `lib/database_cleaner.rb:1` → `require "database_cleaner/active_record"` only |
| `database_cleaner-core` 2.0.1 | `DatabaseCleaner` module, `Cleaners`, `Cleaner`, `Strategy`, `Safeguard` | none |
| `database_cleaner-active_record` 2.2.2 | `DatabaseCleaner::ActiveRecord::{Transaction,Truncation,Deletion}` | `active_record.rb:4-11` — `ActiveSupport.on_load(:active_record) { DatabaseCleaner[:active_record].strategy = :transaction }` |
| `database_cleaner-sequel` | `DatabaseCleaner::Sequel::{Transaction,Truncation,Deletion}` | `lib/database_cleaner/sequel.rb:7` — `DatabaseCleaner[:sequel].strategy = :transaction` (github.com/DatabaseCleaner/database_cleaner-sequel) |
| `database_cleaner-redis` | `DatabaseCleaner::Redis::Deletion` only | `lib/database_cleaner/redis.rb:5` — `DatabaseCleaner[:redis].strategy = :deletion` (github.com/DatabaseCleaner/database_cleaner-redis) |

**Consequence:** a strategy is already set the moment the adapter loads. "Strategy is non-null" ≠ "user configured it". Detection must look for user *hooks* (see §5), not state.

### 1.2 API (core)

| Call | Source | Semantics |
|---|---|---|
| `DatabaseCleaner[:active_record, db: :primary]` | `cleaners.rb:11-14` | Lookup-or-create, keyed `[orm, opts]`. `db:` = Symbol (name in `database.yml` / `configs_for`), model class, or (redis) URL / `::Redis` |
| `DatabaseCleaner.strategy = :truncation` / `[:truncation, {except: %w[x]}]` | `cleaners.rb:16-19`, `cleaner.rb:42-53` | Applies to **all** registered cleaners; builds a **new strategy object** each call (drops caches, see 1.4) |
| `DatabaseCleaner.start` / `.clean` | `cleaners.rb:21-29` | Safeguard, then each cleaner. `start` is a no-op for truncation/deletion |
| `DatabaseCleaner.cleaning { }` | `cleaners.rb:31-36`, `strategy.rb:27-34` | Nested `start; yield; ensure clean` across cleaners |
| `DatabaseCleaner.clean_with(:truncation, opts)` | `cleaners.rb:38-41`, `cleaner.rb:62-67` | One-shot clean with a throwaway strategy; current strategy untouched. Typical in `before(:suite)` |
| `DatabaseCleaner.allow_remote_database_url = true` / `allow_production` / `url_allowlist` | `core.rb:17-20` | Safeguard escape hatches |
| ENV `DATABASE_CLEANER_ALLOW_REMOTE_DATABASE_URL`, `DATABASE_CLEANER_ALLOW_PRODUCTION` | `safeguard.rb:67-71,91-94` | same |
| Default strategy (no adapter loaded) | `cleaner.rb:55-57` | `NullStrategy` — silent no-op |
| Unknown strategy | `cleaner.rb:144-150` | `UnknownStrategySpecified` listing available ones |
| Safeguard | `safeguard.rb:41-106` | Raises (as `Exception`, not `StandardError`!) if `DATABASE_URL` host ∉ `localhost`,`127.0.0.1`,`*.local`, or any of `ENV APP_ENV RACK_ENV RAILS_ENV` == `production` |

Safeguard gotcha for us: Docker/CI DB hosts (`postgres`, `db`) trip `RemoteDatabaseUrl`; real-world apps set `allow_remote_database_url = true` (§6). If we rewrite `DATABASE_URL` per worker, keep the host unchanged so we never newly trip it.

### 1.3 Strategies (ActiveRecord adapter)

| Strategy | Source | Mechanism | Options | Cost |
|---|---|---|---|---|
| `:transaction` | `active_record/transaction.rb:4-27` | `start`: lease connection, `connection.transaction {}` warm-up, `begin_transaction joinable: false`. `clean`: for **every connection in the pool** with `open_transactions > 0` → `rollback_transaction`; `release_connection` | none (`Strategy#initialize` raises on options, `strategy.rb:6-11`) | ~0 |
| `:truncation` | `active_record/truncation.rb:6-31` | `disable_referential_integrity { truncate_tables(...) }`; excludes `schema_migrations`, `ar_internal_metadata`, views | `only:`, `except:`, `pre_count:`, `cache_tables:` (default true), `reset_ids:`, `truncate_option:` (`:restrict` default; PG `:cascade`) | PG `TRUNCATE` of N tables: tens of ms, grows with table count, takes ACCESS EXCLUSIVE locks |
| `:deletion` | `active_record/deletion.rb:3-49` | `DELETE FROM t WHERE 1=1` per table; with `information_schema` only tables that have new rows | same as truncation | faster than truncation for small row counts / many tables (esp. MySQL) |

Sequel: `Transaction#start` runs `db.transaction(rollback: :always, savepoint: true, auto_savepoint: true) { Fiber.yield }` inside a `Fiber`, `clean` resumes it (`sequel/transaction.rb:6-21`). Fiber-bound → `start`/`clean` must run on the same thread; fine for fork and per-thread workers, breaks if a Capybara server thread writes outside that connection.
Redis: `Deletion#clean` → `flushdb` unless `only:`/`except:` (then `KEYS` + `DEL`); default connection `::Redis.new` (= `REDIS_URL` or `localhost:6379/0`) (`redis/deletion.rb:11-46`). **`flushdb` on a shared logical DB wipes every other worker's keys** → per-worker Redis DB is mandatory before we enable it.

### 1.4 Which strategy when

| Test kind | Server thread? | Strategy that works | Why |
|---|---|---|---|
| model / unit / service | no | `:transaction` (or Rails transactional tests) | single connection |
| request / integration (`rack-test`) | no — same thread | `:transaction` | app runs in-thread via rack-test |
| system / feature, JS driver, **Rails ≥ 5.1 transactional tests** | yes (Puma `Threads: '0:4'`, `capybara/registrations/servers.rb:40`) | Rails transactional tests | `ActiveRecord::TestFixtures` pins **one** connection for the pool: `pool.pin_connection!(lock_threads)` (`test_fixtures.rb:202,218`; `connection_pool.rb:368-381`) and `lock_threads` default true (`test_fixtures.rb:37`) → server threads share the test's connection + transaction |
| system / feature, JS driver, **DatabaseCleaner `:transaction`** | yes | ✗ usually | DC leases a per-thread connection (`transaction.rb:5-15`); Puma threads check out others → don't see uncommitted rows |
| system tests that spawn processes, use `after_commit`-sensitive code, multiple DBs not pinned, or `uses_transaction` | yes/other proc | `:truncation` / `:deletion` | data must actually be committed |

Real-world rule seen repeatedly: `:transaction` default, `:truncation` for `js:` / `ActionDispatch::IntegrationTest` / system classes (§6).

Pitfalls (fork/thread-relevant):

| Pitfall | Source | Effect under parallelism |
|---|---|---|
| `Transaction#clean` rolls back **every** pooled connection with open txns | `transaction.rb:18-26` | thread-pool workers sharing one AR pool → worker A's `clean` rolls back worker B's in-flight test. **Never share a pool across concurrent tests on JRuby/TruffleRuby** |
| `strategy=` per example builds a fresh `Truncation` | `cleaner.rb:42-53`; `truncation.rb:45-51` | table-list cache (`cache_tables`) lost each time → one `information_schema` query per test |
| DC `:transaction` + Rails `use_transactional_tests = true` (default) | `test_fixtures.rb:34,123-127` | double wrapping; harmless-ish but redundant. Second `strategy=`+`start` without `clean` leaks an open txn on the pooled connection (one app documented exactly this bug) |
| Safeguard raises `Exception` subclass | `safeguard.rb:3` | bypasses `rescue => e` in our worker loop; must rescue explicitly to report cleanly |
| `before(:suite) { clean_with(:truncation) }` | idiom | runs once **per worker** under us (each worker has its own suite boot) — fine only if each worker has its own DB |

### 1.5 Rails transactional tests interaction

| Setting | Default | Where | fast_rspec stance |
|---|---|---|---|
| `use_transactional_tests` (minitest) / `config.use_transactional_fixtures` (rspec-rails) | true | `test_fixtures.rb:34` | prefer it; don't add DC on top |
| `lock_threads` | true | `test_fixtures.rb:37` | required for system tests on shared connection |
| `self.use_transactional_tests = false` / `uses_transaction :name` | — | `test_fixtures.rb:123-127` | those tests need truncation → per-worker DB makes truncation safe |
| `parallelize(workers:)` → `ActiveRecord::TestDatabases` after-fork hook | `test_databases.rb:7-21` | sets `db_config._database = "#{database}_#{i}"` and `reconstruct_from_schema` per worker | fast_rspec replaces the fork; must reproduce the hook (or call it) |

### 1.6 Per-worker DB approaches

| Approach | How | Per-worker setup cost (rough, 50–300 tables) | Pros | Cons |
|---|---|---|---|---|
| Rails `_N` + schema load | `ActiveRecord::TestDatabases.create_and_load_schema(i, env_name:)` → `DatabaseTasks.reconstruct_from_schema` (`test_databases.rb:23-36`, `database_tasks.rb:412-428`): if `schema_up_to_date?` → **truncate only**; else purge + `load_schema`; on `NoDatabaseError` create + load | cold: 1–10 s (`schema.rb` load; `structure.sql` via `psql`/`mysql` shell-out is slower). warm (SHA matches): truncate ≈ 50–500 ms | upstream behavior, all adapters, multi-DB aware (`configs_for(include_hidden: true)`) | cold N× schema load in parallel hammers the DB server; DB names `x_test_0..N-1` (Rails 0-based) vs `parallel_tests` `x_test`, `x_test2`… (1-based, `TEST_ENV_NUMBER`) |
| Postgres template clone | load schema once into `x_test` (or `x_test_template`), then `CREATE DATABASE x_test_N TEMPLATE x_test` (AR supports `:template` option, `postgresql/schema_statements.rb:14-31`) | 100–800 ms each (file copy; PG15+ default `STRATEGY = WAL_LOG` is slower for big DBs, `STRATEGY = FILE_COPY` faster but forces checkpoint) | one schema load total; includes seeds/fixtures baked into template | **fails if any session is connected to the template** ("source database … is being accessed by other users") → parent must disconnect before cloning; clone serially or limited concurrency |
| MySQL | no template. Options: schema load per worker; `CREATE TABLE w.t LIKE base.t` per table; `mysqldump --no-data base \| mysql w` | `LIKE` loop: ~5–20 ms/table; dump/load: seconds | — | no atomic clone; foreign keys/triggers/views need dump path. Cache: skip if `ar_internal_metadata` schema SHA matches (Rails' own check) |
| SQLite | `cp test.sqlite3 test_N.sqlite3` (or `VACUUM INTO`) after parent has checkpointed WAL and **closed** the handle | ~ms (file size bound) | fastest; trivially per-thread too | parent's open handle must be closed pre-fork (real-world app hit corruption from an inherited handle); `:memory:` needs schema load per connection |
| Shared DB, per-test transaction (Ecto `SQL.Sandbox` style) | one DB; each test checks out a dedicated connection, wraps it in a txn, rolls back; other threads/processes *opt in* to that connection ("allowance"/shared mode) | 0 setup | no N databases; ideal for JRuby/TruffleRuby thread pool | Rails' `pin_connection!` is **per pool**, not per test (`connection_pool.rb:368`) → N concurrent tests in one process need N pools (one `ConnectionHandler` per worker thread) or an ownership layer we'd build; anything that commits (truncation tests, `uses_transaction`, DDL) breaks isolation; sequences shared |
| Per-thread DB (JRuby) | same as fork approaches but per worker thread; each thread gets its own `ConnectionHandler` via `ActiveSupport::IsolatedExecutionState` / `connected_to` | as above | full isolation, truncation-safe | must route every model call on that thread (incl. Capybara server threads) to the right handler |

Recommendation for fast_rspec: CRuby fork pool → PG template clone (fallback Rails `_N` schema path for MySQL; file copy for SQLite), reusing DBs across runs when the schema SHA matches. JRuby/TruffleRuby thread pool → per-thread DB (same naming), with sandbox-style shared DB as opt-in only.

## 2. shoulda-matchers / shoulda-context

### 2.1 shoulda-matchers

```ruby
Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec        # :minitest, :minitest_5, :minitest_4, :active_support_test_case, :test_unit
    with.library :rails               # or :active_record, :active_model, :action_controller, :routing
  end
end
```

| Fact | Source |
|---|---|
| `configure` yields a singleton `Configuration`; `integrate` **replaces** `@integrations` | `matchers/configuration.rb:4-6,26-28` |
| `Shoulda::Matchers.integrations` is `nil` until someone calls `integrate` → **our "already configured" probe** | `matchers/configuration.rb:9-11,23` |
| Neither framework nor library → `ConfigurationError` | `integrations/configuration.rb:31-44` |
| Apply = `test_framework.include(Independent)` + each library's `integrate_with` | `integrations/configuration.rb:46-49` |
| `:rails` = `active_model, active_record, action_controller, routing`; sets `assertion_exception_class = ActiveSupport::TestCase::Assertion` | `integrations/libraries/rails.rb:11-26` |
| RSpec include is `config.include(mod, type: :model)` etc. — model matchers only in `type: :model` unless user includes manually | `integrations/test_frameworks/rspec.rb:12-15`, `libraries/active_record.rb:12-15` |
| AR library also includes into `ActiveSupport::TestCase` regardless of framework | `libraries/active_record.rb:14` |
| Version floors: 8.0.1 → Ruby ≥ 3.3, activesupport ≥ 7.2; 7.0.1 → Ruby ≥ 3.2, activesupport ≥ 7.1 | gemspecs |

fast_rspec floor is CRuby 3.2 / Rails 7.1 → gemspec dep must be `shoulda-matchers >= 7.0, < 9` (8.x unresolvable on 3.2/7.1).
Calling `integrate` twice re-includes modules (idempotent at Ruby level) but the second call wins `@integrations`; if the user's file runs after ours, theirs wins naturally. We must run **after** user support files or not at all → install lazily (first example / `before(:suite)`), only if `integrations.nil?`.

### 2.2 shoulda-context (Minitest DSL)

| Fact | Source |
|---|---|
| Requiring it includes `Shoulda::Context::DSL` into **every** detected base: `ActiveSupport::TestCase`, `Minitest::Test`, `Test::Unit::TestCase` | `context.rb:15-17`, `context/test_framework_detection.rb:25-47`, `context/configuration.rb:7-11` |
| Detection result is **memoized at first call** → loading before `ActiveSupport::TestCase` is defined skips it | `test_framework_detection.rb:45-47` |
| `context "x" do; setup {}; should "y" do; end; should validate_presence_of(:a); end` → methods named `"test: X should y. "` (trailing space) | `context/dsl.rb:37,154,182-188`; `context/context.rb:47-80,108-126` |
| Duplicate name → raises `"'…' is defined more than once."` | `context/context.rb:110-116` |
| Railtie autoloads `test/shoulda_macros` + `vendor/{plugins,gems}/*` | `context/railtie.rb:3-12` |
| If `defined?(Rails)`: patches `Rails::TestUnitReporter#format_rerun_snippet` to call bare `executable` | `context.rb:10-13`, `context/rails_test_unit_reporter_patch.rb:4-18` |

Rails 8.1 incompatibility:

| Rails | `executable` defined as | Instance method? | Source |
|---|---|---|---|
| 8.0.5 | `class_attribute :executable, default: ENV.fetch("RAILS_TEST_EXECUTABLE", "bin/rails test")` | yes | `railties-8.0.5/lib/rails/test_unit/reporter.rb:9` |
| 8.1.x | `@executable = …; singleton_class.attr_accessor :executable`; upstream uses `self.class.executable` | **no** | `railties-8.1.4/lib/rails/test_unit/reporter.rb:10-11,91` |

→ shoulda-context 2.0.0's patched `format_rerun_snippet` raises `NameError: undefined local variable or method 'executable'` the first time a test **fails** (rerun line printed) — green runs never see it. Shim found verbatim in several apps (§6):

```ruby
if defined?(Rails::TestUnitReporter) && !Rails::TestUnitReporter.instance_methods.include?(:executable)
  Rails::TestUnitReporter.class_eval { private def executable = self.class.executable } # apps hardcode 'bin/rails test'
end
```

fast_rspec: ship this shim (delegating to `self.class.executable`, not hardcoded) guarded by the same `instance_methods` check; no-op once upstream fixes it. Also our own reporter prints rerun lines — must match `bin/rails test path:line` byte-for-byte, honoring `RAILS_TEST_EXECUTABLE`.

## 3. Capybara (+ cuprite, selenium)

### 3.1 Config surface

| Setting | Default | Source | Parallel concern |
|---|---|---|---|
| `Capybara.server = :puma, { Silent: true }` | `:default` → puma via `run_default_server` | `config.rb:59-67`; Rails sets puma Silent if still default `system_testing/server.rb:24-25` | each worker boots its own server thread |
| puma threads | `Threads: '0:4'`, `workers: 0` | `registrations/servers.rb:40` | ≥ 5 AR connections per worker unless pinned; N workers × pool size vs PG `max_connections` |
| `server_host` | `127.0.0.1` | `session/config.rb:75-77` | — |
| `server_port` | `nil` → `TCPServer.new(host, 0)` random | `server.rb:23,35-37,109-119` | random is per-worker safe; **user fixed port** (`9887`) collides → must offset by worker (real apps do `9887 + worker`) |
| `Capybara::Server.ports[port_key]` | class-level cache | `server.rb:15,36,74,101-102` | inherited across fork if server booted pre-fork → never boot server in parent |
| `app_host` | `nil` | `session/config.rb:84-91` | user setting `http://127.0.0.1:#{port}` must track the per-worker port |
| `default_driver` / `javascript_driver` | `:rack_test` / `:selenium` | `config.rb:74-84` | — |
| `register_driver(name) { \|app\| … }` | builtins `:rack_test`, `:selenium`, `:selenium_headless`, `:selenium_chrome(_headless)` | `capybara.rb:131`, `registrations/drivers.rb` | re-registering same name overwrites → our default must register only if absent (`Capybara.drivers.names.include?(:cuprite)` — `key?` goes through deprecated `method_missing`, `registration_container.rb:6,19-25`; see 3.2) |
| `save_path` | `nil` → `Dir.pwd` for `save_page`; Rails screenshots `Capybara.save_path.presence \|\| "tmp/screenshots"` | `capybara.rb:96`; `screenshot_helper.rb:90-95` | Rails names `"#{unique}_#{method_name}"` (`screenshot_helper.rb:67-78`) — `unique` counter is per-process → collisions only across workers on same test name; `rm_rf tmp/screenshots` in one worker's `before(:suite)` wipes others' → per-worker subdir |
| `default_max_wait_time` | 2 | `capybara.rb:80` | global, not per-session |
| `threadsafe` | false; can't change after a session exists | `config.rb:29-35` | JRuby thread pool needs `threadsafe = true` set **before** any session, else sessions/config are global and shared across worker threads |
| `reuse_server` | true | `server.rb:102` | per process; fine |

### 3.2 cuprite / ferrum

| Fact | Source |
|---|---|
| `require "capybara/cuprite"` registers `:cuprite` unconditionally → requiring it after user registration **overwrites theirs** | `cuprite-0.18/lib/capybara/cuprite.rb:14-16` |
| `Driver.new(app, options)`: `screen_size` (default maximize), `save_path` ← `Capybara.save_path`, `browser_options` merged with `"remote-allow-origins": "*"` | `cuprite/driver.rb:26-43` |
| Common opts in the wild: `window_size: [1440,900]`/`[1200,800]`, `browser_options: { "no-sandbox": nil, "disable-dev-shm-usage": nil, "disable-gpu": nil }`, `process_timeout: 10..15`, `timeout: 10..15`, `inspector: ENV["INSPECTOR"]`, `headless: !ENV["HEADLESS"].in?(%w[n 0 no false])`, `js_errors: true` variant | §6 |
| Ferrum port `"0"` (random CDP port), host `127.0.0.1`; `user-data-dir` = fresh `Dir.mktmpdir("ferrum_user_data_dir_")` | `ferrum/browser/options.rb:12-13,31-32`; `browser/process.rb:110`; `options/chrome.rb:106-109` |
| Timeouts from ENV: `FERRUM_DEFAULT_TIMEOUT` (5), `FERRUM_PROCESS_TIMEOUT` (10), `FERRUM_PROTOCOL_TIMEOUT` | `ferrum/browser/options.rb:16-18` |

→ cuprite is per-worker safe by default (random ports, own profile dir). Costs: one Chrome per worker (~150–300 MB RSS each, startup 0.5–2 s) → cap concurrent browser workers (e.g. `min(cores, mem/400MB)`) and set `--disable-dev-shm-usage` in containers (`/dev/shm` 64 MB default). Browser must start **lazily in the child**; a Chrome started pre-fork is shared by all children (CDP socket shared → forbidden by our fork rule).
Selenium: chromedriver also picks a free port by default; same memory caveat; selenium-manager download on first use races across workers → warm it in the parent (`Selenium::WebDriver::SeleniumManager.binary_paths`) before fork.

### 3.3 Server threads ↔ DB

| Setup | Works? |
|---|---|
| Rails ≥ 7.2 transactional tests + `lock_threads` (pinned connection) + puma in-process | yes — server threads use the pinned connection (serialized by `connection.lock`) |
| DatabaseCleaner `:transaction` + JS driver | no (see 1.4) |
| truncation + per-worker DB | yes, slower |
| JRuby thread pool | puma thread of worker *k* must resolve AR to worker *k*'s handler/DB — Capybara's server thread doesn't inherit `IsolatedExecutionState`; need a Rack middleware we inject that sets the worker context per request (`Capybara.app` wrap) |

## 4. SimpleCov

| API | Source | Notes |
|---|---|---|
| `SimpleCov.start(profile = nil) { … }` | `simplecov.rb:48-60` | `require "coverage"`; records `pid = Process.pid`; starts `Coverage` (lines / `enable_coverage :branch` / `primary_coverage`) |
| Must run **before app code loads** | `Coverage` only instruments files required after `start` | if `test_helper.rb` requires simplecov after `config/environment`, coverage is wrong; our preload must not load app code before user's `test_helper`/`spec_helper` top lines (or must start SimpleCov first when user has `.simplecov`) |
| `.simplecov` file | `load_global_config.rb` | auto-loaded by `require "simplecov"` — config may live there, not in helper |
| profiles `rails`, `test_frameworks`, `root_filter`, `hidden_filter`, `bundler_filter` | `profiles/*.rb` | `rails` = filters `config/`, `db/`, groups, `track_files "{app,lib}/**/*.rb"` |
| `command_name` | `configuration.rb:87-91`; guess `command_guesser.rb:24-28` | key in `.resultset.json`; **same name from two processes = last writer wins** |
| `at_fork { \|pid\| … }` | `configuration.rb:233-245` | default: `command_name "#{command_name} (subprocess: #{pid})"`, `print_error_status = false`, `SimpleFormatter`, `minimum_coverage 0`, `SimpleCov.start` |
| `enable_for_subprocesses true` | `configuration.rb:202-211`; `process.rb:3-18` | aliases `Process.fork` to call `at_fork` in child. Patches `Process.fork` only, not `Kernel#fork` / `Process._fork` |
| `use_merging` (default true), `merge_timeout` (default 600 s) | `configuration.rb:262-282` | results older than 600 s dropped at merge → suites > 10 min lose early workers' results unless raised |
| `.resultset.json` + `.resultset.json.lock` | `result_merger.rb:14-19,136-155` | file-locked writes; safe across processes |
| `SimpleCov.result` | `simplecov.rb:101-118` | stores own result then merges all within timeout |
| `SimpleCov.collate(files, profile, ignore_timeout: true)` | `simplecov.rb:86-96` | merge separate resultsets (CI shards) |
| at_exit guard `return if SimpleCov.pid != Process.pid` | `simplecov.rb:174-180` | **forked children never store** unless they re-`start` (at_fork) |
| Non-zero exit → stored result skipped | `simplecov.rb:186-193` | worker exiting non-zero (any at_exit) drops its coverage — seen in the wild |
| `parallel_tests` coupling | `simplecov.rb:268-280,425-436` | if `TEST_ENV_NUMBER` **and** `PARALLEL_TEST_GROUPS` set, SimpleCov `require "parallel_tests"` (warns if missing) and only `ParallelTests.last_process?` formats → **we must not set `PARALLEL_TEST_GROUPS`** (or must define a compatible `ParallelTests`) |

fast_rspec flow (fork pool): parent `SimpleCov.start` (user's) → fork → in child `SimpleCov.at_fork.call("worker-#{i}")` (respect user's `at_fork`) → child at end stores via `ResultMerger.store_result(SimpleCov.result)` explicitly, before any other at_exit can change status → parent `Process.waitall` then normal at_exit merge/format/`minimum_coverage` check. Thread pool (JRuby): `Coverage` is process-global → nothing to merge; JRuby needs `--debug`/`jruby.debug.fullTrace` for coverage at all.
Children inherit pre-fork counters → hit counts inflated for preload-executed lines; percent unaffected.

## 5. Sidekiq & Devise (supporting batteries seen alongside)

| Item | Source | Parallel note |
|---|---|---|
| `require "sidekiq/testing"` → `Sidekiq.testing!(:fake)`; **deprecated in 8.x** (warns, removed in 9) | `sidekiq-8.1.6/lib/sidekiq/testing.rb:1-3` | don't trigger the warning ourselves; use `Sidekiq.testing!` when available |
| `Sidekiq::Testing.fake!` / `inline!` / `disable!`, block form = thread-local, no nesting | `sidekiq/test_api.rb:14-52` | global mode is process-wide → shared across JRuby worker threads; block form is per-thread |
| `Sidekiq::Worker.clear_all` / `Sidekiq::Queues.clear_all` | `test_api.rb:202,302` | fake job arrays are process-global → per-thread pool needs per-thread clearing or serialization |
| `Devise::Test::IntegrationHelpers` includes `Warden::Test::Helpers`; `sign_in` | `devise-5.0.4/lib/devise/test/integration_helpers.rb:21-37` | `Warden.on_next_request` queue is a module ivar (`warden/test/warden_helpers.rb:26-39`) → process-global; thread pool: one worker's `login_as` can be consumed by another's request |
| `Warden.test_reset!` after each | idiom | — |

## 6. Real-world patterns (anonymized, ~25 Rails apps)

| Area | Pattern | Frequency |
|---|---|---|
| DC (rspec) | `before(:suite) { DatabaseCleaner.strategy = :transaction; DatabaseCleaner.clean_with(:truncation) }` + `around { DatabaseCleaner.cleaning { ex.run } }` | most rspec apps using DC |
| DC (rspec) | per-example switch: `strategy = (metadata[:js] \|\| metadata[:truncation]) ? :truncation : :transaction`; `start` / `ensure clean` | several |
| DC guard | `abort(...) unless current_database.include?('_test')` in `before(:suite)` | several — **our `_test_N` / template names must keep `_test` in the name** |
| DC safeguard | `DatabaseCleaner.allow_remote_database_url = true` | docker apps |
| DC (minitest) | `ActiveSupport::TestCase` `setup { strategy = :transaction; start }` / `teardown { clean }` **on top of** default transactional tests | many |
| DC (minitest) | `class_attribute :database_cleaner_strategy, default: :transaction`; `IntegrationTest`/system override `:truncation` | several; motivated by an open-txn leak from double `start` |
| DC + parallel | comment "PARALLEL_WORKERS=1 in CI to avoid DatabaseCleaner + fork flakiness" | several — the pain we fix |
| rspec-rails | `use_transactional_fixtures = true` (most) / `false` + DC (some) | — |
| shoulda | `test/support/shoulda.rb` with `test_framework :minitest; library :rails` + the `executable` shim (§2.2) | ~6 apps verbatim |
| shoulda (rspec) | manual `config.include Shoulda::Matchers::ActiveModel/ActiveRecord, type: :model` *plus* `configure` | some (redundant) |
| Capybara system | `ApplicationSystemTestCase`: `register_driver(:cuprite)` inline; `driven_by :cuprite`; `setup { Capybara.reset_sessions! }`; DC truncation | most minitest apps |
| Capybara server | `Capybara.server = :puma, { Silent: true }` or `:webrick, { Silent: true }` | both seen |
| Capybara parallel | `parallelize_setup { \|w\| Capybara.server_port = 9887 + w; Capybara.app_host = "http://127.0.0.1:#{port}"; re-register drivers; mkdir tmp/screenshots/worker-#{w} }` | several |
| Capybara (rspec) | `server_port = 9887 + ENV.fetch('TEST_ENV_NUMBER', 0).to_i`; `save_path = ENV.fetch('CAPYBARA_ARTIFACTS', './tmp/capybara')`; `rm_rf tmp/screenshots` only `unless ENV['TEST_ENV_NUMBER']` | one large app |
| Capybara (rspec) | `current_driver = metadata[:js] ? :cuprite : :rack_test`; overrides rspec-rails' default `driven_by(:selenium_chrome_headless)` | one |
| other per-worker state | `parallelize_setup` used for: Active Storage disk root `tmp/storage/w#{w}`, Redis key namespace `…:w#{w}`, Redis logical DB per worker (1..14, refuses to wrap), `clear_all_connections!` after fork for inherited SQLite handle | several — users rely on `parallelize_setup` receiving the worker index |
| SimpleCov | `if ENV['COVERAGE']` guard; `enable_coverage :branch`; `primary_coverage :line`; `add_filter '/test/'`; `track_files 'lib/**/*.rb'`; `minimum_coverage line: 90, branch: 90`; Cobertura formatter; `begin require 'simplecov' rescue LoadError` | gem repos |
| SimpleCov + fork | hand-rolled: `at_fork.call("worker-#{w}")` in after-fork hook, explicit `store_result` as newest at_exit, parent `Process.waitall`, post-merge check that every worker's entry exists and is within `merge_timeout`; parent-pid guards on inherited `after_run` hooks | one gem — exactly the logic we should own |
| Sidekiq | `require 'sidekiq/testing'; Sidekiq::Testing.inline!` (minitest, global) | most minitest apps |
| Sidekiq | `before(:suite) { Sidekiq::Testing.fake! }`, `before { Sidekiq::Worker.clear_all }`, `around(type: :job/:sidekiq) { inline! { run } }` via metadata | rspec apps |
| Sidekiq | Redis stubbed out entirely (`Sidekiq.define_singleton_method(:redis) { raise … }`) | one |
| Devise | minitest: `ActionDispatch::IntegrationTest` `include Devise::Test::IntegrationHelpers` (+ system case) | nearly all |
| Devise | rspec: `ControllerHelpers type: :controller`, `IntegrationHelpers type: :request/:system/:feature`, `Warden::Test::Helpers` + `after { Warden.test_reset! }`, `reload_routes_unless_loaded` in `before(:suite)` | rspec apps |

## 7. Zero-config defaults for fast_rspec

| Gem | Default we set (only if absent) | "User already configured" probe → skip | Per-worker isolation |
|---|---|---|---|
| database_cleaner (AR) | **nothing by default** when Rails transactional tests are on; if `use_transactional_tests`/`use_transactional_fixtures` is false: `strategy = :transaction` + `around { cleaning }`, `:truncation` for `type: :system/:feature`/`js:` and `IntegrationTest` subclasses with JS drivers; `clean_with(:deletion)` once per worker at boot | any user `before(:suite)`/`around`/`setup` that calls `DatabaseCleaner.*` (wrap `DatabaseCleaner.start/cleaning/strategy=` with a call-site flag set during user-support load); strategy state is **not** a signal (adapter auto-sets `:transaction`) | own DB per worker (template clone / `_N`) — mandatory before allowing truncation in parallel |
| database_cleaner (Sequel) | `DatabaseCleaner[:sequel].strategy = :transaction` already set by adapter; we add `around { cleaning }` only if no user hook | same | own DB per worker; `Sequel::DATABASES` reconnect after fork |
| database_cleaner (Redis) | none unless user loaded `database_cleaner-redis` | — | **required**: worker → own logical DB (`REDIS_URL=…/N`, N ∈ 1..15, refuse to wrap) or key prefix; never touch DB 0 |
| per-worker DB | PG: `CREATE DATABASE <db>_<i> TEMPLATE <db>` (parent disconnected); MySQL: Rails `create_and_load_schema`; SQLite: file copy; reuse when schema SHA unchanged; names keep `_test` | user `parallelize_setup`/`parallelize(workers:)` hooks still run with worker index; user-provided `database.yml` `<%= ENV['TEST_ENV_NUMBER'] %>` honored (set `TEST_ENV_NUMBER`, never `PARALLEL_TEST_GROUPS`) | — |
| shoulda-matchers | `integrate { test_framework (:rspec \| :minitest); library (:rails \| :active_record \| :active_model) }` | `Shoulda::Matchers.integrations` non-nil after user support files load | none |
| shoulda-context | none (requiring it is the config); install `executable` shim on Rails ≥ 8.1 | `Rails::TestUnitReporter.instance_methods.include?(:executable)` | none |
| capybara | `server = :puma, { Silent: true }` if still `:default`; `default_driver :rack_test` (upstream); `javascript_driver = :cuprite` if cuprite present else leave `:selenium`; per-worker `save_path` = `tmp/capybara/w<i>` if unset | `Capybara.server != Capybara.servers[:default]`; `@javascript_driver` set; `save_path` non-nil → shift into `…/w<i>` subdir only for our default | random port (default) ok; if user fixed `server_port`/`app_host`, offset by worker and log it at `FAST_RSPEC_DEBUG=1`; `threadsafe = true` before first session on thread pool |
| cuprite | register `:cuprite` with `window_size [1400,1400]`, `browser_options { "no-sandbox": nil (CI/root only), "disable-dev-shm-usage": nil }`, `process_timeout 15`, `headless: ENV["HEADLESS"] != "false"` | `Capybara.drivers.names.include?(:cuprite)` **before** `require "capybara/cuprite"` (it overwrites), then restore user's block | lazy browser per worker; cap browser-worker concurrency by RAM |
| selenium | none (mention only); pre-resolve selenium-manager in parent | user `driven_by :selenium…` | chromedriver per worker on free port |
| simplecov | none unless user requires simplecov / has `.simplecov`; then: `at_fork` per worker (`command_name "#{base} (worker-#{i})"`), explicit store, parent waits + merges, bump `merge_timeout` ≥ run length, verify all workers present | user `at_fork` block set → call theirs; user `enable_for_subprocesses` → don't double-hook | per-worker `command_name`; one shared `coverage/.resultset.json` (lock-protected) |
| sidekiq | `Sidekiq.testing!(:fake)` (8.x) / `Sidekiq::Testing.fake!` (≤7) + `clear_all` after each, only if `sidekiq/testing` mode never set by user | `Sidekiq::Testing.__global_test_mode` non-nil (no public predicate; `Sidekiq.testing!` at `sidekiq.rb:50`) | per-worker Redis DB if real Redis used |
| devise | include `Devise::Test::IntegrationHelpers` into `IntegrationTest`/`type: :request,:system,:feature`, `ControllerHelpers` into `type: :controller`; `Warden.test_reset!` after each | `ancestors.include?(Devise::Test::IntegrationHelpers)` on target class / RSpec `config.include` list | process-global Warden queue → per-thread guard on JRuby |
