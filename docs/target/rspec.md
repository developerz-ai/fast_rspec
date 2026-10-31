# Compat target: RSpec

As of 2026-10, rspec 3.13.x (rspec-core 3.13.6, rspec-expectations 3.13.5, rspec-mocks 3.13.8, rspec-support 3.13.6), rspec-rails 8.0.4.
Source paths below are relative to each gem's root (`gem contents rspec-core`). `core/` = `rspec-core-3.13.6/lib/rspec/core/`.

**Rule:** every public surface listed here behaves byte-identically under `fast_rspec` vs stock `rspec`, except where a row in §7 says "documented divergence". We drive `RSpec::Core::Runner` / `Configuration` / `World` / `Reporter`; we never reimplement them.

---

## 1. CLI surface

### 1.1 Flags (`core/option_parser.rb`)

| Flag | Option key | Line | Parallel-runner note |
|---|---|---|---|
| positional `FILE[:LINE…]` / `FILE[ID,ID]` / `DIR` | `:files_or_directories_to_run` | 29 | parent expands → work units; pass original `file:line` / `file[id]` arg verbatim to the worker owning that file |
| `-I PATH` | `:libs` (concat, `File::PATH_SEPARATOR` split) | 45 | apply in parent before preload |
| `-r`, `--require PATH` | `:requires` (concat) | 50 | parent preload |
| `-O`, `--options PATH` | `:custom_options_file` | 55 | replaces *all* of global/project/local files |
| `--order TYPE[:SEED]` (`defined`, `rand`, `random`, `random:SEED`, `recently-modified`, custom) | `:order` | 59 | parent picks seed, forwards |
| `--seed SEED` | `:order = "rand:SEED"` | 68 | same seed to every worker |
| `--bisect[=verbose]` | `:bisect`, `:runner = Invocations::Bisect` | 72 | hard case §7 |
| `--[no-]fail-fast[=COUNT]` | `:fail_fast` (true→1, false/0→false) | 78 | global count across workers §7 |
| `--failure-exit-code CODE` | `:failure_exit_code` | 93 | parent exit |
| `--error-exit-code CODE` | `:error_exit_code` | 98 | parent exit |
| `-X`, `--[no-]drb` / `--drb-port PORT` | `:drb`, `:drb_port` | 103, 108 | legacy (spork); passthrough to stock serial path |
| `-f`, `--format FORMATTER` (`p`/`progress`, `d`/`doc`/`documentation`, `h`/`html`, `j`/`json`, `f`/`failures`, `bisect-drb`, class name) | `:formatters << [f]` | 114 | formatters run **in parent only** §3.5 |
| `-o`, `--out FILE` (applies to previous `-f`, else progress) | `:formatters.last << file` | 125 | parent only; workers never open it |
| `--deprecation-out FILE` | `:deprecation_stream` | 134 | parent merges deprecations |
| `-b`, `--backtrace` | `:full_backtrace` | 138 | backtrace filtered in worker |
| `-c`, `--color`, `--colour` (hidden) | `:color_mode = :automatic` | 142 | TTY check in parent, forward resolved mode |
| `--force-color`, `--force-colour` / `--no-color`, `--no-colour` | `:color_mode = :on/:off` (mutually exclusive → abort) | 148, 155 | workers' stdout is a pipe → must force parent's resolved mode |
| `-p`, `--[no-]profile [COUNT]` (default 10) | `:profile_examples` | 162 | merge timings in parent |
| `--dry-run` | `:dry_run` (skips all hooks incl. suite) | 181 | can be parallel or serial; output must match |
| `-w`, `--warnings` | `$VERBOSE = true`, `Warning[:deprecated]` | 186 | set before fork |
| `--only-failures` | `:only_failures` + inclusion `last_run_status: 'failed'` | 211, 320 | requires persistence file else `abort_with … 1` (`core/world.rb:252`) |
| `-n`, `--next-failure` | only-failures + fail_fast 1 + `order ||= defined` | 215 | global fail-fast |
| `-P`, `--pattern PATTERN` (comma-joined if repeated; default `**{,/*/**}/*_spec.rb` under `spec`) | `:pattern` | 222 | parent globbing |
| `--exclude-pattern PATTERN` | `:exclude_pattern` | 230 | parent globbing |
| `-e`, `--example STRING` (escaped regexp, repeatable) | `:full_description` | 235 | needs loaded groups → worker-side filter |
| `-E`, `--example-matches REGEX` | `:full_description` | 240 | worker-side |
| `-t`, `--tag TAG[:VALUE]` / `~TAG` (value coerced: `true/false/nil/:sym/int/float/str`) | `:inclusion_filter` / `:exclusion_filter` | 245 | worker-side |
| `--default-path PATH` (default `spec`) | `:default_path` | 270 | — |
| `--init` | `Invocations::InitializeProject` | 277 | passthrough, no pool |
| `-v`, `--version` | `Invocations::PrintVersion` | 281 | prints `RSpec 3.13` + per-gem versions; we may *append*, never replace |
| `-h`, `--help` | `Invocations::PrintHelp` | 295 | passthrough; `-d`, `--I` rejected as invalid (289–305) |

