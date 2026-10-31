# Target: factory_bot · factory_bot_rails · Faker · VCR · WebMock

As of 2026-10. Compat target for the factory/data/HTTP batteries. Sources read: factory_bot 6.6.0, factory_bot_rails 6.5.1, faker 3.8.0, vcr 6.4.0, webmock 3.34.0 (installed gems; paths below relative to each gem's `lib/`). Real-app patterns from ~34 support/helper files + 430 factory files under `~/workspace`, anonymized.

Contract: we `require` and drive these gems; never fork their DSL. Every row in "Zero-config defaults" must be skippable when the user already configured it.

---

## 1. factory_bot 6.6.0

### Public API (user code calls)

| Surface | Names | Source |
|---|---|---|
| Definition DSL | `FactoryBot.define`, `FactoryBot.modify`, `factory`, `sequence`, `trait`, `association`, `transient`, `after/before/callback`, `initialize_with`, `to_create`, `skip_create` | `factory_bot/syntax/default.rb:6,10,15,28,32`; `definition_proxy.rb` |
| Strategy methods | `build`, `create`, `build_stubbed`, `attributes_for`, `null` + `*_list`, `*_pair` — generated at load | `internal.rb:99-105`, `strategy_syntax_method_registrar.rb:24-55` (defined into `FactoryBot::Syntax::Methods` via `module_exec`) |
| Sequence helpers | `generate`, `generate_list`, `increment_sequence`; `FactoryBot.rewind_sequences`, `rewind_sequence`, `set_sequence` | `syntax/methods.rb:120,144,169`; `factory_bot.rb:107-113` |
| Mixin | `include FactoryBot::Syntax::Methods` (RSpec `config.include`, `ActiveSupport::TestCase`) | `syntax/methods.rb:32` |
| Discovery | `FactoryBot.definition_file_paths`, `FactoryBot.find_definitions`, `FactoryBot.reload` | `find_definitions.rb:7-24`, `reload.rb:2-6` |
| Lint | `FactoryBot.lint(factories = all, strategy: :create, traits: false, verbose: false)` | `factory_bot.rb:67-71`, `linter.rb:3` |
| Registry | `FactoryBot.factories`, `FactoryBot.register_strategy` | `factory_bot.rb:107-113` |

### Config API (process globals)

| Setting | Default | Source |
|---|---|---|
| `FactoryBot.use_parent_strategy` | `true` | `factory_bot.rb:51-52` |
| `FactoryBot.automatically_define_enum_traits` | `true` | `factory_bot.rb:54-55` |
| `FactoryBot.sequence_setting_timeout` | `3` (s, `set_sequence` seek) | `factory_bot.rb:57-58`, `sequence.rb:119` |
| `FactoryBot.build_stubbed_starting_id=` | stub ids start `1001` (`@@next_id = 1000`) | `factory_bot.rb:76-78`, `strategy/stub.rb:4,50-56` |
| `FactoryBot.definition_file_paths` | `%w[factories test/factories spec/factories]` (relative to **cwd**) | `find_definitions.rb:10` |

### Load-time side effects (`require "factory_bot"`)

- Requires `active_support`, `active_support/notifications`, `active_support/deprecation` (`factory_bot.rb:1-6`) — loads AS even in plain-Ruby suites.
- Registers default strategies → defines `build/create/...` on `Syntax::Methods` (`factory_bot.rb:117`).
- Does **not** load definitions. Plain Ruby: user must call `FactoryBot.find_definitions`. Rails: factory_bot_rails does it.

### Discovery

| Fact | Detail | Source |
|---|---|---|
| Paths | each entry → `load "#{path}.rb"` if exists, then `Dir["#{path}/**/*.rb"].sort.each { load }` | `find_definitions.rb:12-24` |
| `load`, not `require` | calling twice re-executes `FactoryBot.define` | — |
| Duplicates raise | `DuplicateDefinitionError "Factory already registered: x"` — factories/sequences/traits registries wrapped in `DisallowsDuplicatesRegistry` | `configuration.rb:15`, `decorator/disallows_duplicates_registry.rb:4-10` |
| → idempotency rule | **Never call `find_definitions` if `FactoryBot.factories.any?`**; or call `FactoryBot.reload` (resets whole config, `internal.rb:23-25`) — only safe before any user `FactoryBot.modify`/custom strategy | — |
| Compile is lazy | `Factory#compile`/`Definition#compile` memoized on first run (`@compiled`), resolves model constant, expands enum traits, fires `factory_bot.compile_factory` | `factory.rb:91-97`, `definition.rb:50-66` |

### factory_bot_rails 6.5.1 railtie (`factory_bot_rails/railtie.rb`)

| Step | Behavior | Line |
|---|---|---|
| config | `config.factory_bot.definition_file_paths` (default = FactoryBot's), `.validator`, `.file_fixture_support = true` | 12-15 |
| initializer `factory_bot.set_fixture_replacement` | generators: `fixture_replacement :factory_bot` (rspec vs non-rspec dir), off if `generators.rails[:factory_bot] == false` | 17-19; `generator.rb:34-58` |
| initializer `factory_bot.set_factory_paths` | rewrites paths to `Rails.root.join(path)` (cwd-independent) | 21-23, 49-53 |
| `after_initialize` #1 | `SyntaxRunner.include FileFixtureSupport`; `on_load(:active_support_test_case) { setup { SyntaxRunner.file_fixture_support = self } }`; if `RSpec.configure` defined → `config.before { ... = self }` | 25-39 |
| `after_initialize` #2 | `FactoryBot.find_definitions`; `Reloader` (file watcher → `FactoryBot.reload` on `to_prepare`); validator subscribes to `factory_bot.compile_factory` | 41-45; `reloader.rb:39-65`; `factory_validator.rb:11-13` |

Notes:
- Railtie does **not** include `Syntax::Methods` anywhere. Every app does it by hand (see §1 real apps).
- `require "factory_bot_rails"` must happen **before** `Rails.application.initialize!`. As a *transitive* dep of `fast_rspec` it is not hit by `Bundler.require` → `lib/fast_rspec.rb` must `require "factory_bot_rails"` when `defined?(Rails::Railtie)`.
- Users who had `factory_bot_rails` in `group :development, :test` lose generator fixture-replacement in dev once only `fast_rspec` (test group) remains. Doc it in migration guide.
- `file_fixture_support` is a `cattr_accessor` on `SyntaxRunner` (`file_fixture_support.rb:16-19`): one slot per process, overwritten in each test's `setup`. Thread pool → races (last thread's test instance wins). Harmless when `file_fixture_path` identical; wrong when per-class `file_fixture_path` differs.

### Process-global / thread-unsafe state

| State | Where | Fork (CRuby) | Threads (JRuby/Truffle) |
|---|---|---|---|
| Global sequences `n` | `Sequence#@value` (`EnumeratorAdapter`), `next` = `peek` then `ensure increment` | each child inherits parent counter → **every worker emits the same values** (`user1@`, `user2@`, …) | `peek`/`next` not atomic (`sequence.rb:37-47,89-95`) → duplicate or skipped values |
| Inline (factory-scoped) sequences | `Internal.inline_sequences` | same as above | same |
| Lazy initial value (`sequence(:x, -> { ... })`) | evaluated on first `peek` (`sequence.rb:191-194`) | evaluated per worker if not touched pre-fork; fixed in parent if lint/`generate` ran pre-fork | race on first eval |
| `build_stubbed` ids | `Strategy::Stub @@next_id += 1` (`strategy/stub.rb:4,54`) | same ids per worker (fine: never persisted) | `+=` not atomic → duplicate ids (rare, only matters if test compares stub ids) |
| Compiled factories | `@compiled` memo | compile pre-fork = CoW shared, saves per-worker compile | double-compile race; `define_trait` mutates traits |
| `SyntaxRunner.file_fixture_support` | cattr | per-process, fine | race (above) |
| `ActiveSupport::Notifications` subscribers | `factory_bot.run_factory`, `.compile_factory` (`factory_runner.rb:28-30`, `definition.rb:65`) | fine | fine (AS::N is thread-safe) |

### Sequences across workers — the unique-index question

- Per-worker DB (our default isolation, and Rails `parallelize` today): identical sequence values in different workers **do not collide** — separate databases. Rails `parallelize(workers: :number_of_processors)` already forks with identical counters; 9+ real apps run green this way.
- They **do** collide on anything shared across workers and keyed by sequence/ID: a shared DB (no per-worker isolation), Redis without per-worker DB/namespace, Elasticsearch/OpenSearch indexes, ActiveStorage `Disk` root / S3/minio bucket (one real app hit exactly this: blob keys derived from record ids, all workers shared one disk root → fixed with per-worker root in `parallelize_setup`), tmp file paths, external sandboxes.
- Offsetting sequences per worker (`set_sequence`/rewrite `@value`) is **not drop-in**:
  - breaks exact-value assertions (`expect(user.email).to eq "user1@example.com"` after `rewind_sequences`), snapshot/golden files;
  - breaks VCR cassette matching when the sequence value lands in a recorded URI/body (`match_requests_on: [:method, :uri, :body]`) → `UnhandledHTTPRequestError` only in workers ≠ 0;
  - non-Integer sequences (`"a"`, enumerators, `%w[...].cycle`) can't be offset directly (`sequence.rb:73-81,142-146` → seek with timeout).
- Decision for battery: **no offset when per-worker DB isolation is active** (default). Offset only in shared-DB mode, Integer-valued sequences only, via public `FactoryBot.set_sequence`-equivalent on each registered sequence, `worker_index * 1_000_000`. Conflicts with `docs/idea/06-batteries.md` row "sequences offset per worker" → update that doc.
- Thread pool: wrap `Sequence#next` + `Stub#next_id` in a mutex (prepend, parity-tested) — or per-thread sequence clones. Mutex is simpler and keeps uniqueness within the process.

### `FactoryBot.lint`

- Runs each factory (and traits with `traits: true`) inside `ActiveRecord::Base.transaction(joinable: false) { ...; raise ActiveRecord::Rollback }` (`linter.rb:110-117`) — DB-clean but **consumes sequences** and evaluates lazy initial values.
- Real apps: lint as a normal test (`test/factories_lint_test.rb`, one test per factory) or in a rake task; never in helpers. Don't auto-run lint. If we ever offer `fast_rspec lint`, run it in one worker, not pre-fork.

### Real-app patterns (anonymized)

| Pattern | Frequency |
|---|---|
| `include FactoryBot::Syntax::Methods` in `ActiveSupport::TestCase` (test_helper) | ~10 apps |
| `config.include FactoryBot::Syntax::Methods` in `rails_helper.rb` / `spec/support/factory_bot.rb` | ~4 apps |
| Explicit `FactoryBot.create(...)` in support helpers (no mixin) | common in helpers |
| `definition_file_paths` override | 0 (one comment only); all use `spec/factories` or `test/factories` |
| `find_definitions` by hand | 0 (all Rails + factory_bot_rails) |
| `FactoryBot.lint` | 1 app, as a test |
| Sequences in factories | 141/430 factory files, 178 uses; top: `:name`, `:slug`, `:email`, `:key`, `:title`, external ids |
| `Faker::` in factories | 101/430 files; `.unique.` 9 uses (email, username, slug, word) |
| `parallelize(workers: :number_of_processors)` with factories | ~9 minitest apps — proof identical per-worker sequences are fine with per-worker DB |

---

## 2. Faker 3.8.0

### Public API / config

| Surface | Names | Source |
|---|---|---|
| Generators | `Faker::<Category>.<method>` (`Faker::Name.name`, `Faker::Internet.email`, …), ~300 classes | `faker/**/*.rb` |
| Uniqueness | `Faker::X.unique.method`, `Faker::X.unique.clear`, `Faker::UniqueGenerator.clear`, `.unique.exclude(name, args, values)` | `faker.rb:247-249`; `helpers/unique_generator.rb:40-58` |
| Locale | `Faker::Config.locale=`, `.default_locale=`, `Faker::Base.with_locale` | `faker.rb:19-31,193` |
| Randomness | `Faker::Config.random=` (any `Random`-like), default `Random` (process `Kernel` PRNG) | `faker.rb:34-40` |
| Lazy load | `Faker::Config.lazy_loading=` / `ENV["FAKER_LAZY_LOAD"]` | `faker.rb:42-52,291-330` |

All randomness funnels through `Faker::Config.random` (`sample`, `shuffle`, `rand` at `faker.rb:251-276`) — so seeding `Faker::Config.random` or `Kernel.srand` determines output.

### Load-time side effects

- `I18n.load_path += 318 locale YAMLs (5.2 MB)` (`faker.rb:12`). Not parsed yet.
- Eager mode (default): requires every generator file (`faker.rb:327-330`). `require "faker"` ≈ 0.5 s.
- **First generator call parses all locale YAML: measured 1.17 s** (Ruby 3.4.7). If that first call happens post-fork it's paid once **per worker** and the parsed hash is not CoW-shared.
- → Warm in parent pre-fork: `I18n.backend.eager_load!` (i18n ≥ 1.x `backend/simple.rb:64`) — loads translations without consuming the PRNG. Don't warm by calling a Faker method (would shift the random stream vs stock).

### Global / thread-local state — **all of it is `Thread.current[...]` (fiber-local)**

| Key | Meaning | Source | Fork | Threads |
|---|---|---|---|---|
| `:faker_config_random` | user-set PRNG | `faker.rb:34-40` | inherited (same state in every child) | **not visible in worker threads** → threads fall back to shared `Random` → nondeterministic |
| `:faker_config_locale` | user-set locale | `faker.rb:21-31` | inherited | **lost in worker threads** (e.g. app sets `Faker::Config.locale = :es` in initializer → threads generate `:en`) |
| `:faker_lazy_loading` | lazy flag | `faker.rb:46-51` | — | lost; plus `const_missing` + `require` race (`faker.rb:304-321`) |
| `:faker_unique_generator_previous_results` | seen values per generator | `unique_generator.rb:35-38` | copied at fork; each worker then diverges independently | each thread starts empty |
| `:faker_unique_generator_marked_unique` | generators to clear | `unique_generator.rb:44-51` | same | same |
| `Faker::Base.@unique` | memoized `UniqueGenerator` per class | `faker.rb:248` | fine | `||=` race (benign) |

Implications:
- `Kernel.srand config.seed` in `spec_helper` (rspec default template; 7 real apps) + fork → **every worker produces the identical Faker stream**. Per-worker DB makes this harmless; shared resources (above) make it a collision.
- `Faker::X.unique` guarantees uniqueness only within one thread of one process. Across workers it guarantees nothing — fine with per-worker DB.
- Uniqueness exhaustion: stock never clears unless the user does; `RetryLimitExceeded` after 10 000 tries (`unique_generator.rb:13-22`). Fewer tests per worker → less exhaustion than serial. Auto-`clear` per test (plan in `06-batteries.md`) **diverges from stock**: values recur across tests → collisions with `before(:all)`/`before_all`/seed rows that survive the per-test transaction. Default: don't clear; offer opt-in.
- Determinism with work-stealing: a test's Faker values depend on how many Faker calls ran earlier in that worker → same `--seed` ≠ same values unless reseeded per example/file.

### Fork/thread rules for the battery

| Platform | Do |
|---|---|
| CRuby fork | pre-fork: `I18n.backend.eager_load!`. Post-fork: if user did not set `Faker::Config.random`, set `Faker::Config.random = Random.new(derive(seed, worker_index))`. Optional (`FAST_RSPEC_FAKER_RESEED=example`): reseed per example from `(seed, example id)` for scheduling-independent repro. |
| Threads | on each worker thread start: copy `:faker_config_random` (fresh `Random.new(derive(...))`, never share a `Random` across threads), `:faker_config_locale`, `:faker_lazy_loading` from main thread; force eager load (`FAKER_LAZY_LOAD` off) |
| Fibers | `Thread.current[]` is fiber-local → async/fiber-scheduler tests lose Faker config; out of scope, document |

---

## 3. VCR 6.4.0

### Public API

| Surface | Names | Source |
|---|---|---|
| Cassettes | `VCR.use_cassette(name, opts) { }` (block required), `VCR.use_cassettes([...])`, `VCR.insert_cassette`, `VCR.eject_cassette(skip_no_unused_interactions_assertion:)`, `VCR.current_cassette` | `vcr.rb:48-50,132-146,159-165,184-205,213` |
| On/off | `VCR.turned_off { }`, `VCR.turn_off!(ignore_cassettes:)`, `VCR.turn_on!`, `VCR.turned_on?` | `vcr.rb:270-342` |
| Config | `VCR.configure { |c| }`, `VCR.configuration` | `vcr.rb:234-241` |
| RSpec | `c.configure_rspec_metadata!` → `:vcr`, `vcr: true`, `vcr: "name"`, `vcr: { cassette_name:, record:, ... }`; name = group descriptions joined by `/` | `configuration.rb:417-422`; `test_frameworks/rspec.rb:8-59` |
| Cucumber | `VCR.cucumber_tags` | `vcr.rb:256` |
| Minitest | **no adapter in VCR**. Real apps: `VCR.use_cassette` blocks or a tiny helper (`def vcr_cassette(name, **, &) = VCR.use_cassette(name, **, &)`); 3rd-party `minitest-vcr` exists | — |

### Config API (`VCR::Configuration`)

| Option | Default | Notes / source |
|---|---|---|
| `cassette_library_dir=` | `nil` | sets `FileSystem.storage_location`; `mkdir_p` + `Dir.chdir(dir) { Dir.pwd }` (`configuration.rb:29-31`, `persisters/file_system.rb:14-17,47-49`) — `Dir.chdir` block is process-global; call only on main thread pre-fork |
| `hook_into :webmock / :faraday / :typhoeus / :excon` | none | requires `vcr/library_hooks/<x>` (`configuration.rb:64-67,516-522`) |
| `default_cassette_options=` | `record: :once, record_on_error: true, match_requests_on: [:method, :uri], allow_unused_http_interactions: true, serialize_with: :yaml, persist_with: :file_system` | merged into defaults (`configuration.rb:48`, `492-501`) |
| `allow_http_connections_when_no_cassette=` | `nil` (false) | `configuration.rb:128-131` |
| `ignore_localhost=` | off | adds `localhost 127.0.0.1 0.0.0.0 host.docker.internal` (`request_ignorer.rb:11,20-25`) — **no `::1`/`[::1]`** (WebMock's list has `[::1]`, not `host.docker.internal`) |
| `ignore_hosts`, `unignore_hosts`, `ignore_request { |req| }` | — | `configuration.rb:74-111` |
| `filter_sensitive_data(placeholder, tag = nil) { |interaction| }` | — | alias of `define_cassette_placeholder`: `before_record` filter + `before_playback` unfilter (`configuration.rb:224-237`) |
| `before_record`, `before_playback`, `before_http_request`, `after_http_request`, `around_http_request` | — | `configuration.rb:296-394` |
| `register_request_matcher`, `preserve_exact_body_bytes`, `debug_logger=`, `query_parser`, `uri_parser` | — | — |

Record modes (`cassette.rb:12-17,140-145,258-268`):

| Mode | Plays back | Records | Writes file when |
|---|---|---|---|
| `:once` (default) | yes | only if cassette file absent/empty | file missing at insert |
| `:new_episodes` | yes | unmatched requests | any new interaction → old + new rewritten |
| `:all` | no | everything | always; replaces matching old |
| `:none` | yes | never (unmatched → error) | never |
| `re_record_interval:` | — | upgrades mode to `:all` once stale (`cassette.rb:201,237-247`) | — |

### Load-time side effects

- `require "vcr"`: defines `VCR::CassetteMutex = Mutex.new`, **`VCR::MainThread = Thread.current`** (`vcr.rb:26-30`). Nothing hooked yet.
- `hook_into :webmock` (`library_hooks/webmock.rb`): `WebMock.globally_stub_request` (every request routed through VCR, `:134-136`); two `WebMock.after_request` callbacks (`:138-154`); **monkeypatches `WebMock.net_connect_allowed?` to return `true` whenever VCR is on** (`:164-170`).

### Interaction with WebMock (critical for "always on" defaults)

| Effect of `hook_into :webmock` | Consequence |
|---|---|
| `net_connect_allowed?` ≡ `true` while VCR on | user's `WebMock.disable_net_connect!(allow: [...])` allow-list is **ignored**; VCR alone decides |
| No cassette, `allow_http_connections_when_no_cassette` false | request → `VCR::Errors::UnhandledHTTPRequestError` (`request_handler.rb:33-41`, `vcr.rb:351-354`), **not** `WebMock::NetConnectNotAllowedError` |
| Error class hierarchy differs | `WebMock::NetConnectNotAllowedError < Exception` (`webmock/errors.rb:5`) escapes `rescue => e`; `VCR::Errors::Error < StandardError` (`vcr/errors.rb:5`) is **swallowed** by app code that rescues `StandardError` (HTTP wrappers, jobs with retry) → tests that passed (failing loudly) now pass silently or vice-versa |
| `stub_request` still wins | `externally_stubbed?` checked first (`request_handler.rb:35`) |

→ Turning VCR on for a suite that never used it is **not drop-in**. VCR battery must only activate when the app already uses VCR (cassette dir exists, or `vcr` was in the pre-migration Gemfile/lock, or `:vcr` metadata / `VCR.` referenced in spec/test). Conflicts with `06-batteries.md` ("vcr: always") → update.
→ When both are active and the user passed `WebMock.disable_net_connect!(allow: X)` but did not configure VCR ignores, mirror `X` into `VCR.configure { |c| c.ignore_hosts(*X) }` (strings only; regex/proc → `ignore_request`).

### Thread/fork state

| State | Fork | Threads |
|---|---|---|
| `@context` hash keyed by Thread/Fiber (`vcr.rb:413-470`) | fine iff fork is called from the thread that required VCR (child's main thread = forking thread). Forking from a non-main pool thread → `MainThread` mismatch → child's context is a *linked* copy | each new thread gets `dup_context(@context[MainThread])` with `linked_context` → **sees cassettes inserted on main thread**; own cassettes are private. OK as long as main thread inserts none |
| `CassetteMutex` | per process | guards `record_http_interaction` only (`cassette.rb:116-121`) |
| `VCR.configuration` hooks/ignores | global, CoW | shared; configure pre-start only |
| `turned_off`/`ignore_cassettes` | per context | per thread |

### Cassette file concurrency (N workers, same cassette)

Persister is plain `File.binread` / `File.binwrite` (`persisters/file_system.rb:23-38`): no lock, no tmp+rename. Write happens on eject (`cassette.rb:308-314`).

| Scenario | Stock serial | N workers |
|---|---|---|
| Playback only (file exists, `:once`/`:none`) | fine | fine (read-only) |
| Shared cassette name (`vcr: { cassette_name: "stripe/customer" }` in several files), file missing, `:once` | first test records, later tests play back | several workers see "absent" → all record real HTTP → last `binwrite` wins, others' interactions lost; next run may miss requests |
| `:new_episodes` | append | read-old/append/write lost update |
| Concurrent writer + reader | n/a | reader can see truncated file mid-`binwrite` → `Psych::SyntaxError` |
| Auto-named via metadata (unique per example) | — | no collision (names include full group path) |

Battery mitigation (only when we own the persister, i.e. `persist_with: :file_system` and no custom persister registered): wrap `VCR.cassette_persisters[:file_system]` so `[]=` does `flock(LOCK_EX)` on `"#{path}.lock"` → re-read → for `:once`, skip write if file appeared since insert (warn) → write tmp + `File.rename` (atomic). Readers unaffected. Parity test: serial output byte-identical.

### Real-app patterns (anonymized; 8 VCR configs)

| Setting | Seen |
|---|---|
| `hook_into :webmock` | 8/8 |
| `ignore_localhost = true` | 8/8 |
| `cassette_library_dir` | `test/cassettes` (5, `Rails.root.join(...)`), `spec/cassettes` (2), `spec/fixtures/vcr` (1) |
| `configure_rspec_metadata!` | rspec apps |
| `default_cassette_options` | `record: :once` (1), `record: :new_episodes` (1); rest default |
| `filter_sensitive_data` | 3 (API keys, tokens; one iterates credentials list); one uses `before_record` to scrub query/JSON tokens |
| `allow_http_connections_when_no_cassette = false` | explicit in 1 (= default) |
| extra `ignore_hosts` | Selenium grid host from ENV, docker service names (`proxy`) |
| `:disable_vcr` metadata → `VCR.turned_off { WebMock.allow_net_connect!; ...; disable_net_connect!(allow_localhost: true) }` | 1 |
| manual registry resets around VCR (`before { RequestRegistry.reset! }`, `after { StubRegistry.reset! }`) | 1 — works around hook ordering; must keep working |
| `debug_logger = $stdout` toggled by ENV | 1 |

---

## 4. WebMock 3.34.0

### Public API

| Surface | Names | Source |
|---|---|---|
| Stubs | `stub_request(method, uri)`, `.with(...)`, `.to_return/.to_raise/.to_timeout/.to_rack`, `remove_request_stub`, `hash_including`, `hash_excluding` | `webmock/api.rb:7-67` |
| Assertions | `assert_requested`, `assert_not_requested`, `a_request(...)`, RSpec `have_requested`/`have_been_requested`/`have_been_made` | `api.rb:14-31`; `rspec/matchers` |
| Global | `WebMock.enable!(except:)`, `.disable!(except:)`, `.allow_net_connect!(net_http_connect_on_start:)`, `.disable_net_connect!(allow_localhost:, allow:, net_http_connect_on_start:)`, `.reset!`, `.reset_executed_requests!`, `.after_request`, `.globally_stub_request`, `.show_body_diff!/.hide_body_diff!`, `.hide_stubbing_instructions!` | `webmock/webmock.rb:30-176` |
| `allow:` accepts | String host / `host:port` / `http(s)://` URL prefix, Regexp, Proc (`call(uri)`), Array of these | `webmock.rb:85-101` |

### Config (singleton `WebMock::Config`, process-global)

`allow_net_connect` (nil ⇒ blocked), `allow_localhost`, `allow`, `net_http_connect_on_start`, `show_stubbing_instructions` (true), `show_body_diff` (true) — `config.rb:5-18`. Localhost = `localhost 127.0.0.1 0.0.0.0 [::1]` (`util/uri.rb:71-73`).

`disable_net_connect!` **replaces** all three fields (`webmock.rb:51-56`): a second call without `allow:` wipes the first call's allow-list.

### Load-time side effects / adapters

| Require | Effect | Source |
|---|---|---|
| `webmock` | loads adapters (Net::HTTP, http.rb, httpclient, patron, curb, em-http, typhoeus, excon, manticore, async-http); **does not enable** — `Net::HTTP` untouched | `webmock.rb:50-63` |
| `webmock/rspec` | `config.include WebMock::API, WebMock::Matchers`; `before(:suite) { WebMock.enable! }`; `after(:suite) { WebMock.disable! }`; `around(:each) { run; WebMock.reset! }`; assertion error = `RSpec::Expectations::ExpectationNotMetError` | `rspec.rb:25-44` |
| `webmock/minitest` | `WebMock.enable!` **at require**; includes `WebMock::API` into `Minitest::Test`; aliases `teardown` → `teardown_without_webmock; WebMock.reset!`; assertion error = `Minitest::Assertion` | `minitest.rb:15-43` |
| `webmock/test_unit`, `webmock/cucumber` | analogous | — |
| `enable!` | swaps `Net::HTTP` constant for `@webMockNetHTTP` subclass (`http_lib_adapters/net_http.rb:25-41`) | — |

Gotchas:
- `WebMock.reset!` = stubs + request registry only (`webmock.rb:149-152`). **Config is never reset**: a test calling `WebMock.allow_net_connect!` leaks into every later test in that worker → with work-stealing, which tests are affected varies per run. Real apps restore in `ensure`; battery should snapshot `Config` and restore after each test (cheap, 4 ivars) — but only if `webmock` is ours, to stay drop-in.
- Minitest `teardown` alias: a test class defining `def teardown` without `super` skips `WebMock.reset!` (stock behavior; we keep it).
- `NetConnectNotAllowedError < Exception` — not caught by `rescue => e`; intentional, keep.
- `Net::HTTP` swap happens at `enable!`: libraries that captured `Net::HTTP` before enable (constant cached in a client) bypass WebMock. Enable pre-fork, early.

### Thread/fork state

| State | Fork | Threads |
|---|---|---|
| `StubRegistry.instance.request_stubs` (singleton, `stub_registry.rb:6,18-20`) | per child, fine | **shared across threads**: thread A's `stub_request` answers thread B; A's `reset!` wipes B's stubs mid-test |
| `RequestRegistry` (executed requests) | fine | shared → `assert_requested` counts other threads' requests |
| `Config` | fine | shared → `allow_net_connect!` in one test opens network for all |
| global stubs (VCR's) | fine | VCR handler is context-aware (per thread) — OK |

→ Thread pool needs a parity-tested patch making `StubRegistry#request_stubs`, `RequestRegistry#requested_signatures`, and a per-thread `Config` overlay thread-local (inherit globals set on main thread before start). Without it, any suite using `stub_request` is unsafe on JRuby/TruffleRuby. Alternative: schedule files that touch WebMock onto one thread — loses parallelism, last resort.

### Capybara / browser localhost needs

| Driver | Ruby-side HTTP that WebMock sees | Needs |
|---|---|---|
| rack_test | none (in-process Rack) | — |
| Capybara server boot | `Capybara::Server#responsive?` → `Net::HTTP` GET `/__identify__` on `Capybara.server_host` (default `127.0.0.1`) | localhost; if `server_host` is a container IP/hostname (`IPSocket.getaddress(Socket.gethostname)` pattern for remote browsers) → that host |
| selenium-webdriver (local) | `Net::HTTP` to chromedriver/geckodriver on `127.0.0.1:<port>` | localhost |
| selenium remote grid | `Net::HTTP` to `SELENIUM_REMOTE_URL` / grid host | that host (real app: `ignore_hosts ENV['SELENIUM_GRID_HOST']` + WebMock `allow:`) |
| cuprite/ferrum | `Net::HTTP` GET `http://host:port/json/version`, then raw `TCPSocket` websocket (not intercepted) | browser host (`localhost` or `BROWSER_URL`/`CHROME_URL` host) |
| Browser → app traffic | not Ruby, not intercepted | — |

Both libraries treat `0.0.0.0` as localhost; only WebMock has `[::1]`, only VCR has `host.docker.internal`.

### Real-app patterns (anonymized)

| Pattern | Seen |
|---|---|
| `require "webmock/minitest"` + `WebMock.disable_net_connect!(allow_localhost: true)` in test_helper | ~5 minitest apps (identical lines) |
| `require "webmock/rspec"` in `spec/support/vcr.rb` | rspec apps |
| `WebMock.disable_net_connect!(allow_localhost: true, allow: [grid/chromedriver hosts])` | 1 (selenium) |
| `include WebMock::API` explicitly in `ActiveSupport::TestCase` | 1 (redundant with minitest adapter) |
| `WebMock.stub_request(...)` inside helper modules (JWKS/userinfo/IdP endpoints) | 3 |
| Extra DNS/socket guard raising on real resolves | 1 |
| HTTP clients not covered by WebMock (httpx) → adapter required process-wide, cannot be unloaded | 1 — WebMock adapters are load-order dependent; never `require` optional adapters on users' behalf |

---

## 5. Zero-config defaults for fast_rspec

Install timing: mixins at `require "fast_rspec"` (early, so user modules included later win method lookup — e.g. a user helper named `create`/`build`); config decisions **after** user helpers + `spec/support`/`test/support` load and **before** fork/thread start; per-worker steps post-fork / on thread start.

| Gem | Default we set | Skip if user already did (detection) | Per-worker isolation |
|---|---|---|---|
| factory_bot (plain Ruby) | `FactoryBot.find_definitions` when any of `factories{,.rb}`, `test/factories`, `spec/factories` exists under project root (`definition_file_paths` made absolute to root, not cwd) | `FactoryBot.factories.any?` (already loaded) — never call twice (`DuplicateDefinitionError`) | none by default (per-worker DB). Shared-DB mode: Integer sequences `+ worker_index * 1_000_000`. Threads: mutex around `Sequence#next`, `Stub#next_id` |
| factory_bot_rails | `require "factory_bot_rails"` from `lib/fast_rspec.rb` when `defined?(Rails::Railtie)` (Bundler won't require a transitive dep) | `defined?(FactoryBotRails::Railtie)` | pre-fork: optionally compile all factories (`FactoryBot.factories.each(&:compile)`) for CoW — measure first; validators still fire |
| `Syntax::Methods` | RSpec: `config.include FactoryBot::Syntax::Methods`; Minitest: include into `Minitest::Test` → covers `ActiveSupport::TestCase`, `ActionDispatch::IntegrationTest` | Ruby `include` is idempotent; still check `klass.include?(FactoryBot::Syntax::Methods)` to log accurately | — |
| Faker | pre-fork `I18n.backend.eager_load!` (saves ~1.2 s CPU per worker); force eager generator load | user set `Faker::Config.random` (`Thread.current[:faker_config_random]` non-nil on main thread after helpers) → leave PRNG alone; `ENV["FAKER_LAZY_LOAD"]` set → respect, warn on threads | fork: `Faker::Config.random = Random.new(hash(seed, worker_index))` only if user didn't set it. Threads: copy locale/random/lazy keys into each worker thread (fresh `Random` per thread). `UniqueGenerator.clear` per test: **off** (opt-in) |
| WebMock | if no adapter loaded: RSpec → behave like `webmock/rspec`; Minitest → `webmock/minitest`; then `disable_net_connect!(allow_localhost: true, allow: ->(uri) { auto_allowed_host?(uri) })`, where auto-allowed = `Capybara.server_host` (evaluated lazily), hosts of `SELENIUM_REMOTE_URL`, `BROWSER_URL`/`CHROME_URL`, `ELASTICSEARCH_URL`/`OPENSEARCH_URL`, other `*_URL` service hosts present at boot | `$LOADED_FEATURES` has `webmock/rspec.rb`/`webmock/minitest.rb`, or `WebMock::Config.instance.allow_net_connect` non-nil / `allow_localhost` non-nil → user called `allow_/disable_net_connect!` → touch nothing | stubs/registry per process (fork OK). After each test restore `Config` snapshot (ours only). Threads: thread-local registries patch (required) |
| VCR | only when app uses VCR (cassette dir exists or VCR referenced): `cassette_library_dir` = first existing of `spec/cassettes`, `test/cassettes`, `spec/fixtures/vcr_cassettes`, `spec/fixtures/vcr`, `test/vcr_cassettes`, else by framework; `hook_into :webmock`; `ignore_localhost = true`; RSpec `configure_rspec_metadata!`; record `:once` (stock default); mirror WebMock `allow:` into `ignore_hosts` | `VCR.configuration.cassette_library_dir` non-nil, or `defined?(VCR::LibraryHooks::WebMock)` → user configured; never call `configure_rspec_metadata!` if user handles `:vcr` metadata themselves (double insert → `ArgumentError` "already a cassette with the same name", `vcr.rb:134-136`) | locked atomic cassette writes (flock + tmp + rename, skip-if-appeared for `:once`); fork from the thread that required VCR; when `ENV["CI"]` and cassette missing → warn (recording in parallel CI is almost always a mistake), don't change record mode |
| filter_sensitive_data | none (app-specific) | — | — |
| `allow_http_connections_when_no_cassette` | leave `false` | — | — |

Off switches: `FAST_RSPEC_DISABLE=factory_bot,faker,webmock,vcr`. Debug log of every decision at `FAST_RSPEC_DEBUG=1` (which detection fired, which hosts auto-allowed, cassette dir chosen).

### Conflicts to resolve in `docs/idea/06-batteries.md`

| Plan row | Finding | Proposed |
|---|---|---|
| factory_bot "sequences offset per worker" | breaks exact-value asserts + VCR body/URI matching; unnecessary with per-worker DB | off by default; on only in shared-DB mode |
| faker "`UniqueGenerator.clear` per test" | diverges from stock; collisions with rows surviving the test transaction | off by default |
| faker "seed from suite seed + worker id" | correct for fork; threads additionally need thread-local copy; work-stealing still breaks per-test determinism | keep + optional per-example reseed |
| vcr "always" | `hook_into :webmock` silently disables WebMock allow-lists and changes error class (`Exception` → `StandardError`) | only when app already uses VCR |
| webmock "always" | apps never using WebMock that hit docker-network services (ES, minio, grid) break | always, but auto-allow service hosts from ENV + Capybara host; one-line warning naming blocked host + off switch |
