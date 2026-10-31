# 🧪 RSpec frontend

Our own RSpec: core DSL, expectations, matchers, mocks, rails spec types, formatters. Spec to implement: [`../target/rspec.md`](../target/rspec.md). Oracle: upstream's suites.

## Build order
1. Core DSL: `describe`/`context`/`it`, hooks, `let`/`let!`/`subject`, metadata, filtering, ordering, shared examples/contexts.
2. Expectations: `expect`/`to`/`not_to`, built-in matchers, `RSpec::Matchers.define`, compound/aggregate, diffs.
3. CLI + config: every flag, `.rspec` precedence, `RSpec.configure`, exit codes, persistence file.
4. Formatters: progress, documentation, json, failures, `Formatters.register` for third-party.
5. Mocks: doubles, `allow`/`expect(...).to receive`, `stub_const`, `and_call_original`, verifying doubles.
6. Rails: spec types, `type:` inference, transactional fixtures, request/system/model/mailer/job helpers.

## Mechanics
- `exe/rspec` / `bundle exec rspec` → our CLI.
- Same option precedence: `.rspec`, `~/.rspec`, `.rspec-local`, `SPEC_OPTS`.
- Worker: load assigned files into `RSpec.world`, run, forward reporter notifications.
- `before(:suite)` / `after(:suite)`: per worker (matches parallel_tests users' expectations); documented in target doc.
- Parent formatters receive replayed notifications → progress/documentation/JSON/JUnit output identical to serial.
- `--only-failures`, `--next-failure`: merge per-worker status into the one `example_status_persistence_file_path`.
- `--bisect`: ours, parallel-aware (uses the failing worker's recorded order).

## Upstream behavior we must match (see [`../target/rspec.md`](../target/rspec.md))
- Random order is per-example `hash(seed, id)` → match the exact hash so `--seed N` orders identically to stock rspec.
- `:focus` / `run_all_when_everything_filtered` are per-process decisions → the parent must decide globally (discovery pass).
- Shared examples resolve at load time → missing definer in a worker = `Could not find shared examples`; preload definers or co-schedule.
- Engine structs are serializable by design → parent gets compact results; failures pre-rendered in the worker; never Marshal user exceptions.
- Only the parent writes the `--only-failures` status file; `--fail-fast` counted in the parent; `--bisect` stays serial.