Gotcha: `files_or_directories_to_run=` adds `default_path` only when `$0` basename == `'rspec'` (`core/configuration.rb:1086`, `#command` at 2276). `exe/fast_rspec` must set `default_path` explicitly or the bare-command run loads nothing.

### 1.2 Option sources & precedence (`core/configuration_options.rb`)

Merged left→right, **later wins** (`organize_options`, :44–57). `:libs`/`:requires` concatenate instead.

| Order | Source | Path | Notes |
|---|---|---|---|
| 1 | global | `$XDG_CONFIG_HOME/rspec/options` if it exists, else `~/.rspec` | :202–237; missing `HOME` → warning |
| 2 | project | `./.rspec` | :194 |
| 3 | local | `./.rspec-local` | :198 |
| 1–3 replaced | custom | `-O PATH` | :125–131 — skips all three |
| 4 | command line | `ARGV` | :142 |
| 5 | env | `SPEC_OPTS` (shellwords) | :133 — **overrides CLI**; file args ignored |

- Option files: ERB-evaluated (`trim_mode: '-'`), `#` comment lines dropped, shellsplit (:173–187). File args in option files ignored (:167).
- Applied via `config.force(key => v)` except `UNFORCED_OPTIONS` (`requires profile drb libs files_or_directories_to_run full_description full_backtrace tty`, :59) → forced values beat later `RSpec.configure` in `spec_helper`. Notable: `--seed`/`--order` forced → `config.order = :random` in spec_helper cannot override CLI seed (`core/ordering.rb:190`).
- Apply order fixed by `OPTIONS_ORDER` (:77): `deprecation_stream, dry_run, libs, default_path, only_failures, files_or_directories_to_run, pattern, exclude_pattern, order, requires` — `requires` last so spec_helper sees CLI state.
- Default generated `.rspec`: `--require spec_helper` (`core/project_initializer/.rspec`).

### 1.3 Exit codes (`core/runner.rb`)

| Situation | Code | Source |
|---|---|---|
| all passed (pending OK) | `0` | runner.rb:198 |
| ≥1 example failed | `failure_exit_code` (default `1`) | :196, configuration.rb:550 |
| error outside examples (load error, `before/after(:suite)` raise, `notify_non_example_exception`) | `error_exit_code \|\| failure_exit_code` | :195; `world.non_example_failure` set in reporter.rb:164 |
| 0 examples + `config.fail_if_no_examples = true` | `failure_exit_code` | :117 |
| load error → `wants_to_quit` → `reporter.exit_early` | per `exit_code` above (non_example_failure) | :87 |
| `--only-failures` without persistence path | `1` via `exit!` | world.rb:255 |
| 2nd SIGINT | `exit!(1)` (skips at_exit) | runner.rb:182 |
| 1st SIGINT | sets `wants_to_quit`, finishes current example, prints summary | :180–190 |
| `SystemExit`/`SyntaxError` in spec file | `rspec_is_quitting`; SystemExit re-raised | configuration.rb:2143–2169 |
| `Runner.invoke` | `exit(status)` only if non-zero | :43–47 |

### 1.4 Example selectors

| Form | Mechanism | Stability |
|---|---|---|
| `path:37:87` | `extract_location` → `filter_manager.add_location` (configuration.rb:2259) | resolves to nearest preceding declaration *after load* (world.rb:140) |
| `path[1:5,1:6]` | `Example.parse_id` → `add_ids` (example.rb:122) | scoped id = per-file index chain (`metadata.rb:185`, `example_group.rb:492` uses `world.num_example_groups_defined_in(file)`) → **independent of other files loaded** → safe across workers |
| `Example#id` | `"#{rerun_file_path}[#{scoped_id}]"` (metadata.rb:105) | key of persistence file + random ordering |
| `location_rerun_argument` | `file:line`, walks up to a *loaded* spec file (example.rb:96) | depends on `config.loaded_spec_files` → worker must compute it, parent prints it |
| `-e` / `-E` / `-t` | metadata filters | worker-side |
| location/id filters are file-scoped (`filter_manager.rb:101`) | other positional files run fully | — |

### 1.5 `--only-failures` / persistence file (`core/example_status_persister.rb`)

- Enabled by `config.example_status_persistence_file_path = "spec/examples.txt"` (template commented, `project_initializer/spec/spec_helper.rb:60`).
- Format: pipe table `example_id | status | run_time`; statuses `passed failed pending unknown` (configuration.rb:1119–1134).
- Read once: `last_run_statuses` (configuration.rb:1101) → `metadata[:last_run_status]` (example.rb:212). `--only-failures` restricts files to `spec_files_with_failures` ∩ requested (configuration.rb:2204–2214).
- Write: after run, unless dry-run (runner.rb:203). `File.open(RDWR|CREAT)` + `flock(LOCK_EX)` + read-merge-rewrite (persister.rb:22–31). Merge: this-run wins unless `unknown`; drops ids of loaded files that no longer exist (:80–112). Note: `rewind`+`write` without `truncate`.
- Loaded-but-filtered examples are written as `unknown` → kept old status.

### 1.6 `--seed` / `--order` (`core/ordering.rb`)

- Default seed `rand(0xFFFF)` at `ConfigurationManager#initialize` (:149) — chosen in parent, inherited by fork.
- `Random#order`: `items.sort_by { jenkins_hash_digest(seed.to_s + item.id) }` (:29). Per-item key depends only on seed + id → **subset-stable**: any subset run with seed N keeps the same relative order as the full run. This is what makes per-worker repro possible.
- Top-level group order under `rand` interleaves files (global sort of all top-level groups), not file-by-file. A parallel run can't reproduce that global sequence; the relative order *within each worker* matches.
- `recently-modified`: sort by `File.mtime` (:65). Custom: `config.register_ordering(:global) { |list| … }`; group-level `:order` metadata.
- `"Randomized with seed N"` printed by `SeedNotification` at `start` and after `dump_summary` (reporter.rb:92, 189) only if seed used.
- `Kernel.srand config.seed` (template :96) is per-process: random values inside tests depend on what ran earlier in that worker → can't match serial; repro must use worker's file list.

---

## 2. `RSpec.configure` surface (`core/configuration.rb`)

### 2.1 Matters to a parallel runner

| Option | Why it matters |
|---|---|
| `order=`, `seed=`, `register_ordering`, `seed_used?`, `ordering_registry` | same seed in every worker; parent prints seed |
| `example_status_persistence_file_path=` | single merged write by parent (§7) |
| `only_failures`, `only_failures_but_not_configured?` | parent must know statuses to schedule |
| `fail_fast=` (int/true), `reporter.fail_fast_limit_met?` | cross-worker counter |
| `failure_exit_code`, `error_exit_code`, `fail_if_no_examples` | computed in parent from merged results |
| `before(:suite)` / `after(:suite)` / `prepend_before` / `append_after` | §4.1 |
| `before/after/around(:context\|:example)` via config | run in worker unchanged |
| `filter_run_including` / `filter_run` / `fit`/`fdescribe` / `filter_run_excluding` | worker-side, but see `filter_run_when_matching` |
| `filter_run_when_matching(:focus)` = `when_first_matching_example_defined { filter_run }` (:1291) | **global decision made per-process** §7 |
| `run_all_when_everything_filtered` (deprecated) | per-process `example_count.zero?` (world.rb:186) |
| `when_first_matching_example_defined` | fires per-process on first match → fires in N workers or 0 |
| `add_formatter`/`formatter=`, `default_formatter=`, `formatters`, `reporter` | parent owns real formatters |
| `output_stream=`, `error_stream`, `deprecation_stream=` | workers redirect; parent writes |
| `profile_examples=` | merged in parent |
| `dry_run` | skips suite hooks (:2092) |
| `files_or_directories_to_run=`, `files_to_run`, `pattern=`, `exclude_pattern=`, `default_path=`, `load_spec_files`, `loaded_spec_files` | the subset-loading seam |
| `color`, `color_mode`, `color_enabled?`, `tty` | workers must be told parent's TTY state |
| `silence_filter_announcements` | silence in workers, parent announces once |
| `threadsafe` (default true; `let` memo Mutex, memoized_helpers.rb:142) | thread pool needs it true |
| `start_time` (`$_rspec_core_load_started_at`) | load_time in summary = parent's |
| `bisect_runner` (`:fork`/`:shell`) | §7 |
| `full_backtrace=`, `backtrace_exclusion_patterns`, `backtrace_inclusion_patterns`, `filter_gems_from_backtrace`, `full_cause_backtrace` | apply in worker before serialization |

### 2.2 Rest (names only; must keep working, no runner impact)

`add_setting`, `alias_example_to`, `alias_example_group_to`, `alias_it_behaves_like_to`, `alias_it_should_behave_like_to`, `include`, `extend`, `prepend`, `include_context`, `define_derived_metadata`, `apply_derived_metadata_to`, `mock_with`/`mock_framework=`, `expect_with`/`expectation_framework=`, `expose_dsl_globally=`, `disable_monkey_patching!`, `expose_current_running_example_as`, `raise_errors_for_deprecations!`, `raise_on_warning=`, `warnings=`, `shared_context_metadata_behavior=`, `on_example_group_definition`, `format_docstrings`, `max_displayed_failure_line_count`, `pending_failure_output=`, `project_source_dirs`, `libs=`, `requires=`, `drb`, `drb_port`, `success_color`/`pending_color`/`failure_color`/`default_color`/`fixed_color`/`detail_color`, `treat_symbols_as_metadata_keys_with_true_values=` (no-op), `reset`, `reset_filters`, `reset_reporter`, `force`.

---

## 3. Runner internals to drive

### 3.1 Stock call graph

`exe/rspec` → `RSpec::Core::Runner.invoke` (runner.rb:43) → `.run(ARGV, $stderr, $stdout)` (:64): `trap_interrupt`, `ConfigurationOptions.new(args)`; special `options[:runner]` (bisect/init/version/help/drb) short-circuits → `Runner.new(opts, RSpec.configuration, RSpec.world).run` →
1. `setup`: `configure` (error/output streams, `options.configure(config)` = force options → filter manager → formatters) → `config.load_spec_files` (`load` each file, :1630) → `world.announce_filters` (ensure).
2. `run_specs(world.ordered_example_groups)`: `reporter.report(count) { config.with_suite_hooks { groups.map { g.run(reporter) }.all? } }` (:113).
3. `persist_example_statuses` (:203).
4. `exit_code(passed)`.

Also `RSpec::Core::Runner.autorun` (at_exit, for `ruby spec/x_spec.rb` + `rspec/autorun`); `disable_autorun!` guards double runs.

### 3.2 Worker recipe — upstream already does it

`core/bisect/fork_runner.rb:104–127` is the template: parent runs `Runner.new(options).configure(err, out)` + `requires` (preload), then per run: `fork { c.files_or_directories_to_run = ids; c.formatter = capture; c.load_spec_files; world.announce_filters; runner.run_specs(world.ordered_example_groups) }`, results sent back over a channel.

fast_rspec worker per unit (file or `file[ids]`):

| Step | Call | Note |
|---|---|---|
| preload (parent, once) | `ConfigurationOptions.new(argv)`, `Runner#configure`, requires (`spec_helper`, `rails_helper`) | no spec files loaded |
| fork | close sockets (AGENTS fork-safety) | `RSpec.world`/`configuration` copied COW |
| select | `config.files_or_directories_to_run = unit_args` | resets `@files_to_run` |
| load | `config.load_spec_files` | errors → `notify_non_example_exception` → must propagate as non-example failure |
| filter | `world.announce_filters` with `silence_filter_announcements` | |
| run | `runner.run_specs(world.ordered_example_groups)` or hand-rolled `reporter.report { with_suite_hooks { … } }` | keep suite hooks once per worker, not per unit |
| reuse worker for next unit | `RSpec.clear_examples` (core.rb:70: `world.reset`, `reset_reporter`, `start_time`, `reset_filters`) | `reset_filters` also drops CLI filters → re-apply `configure_filter_manager`; `world.reset` removes `RSpec::ExampleGroups` consts |
| don't | `persist_example_statuses` in worker | parent writes once |

### 3.3 `World` (`core/world.rb`) — per-process state

`example_groups`, `filtered_examples` (memo hash), `example_group_counts_by_spec_file` (drives scoped ids), `wants_to_quit`, `rspec_is_quitting`, `non_example_failure`, `shared_example_group_registry`, `@sources_by_path`, `syntax_highlighter`, `descending_declaration_line_numbers_by_file`. All plain ivars, no locks.

### 3.4 `Reporter` events (`core/reporter.rb`)

`RSPEC_NOTIFICATIONS` (:6): `start seed message example_group_started example_started example_passed example_failed example_pending example_finished example_group_finished deprecation stop start_dump dump_pending dump_failures deprecation_summary dump_profile dump_summary close`.

| Phase | Event sequence | Payload |
|---|---|---|
| `start` (:89) | `seed`, `start` | `SeedNotification(seed, used)`, `StartNotification(count, load_time)` |
| per group | `example_group_started` / `…_finished` (skipped if no filtered descendants) | `GroupNotification(group)` |
| per example | `example_started` → `example_passed\|failed\|pending` → `example_finished` | `ExampleNotification.for(example)` → `Failed…`/`PendingExampleFixed…`/`PendingExampleFailedAsExpected…`/`SkippedExampleNotification` |
| any time | `message`, `deprecation` | `MessageNotification`, `DeprecationNotification` |
| `finish` (:173) | `stop`, `start_dump`, `dump_pending`, `dump_failures`, `deprecation_summary`, `dump_profile` (unless muted/fail-fast hit), `dump_summary`, `seed`, `close` | `ExamplesNotification(reporter)`, `ProfileNotification(duration, examples, n, profiler.example_groups)`, `SummaryNotification(duration, examples, failed, pending, load_time, errors_outside_of_examples_count)` |
| custom | `reporter.publish(:event, hash)` → `CustomNotification` | user formatters may listen; must forward |

Reporter also keeps `examples`, `failed_examples`, `pending_examples`, `@non_example_exception_count`, `Profiler` (group timings via `example_group_started/finished`, `core/profiler.rb:5`). `abort_with(msg, code)` → `exit!`.

### 3.5 Formatter protocol (`core/formatters.rb`)

- `RSpec::Core::Formatters.register(klass, *events)` → `Loader.formatters[klass] = events` (:86). Events inherited via ancestors (`notifications_for`).
- Instantiated `klass.new(output)`; `-o FILE` opens stream. Duplicate class+output skipped. Unregistered class → legacy path (`rspec-legacy_formatters`) or deprecation.
- `setup_default` (:126): adds default formatter (`progress`) if none, `DeprecationFormatter`, `FallbackMessageFormatter` if nobody handles `:message`, `ProfileFormatter` if profiling and nobody handles `:dump_profile`. Lazy, on first `notify`.
- Built-in: `ProgressFormatter`, `DocumentationFormatter`, `HtmlFormatter`, `JsonFormatter`, `FailureListFormatter`, `BisectDRbFormatter`, `BaseTextFormatter` (summary, failure list, rerun cmds).
- Third-party formatters to keep working unmodified: `rspec_junit_formatter`, `fuubar`, `rspec-instafail`, Knapsack/`turbo_tests` JSON rows, CI annotators.

### 3.6 Serializing results to the parent

Formatters touch: `example.id/description/full_description/location/location_rerun_argument/metadata[:file_path,:line_number,:shared_group_inclusion_backtrace,…]/execution_result.{status,run_time,pending_message,pending_exception,exception,pending_fixed?}`, `example.example_group` (documentation nesting), `notification.fully_formatted(i, colorizer)` → `ExceptionPresenter` (reads source lines for snippet, syntax-highlights, diffs, `cause` chain, `MultipleExpectationsNotMetError#all_exceptions`/`aggregation_metadata`).

| Option | Pro | Con |
|---|---|---|
| A. worker runs formatter, parent concatenates text | trivial | summary/seed/profile/failure numbering wrong; JSON/JUnit invalid; output interleaves |
| B. per-event structs + fake `Example`/`ExampleGroup`/exception proxies rebuilt in parent, fed to real formatters (turbo_tests approach: https://github.com/serpapi/turbo_tests `lib/turbo_tests/json_rows_formatter.rb`, `reporter.rb`) | real formatters, one summary | must cover every attr formatters read; custom metadata values may not serialize; exception class identity lost (`is_a?(ExpectationNotMetError)`) |
| C. B + pre-rendered failure text from worker (`fully_formatted` with parent's colorizer) | byte-identical failure blocks; snippets read where code is | numbering `1)` assigned by parent → render body without index, prefix in parent |

Target: **C**. One IPC message per file (AGENTS), not per example — means progress dots arrive in bursts; acceptable, document. Exceptions: never `Marshal` user exceptions (procs, sockets) — send `{class_name, message, backtrace, cause, all_exceptions}`.

### 3.7 Process-global state (breaks under threads; fork-safe only if reset)

| State | Where | Fork | Threads |
|---|---|---|---|
| `RSpec.configuration`, `RSpec.world` | core.rb:85, 160 (module ivars) | copied; fine | shared; one Runner per process only |
| `Runner` autorun flags, `trap('INT')` | runner.rb:136–177 | child inherits trap → install own | — |
| `RSpec.current_example`, `current_scope` | `RSpec::Support.thread_local_data` (thread variable, rspec-support support.rb:95) | ok | ok |
| `RSpec::ExampleGroups` constants, name disambiguation `Foo_2` | example_group.rb:846–910 | names differ by load set (only visible in `inspect`) | shared |
| class-level `before_context_ivars` | example_group.rb:536 | ok | ok if a group runs on one thread |
| `world.wants_to_quit` (fail-fast, SIGINT) | world.rb:11 | per worker → parent must broadcast | shared → stops all threads (fine) |
| reporter lists, profiler | reporter.rb | per worker | not thread-safe (`@examples <<` unsynchronized) |
| `RSpec::Mocks.space` / `@space_stack` | rspec-mocks mocks.rb:38–55, 108 | ok | **broken**: concurrent setup/teardown corrupts stack |
| partial doubles, `allow_any_instance_of`, `stub_const`, `hide_const` | mutate real classes/constants | ok | **leak across threads** |
| `Kernel.srand`, `$stdout` capture (`output` matcher reassigns `$stdout`) | process | ok | leak |
| `ENV`, `Dir.chdir`, `Time` stubs | process | ok | leak |

→ JRuby/TruffleRuby thread mode cannot be byte-identical for suites using partial doubles / `stub_const` / `output` matcher. Thread pool must be file-granular, run one `Runner`-equivalent with a synchronized reporter facade, and **documented-divergence** for global stubs (or a spawn pool fallback).

---

## 4. Hook semantics a parallel runner can break

| Construct | Stock semantics | Parallel decision |
|---|---|---|
| `config.before(:suite)` | once, in `with_suite_hooks` before first group; stops at first raising hook (configuration.rb:2186) | **once per worker** (matches parallel_tests/turbo_tests; rspec-rails itself registers a `before(:suite)` for verifying doubles, `rspec-rails/lib/rspec/rails/active_record.rb:8`). Not in parent. Errors → non-example failure, exit `error_exit_code`. Divergence: expensive suite setup (asset build, `clean_with(:truncation)`) runs N×; must be idempotent per worker resources |
| `config.after(:suite)` | once, all run even if one raises | once per worker at worker shutdown, not per unit |
| `before/after(:suite)` with metadata / in a group | warns, ignored / unsupported (hooks.rb:455) | same warnings, once (dedupe in parent) |
| `around(:suite)`, `around(:context)` | unsupported, warns (hooks.rb:463) | same |
| `before(:context)` / `after(:context)` | once per group, ivars copied to each example (example_group.rb:554–601); skipped if group has no filtered examples | atomic unit ≥ top-level group; never split a group with `:context` hooks across workers |
| `around(:example)` | wraps example incl. `before/after(:example)` | unchanged |
| `--dry-run` | no hooks at all (configuration.rb:2092) | same |
| `shared_examples`/`shared_context` at top level | registered at **load time** in `world.shared_example_group_registry`; `it_behaves_like` resolves at definition → `ArgumentError "Could not find shared examples"` (example_group.rb:390) | serial works when the defining spec file sorts earlier; a worker loading only the user file fails. Fix: preload files defining shared groups, or on that error retry with the definer; must not silently pass |
| `filter_run_when_matching :focus` / `fit` | if any loaded example is focused, run only focused | per worker → worker without focus runs everything. Parent needs global knowledge (cheap dry pass or worker-reported "has focus" + 2nd phase) |
| `when_first_matching_example_defined` | fires once on first match | fires once per worker that sees a match |
| `metadata` / `define_derived_metadata` | computed at definition | unchanged; per worker |
| example ids `file[1:2]` | per-file indices | stable across workers ✔ |
| `config.include … type:` / `infer_spec_type_from_file_location!` | derived metadata | unchanged |
| `RSpec.current_example` | thread-local | ok |
| `--fail-fast` | stop after N failures; `dump_profile` muted when hit | global counter in parent, broadcast stop; in-flight examples finish → may report > N failures (documented divergence) |

---

## 5. rspec-expectations & rspec-mocks

### 5.1 Public DSL (names)

| Gem | Names |
|---|---|
| expectations core | `expect(…).to/not_to/to_not`, `expect { }`, `is_expected`, `should`/`should_not` (old syntax), `aggregate_failures` (block + `:aggregate_failures` metadata), `RSpec::Matchers.define`/`define_negated_matcher`/`alias_matcher`, `RSpec::Matchers::DSL` (`match`, `match_when_negated`, `failure_message`, `description`, `chain`, `diffable`, `supports_block_expectations`), composable `.and`/`.or`, `RSpec::Matchers::Composable` |
| matchers | `be_truthy be_falsey/be_falsy be_nil be be_a/be_an be_an_instance_of/be_instance_of be_a_kind_of/be_kind_of be_between be_within change contain_exactly cover end_with eq eql equal exist have_attributes include all match match_array output raise_error/raise_exception respond_to satisfy start_with throw_symbol yield_control yield_with_no_args yield_with_args yield_successive_args`, dynamic `be_<predicate>`, `have_<predicate>`, `>`/`<`/`=~` operators, plus every `a_*`/`an_*`/`*ing` alias (`a_hash_including`, `a_string_matching`, `a_value_within`, …) (`rspec-expectations-3.13.5/lib/rspec/matchers.rb`) |
| expectations config | `syntax=`, `max_formatted_output_length=`, `color?`, `include_chain_clauses_in_custom_matcher_descriptions`, `on_potential_false_positives=`, `warn_about_potential_false_positives=`, `strict_predicate_matchers=`, `backtrace_formatter` |
| mocks | `double instance_double class_double object_double spy instance_spy class_spy object_spy allow expect(…).to receive receive_messages receive_message_chain have_received allow_any_instance_of expect_any_instance_of stub_const hide_const without_partial_double_verification RSpec::Mocks.with_temporary_scope` + chain `with once twice thrice exactly at_least at_most times never ordered and_return and_raise and_throw and_yield and_call_original and_wrap_original and_invoke as_null_object` (`rspec-mocks-3.13.8/lib/rspec/mocks/example_methods.rb`) |
| mocks config | `syntax=`, `verify_partial_doubles=`, `verify_doubled_constant_names=`, `transfer_nested_constants=`, `allow_message_expectations_on_nil`, `before_verifying_doubles`/`when_declaring_verifying_double`, `yield_receiver_to_any_instance_implementation_blocks=`, `patch_marshal_to_support_partial_doubles=`, `color?` |

### 5.2 Global state / thread safety

- Expectations: config is a module singleton (set at preload, fine). `aggregate_failures` uses per-thread `failure_notifier` (rspec-support support.rb:106) → thread-safe. `output` matcher swaps `$stdout`/`$stderr` → process-global (threads: captures other examples' writes; fork: fine, but our worker stdout capture must sit *below* it, i.e. capture at fd level not by replacing `$stdout`).
- Mocks: `RSpec::Mocks.setup/verify/teardown` per example via `core/mocking_adapters/rspec.rb:18`; `@space`/`@space_stack` module ivars → **not thread-safe**. Proxies registered on real objects, `any_instance` rewrites class methods, `stub_const` rewrites constants → global. `Space` has a `ReentrantMutex` only for proxy registry (space.rb:148), not isolation.
- `patch_marshal_to_support_partial_doubles` patches `Marshal.dump` globally → our IPC must not use `Marshal` on user objects anyway.

---

## 6. rspec-rails (8.0.x needs Rails ≥ 7.2, rspec-core ≥ 3.13; Rails 7.1 → rspec-rails 7.1.x)

| Surface | Detail | Source (`rspec-rails-8.0.4/`) |
|---|---|---|
| spec types | `channel controller generator helper job mailer model request(requests\|integration\|api) routing view feature system mailbox` | `lib/rspec/rails/configuration.rb:27` `DIRECTORY_MAPPINGS` |
| `infer_spec_type_from_file_location!` | `define_derived_metadata(file_path: /spec[\\/]<dir>[\\/]/) { m[:type] \|\|= type }`; opt-in (commented in template :85) | configuration.rb:111 |
| type → module | `config.include RSpec::Rails::<X>ExampleGroup, type:`; mailer adds `config.after { ActionMailer::Base.deliveries.clear }` | configuration.rb:42, ~140 |
| settings | `use_active_record` (true), `use_transactional_fixtures` (alias `use_transactional_examples`), `use_instantiated_fixtures`, `global_fixtures`, `fixture_paths` (array, since 6.1; singular `fixture_path` present in 6.1.5, absent in 8.0.4 — Rails 7.2 dropped `TestFixtures#fixture_path`), `file_fixture_path` (`spec/fixtures/files`), `infer_base_class_for_anonymous_controllers`, `rendering_views`/`render_views`, `filter_rails_from_backtrace!` | configuration.rb:64–96 |
| transactional fixtures | `FixtureSupport` includes `ActiveRecord::TestFixtures`; `use_transactional_tests = config.use_transactional_fixtures`; `uses_transaction` opt-out | `lib/rspec/rails/fixture_support.rb:14–26` |
| `rails_helper.rb` | `require 'spec_helper'`; `ENV['RAILS_ENV'] \|\|= 'test'`; `require_relative '../config/environment'`; prod abort; `require 'rspec/rails'`; `ActiveRecord::Migration.maintain_test_schema!` (abort on `PendingMigrationError`); support glob commented `Rails.root.glob('spec/support/**/*.rb')`; `fixture_paths = [Rails.root.join('spec/fixtures')]`; `use_transactional_fixtures = true`; `filter_rails_from_backtrace!` | `lib/generators/rspec/install/templates/spec/rails_helper.rb` |
| `maintain_test_schema!` | runs at `rails_helper` **require time**: `load_schema_if_pending!` → may purge+load schema (activerecord `migration.rb:709–720`) | must run once in parent against the template DB *before* cloning per-worker DBs; never concurrently N× on one DB |
| system specs | `type: :system` → `SystemExampleGroup`; default `driven_by(:selenium_chrome_headless)` in a `before` unless set; `driven_by`, `served_by`; Puma silenced; failure screenshots via `before_teardown`/`after_teardown` | `lib/rspec/rails/example/system_example_group.rb:97–172` |
| system specs in parallel | per-worker Capybara server port, browser profile/tmp dir, screenshot path (`tmp/capybara`/`tmp/screenshots` collide by name) | fast_rspec isolation layer |
| generators | `rspec:install` + `rspec:{authentication,channel,controller,feature,generator,helper,job,mailbox,mailer,model,request,scaffold,system,view}`; Rails `g model` etc. hook via `config.generators.test_framework :rspec` | `lib/generators/rspec/*` |
| rake | `rake spec` (default task, prereq `spec:prepare` → `test:prepare`), `spec:<dir>` per `spec/*` dir, `spec:statsetup` (Rails < 8) | `lib/rspec/rails/tasks/rspec.rake` |
| matchers | `be_a_new be_new_record be_valid have_http_status redirect_to render_template/have_rendered route_to be_routable have_enqueued_job/enqueue_job have_performed_job have_been_enqueued have_been_performed have_enqueued_mail/enqueue_mail have_broadcasted_to/broadcast_to have_stream_from have_streams send_email receive_inbound_email match_array` (relation) | `lib/rspec/rails/matchers/*` |
| no parallel awareness | rspec-rails has no `parallelize` equivalent; nothing in lib references `fork`/parallel | — |

---

## 7. Drop-in contract for fast_rspec

### 7.1 Must be identical

| Surface | Guarantee | How |
|---|---|---|
| CLI flags & precedence | every flag §1.1, sources §1.2 incl. `SPEC_OPTS` > CLI, ERB option files | reuse `ConfigurationOptions` verbatim in parent |
| exit codes | §1.3 table; `--failure-exit-code`, `--error-exit-code` | parent computes from merged `failed_count` + `non_example_failure` from any worker |
| formatter output | progress/doc/json/html/failures + third-party: same text modulo timing lines and example order | real formatters in parent fed rebuilt events (§3.6 C) |
| summary block | `Finished in X (files took Y to load)`, `N examples, M failures, K pending`, `Failed examples:` `rspec ./path:line # desc` lines, seed line | parent `SummaryNotification`; rerun args from worker |
| seed | same printed seed; same seed in every worker; `--seed N` reproduces each worker's order given its file list | parent seed forced via `config.force(order:)`; failure prints one-line repro with worker's files |
| example ids / `file:line` / `file[ids]` | resolve identically | pass through to owning worker |
| persistence file | same format, same merge semantics, written once | workers send `{id, status, run_time}` for **all loaded** examples (incl. unknown); parent calls `ExampleStatusPersister.persist`-equivalent once |
| `--only-failures` / `--next-failure` | same selected set | parent reads statuses, schedules only files with failures; `-n` = global fail-fast 1 + `defined` order |
| `--dry-run` | same listing | parallel ok |
| load errors | "An error occurred while loading ./spec/x_spec.rb" + exit `error_exit_code \|\| 1`, other files still reported "0 examples, 0 failures, 1 error occurred outside of examples" | forward non-example exceptions + count |
| SIGINT | 1st: graceful stop + summary; 2nd: hard kill exit 1 | parent traps, signals workers |
| `RSpec.configure` in user helpers | applied once per process, theirs wins | preload helpers in parent |

### 7.2 Known hard cases

| Case | Problem | Plan / divergence |
|---|---|---|
| `--only-failures` status file merge | N workers each flock-merge partial runs; "deleted example" pruning keyed on loaded files (persister.rb:100–112) | workers never write; parent merges full this-run set once. Fallback if a worker crashes: its files keep previous statuses (never mark `passed`) |
| `--bisect` | needs deterministic single-process order; parallel failure may depend on co-located files | run stock `Invocations::Bisect` (`:runner` short-circuit) serially, seeded with the failing worker's file list + seed; never parallelize bisect itself |
| order-dependent failures | global interleaved random order not reproducible | repro line = `rspec --seed N <worker files>`; subset-stable hash makes it exact |
| formatters writing to stdout from N processes | interleaved / duplicated headers, broken JSON/JUnit XML | workers: no user formatters, stdout/stderr captured at fd level, released per file in order; only parent formatters write |
| user `puts`/`warn` in specs | stock: inline with dots | buffered per file, flushed atomically (divergence in timing only) |
| `--fail-fast[=N]` | per-worker `wants_to_quit`; examples in flight | parent counts, broadcasts stop; reported failures may exceed N (documented divergence); profile muted when limit hit (reporter.rb:250) |
| `filter_run_when_matching :focus` / `run_all_when_everything_filtered` / "No examples found" / "All examples were filtered out" | decided per process from its subset | global decision in parent (discovery pass or two-phase); workers silenced |
| shared examples defined in other spec files | load-order dependent resolution | detect "Could not find shared" and reschedule with definers preloaded; or preload all `shared_examples` files |
| `before(:suite)`/`after(:suite)` | run N× instead of once | documented; per-worker resources make most idempotent; expose `FastRspec.parent { }` hook for true once-only |
| `config.profile_examples` | per-worker profiler; group timings | merge example + group timings in parent, then sort/slice |
| `maintain_test_schema!` / `db:test:prepare` | runs at require-time in parent | must finish before template DB clone; never in workers |
| `Kernel.srand(config.seed)` + Faker/`rand` in tests | values depend on per-worker history | seed per file (`seed ^ hash(file)`) is *our* addition only when we own seeding; never override user's `srand` |
| thread pool (JRuby/TruffleRuby) | mocks space, partial doubles, `stub_const`, `output` matcher, reporter lists are process-global | file-granular threads + synchronized reporter; suites using global stubs → spawn pool or serial fallback; documented divergence |
| `$0 != 'rspec'` | `default_path` not auto-added (configuration.rb:1086) | set it explicitly in our exe |
| `RSpec::ExampleGroups::Foo_2` names | depend on global load set | only visible in `inspect`/custom formatters; documented |
| custom metadata in formatters (e.g. JUnit `:type`, screenshots path) | must survive IPC | serialize JSON-safe metadata subset; non-serializable values → `inspect` string |
| `--drb` / spork | separate invocation path | passthrough serial, no pool |
| `rspec/autorun` / `ruby spec/x_spec.rb` | at_exit runner | passthrough serial |
