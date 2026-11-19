# Reviewer instructions — developerz-ai/fast_rspec

> Read by the developerz.ai reviewer at EVERY review of this repository, at the reviewed
> commit, as this repo's own layer of the reviewer's prompt. It refines the platform rules
> (a finding is cited or withheld) and never overrides them. `AGENTS.md` (`CLAUDE.md` is a
> symlink to it) is the source of truth; this file is its review-time distillation.
> Keep it under 12,000 characters — past that it is cut.

## Stack

Ruby >= 3.2 (development pin `4.0` in `mise.toml` and `apps/fast-rspec/.ruby-version`),
Bundler, Rake, rake-compiler, a C extension (`apps/fast-rspec/ext/fast_rspec/`) with a
pure-Ruby twin, RuboCop with the minitest/performance/rake plugins. The gem lives under
`apps/fast-rspec/`. The gate is `bin/check` (lint, compile, unit, forced-PureRuby unit,
package smoke; `bin/check full` adds oracles and demo apps): a change that does not pass it
is not proven, whatever its description says.

The repo is a design-phase scaffold: the engine, frontends, parallel runner and batteries are
planned (`AGENTS.md` § Stack and status, `docs/idea/11-roadmap.md`).

## What to reject

**Drop-in compatibility (`AGENTS.md` § Non-negotiables, `docs/target/`)**
- A change to a public constant, method, arity, keyword argument, return value, raised
  exception class, CLI flag, option precedence, exit code or formatter output that diverges
  from `docs/target/*.md` without a row in `docs/idea/parity-divergences.md`
  (`.claude/agents/compat-reviewer.md`).
- A change that requires users to edit their spec/test files, helpers, support files or
  require paths.
- Upstream source copied verbatim: behaviour is rebuilt from `docs/target/` and the oracles,
  never from upstream internals.
- Shadowing installed frameworks before the replacement works: the `lib/compat/` stubs and
  `exe/rspec` stay out of the gemspec's `require_paths` / `executables` until their
  milestone (`apps/fast-rspec/fast_rspec.gemspec` comments).

**Zero runtime dependencies**
- Any `add_dependency` / `add_runtime_dependency` in `apps/fast-rspec/fast_rspec.gemspec`.

**User configuration wins**
- Wiring that does not first check for user configuration, double-configures, is not
  idempotent, or has no off switch. Detection with an installation side effect
  (`AGENTS.md` § Conventions: detection has no installation side effects).
- Rails code loaded outside a `defined?(Rails::Railtie)` guard
  (`apps/fast-rspec/lib/fast_rspec/rails/railtie.rb`).

**Native / pure parity**
- A change in `apps/fast-rspec/ext/fast_rspec/` without the matching change in
  `apps/fast-rspec/lib/fast_rspec/render/pure_ruby.rb` and a parity test
  (`apps/fast-rspec/test/unit/render_parity_test.rb`). Output must be byte-identical.
- A new C hot path without a benchmark (`bin/rake bench`, results in `docs/benchmarks.md`).
- C sources that include `<ruby.h>` without `<stdbool.h>` first: Ruby 3.2 needs it.
- GC-unsafe C or unchecked buffer sizing in the extension (`.coderabbit.yml` path rule).

**Runner, fork safety, determinism (as the runner lands)**
- DB/Redis/HTTP sockets shared across a fork, not closed before fork or not reconnected in
  the child (`.claude/agents/fork-safety-auditor.md`).
- Per-example IPC or allocation in the scheduler/reporter loop; one IPC message per file,
  no per-test process spawn (`docs/idea/08-performance.md`).
- Non-determinism: the same `--seed` must give the same per-worker order and Faker values;
  a failure must print a one-line reproduction command.

**Tests**
- Mocking the database or the Redis isolation layer: integration tests use real Postgres,
  MySQL, SQLite and Redis.
- Weakening a demo app test (`demo/rails/`, `demo/ruby/`) to make fast_rspec pass; upstream
  stays green.
- A test that mocks the behaviour being implemented instead of testing parity or real
  isolation.
- An upstream oracle failure dismissed without a row in `docs/idea/parity-divergences.md`.

**Claims and docs**
- A "faster than" or "Nx faster" claim in `README.md` or `llms.txt` without numbers in
  `docs/benchmarks.md`.
- Describing a planned capability (engine, runner, batteries) as shipped.
- A user-visible change without a `CHANGELOG.md` `## [Unreleased]` entry; a command or
  behaviour change without the `AGENTS.md` / `README.md` / `docs/` update
  (`.github/pull_request_template.md`).
- An `AGENTS.md` Commands row out of step with `bin/check` or `apps/fast-rspec/Rakefile`.

**Code hygiene (`AGENTS.md` § Conventions)**
- A file without `# frozen_string_literal: true`.
- Dead code, speculative abstractions or backwards-compat shims.
- RuboCop `TargetRubyVersion` (`apps/fast-rspec/.rubocop.yml`) out of step with the
  gemspec's `required_ruby_version`.
- An exact-patch Ruby pin (`4.0.10`) in `mise.toml` or `.ruby-version`: CI images only build
  the latest patch per series.

**Public tree and release**
- Anything private in a tracked file: the repo is public and `bin/check-public-tree` refuses
  private hosts, private repositories and trackers, home directories and private words.
- A tag, a hand `gem push`, or a version bump outside a release PR: merging a bump of
  `apps/fast-rspec/lib/fast_rspec/version.rb` is the release (`.github/workflows/release.yml`).
- A new CI job not added to `needs:` of the `CI OK` job in `.github/workflows/ci.yml`.

## Gates that matter

- `CI OK` in `.github/workflows/ci.yml` is the one required check; it fails unless `Lint /
  RuboCop` (plus the public-tree guard), `Test / 3.2`, `Test / 3.4`, `Test / jruby`,
  `Test / truffleruby`, `Package / build + smoke` and `Demo apps / upstream vs fast_rspec`
  all succeed.
- The demo job gates on upstream runs only; the fast_rspec stack is expected red until the
  roadmap milestones (comment in `ci.yml`).
- Serial/parallel parity is proven only by both pasted `FAST_RSPEC_WORKERS=1` and
  `FAST_RSPEC_WORKERS=4` runs of `demo/ruby/bin/stacks` with identical counts; a green
  `bin/check full` is not parity evidence (`.github/pull_request_template.md`).
- A runner, adapter or battery change is proven by `bin/check full`; the plain
  `bin/check` covers the rest.

## Never flag

- `.github/workflows/canary.yml` runs (Ruby head): outside `CI OK` by design.
- The plain-Ruby bootstrap harness in `apps/fast-rspec/test/bootstrap/` not being Minitest:
  it is excluded from the Minitest cops on purpose (`apps/fast-rspec/.rubocop.yml`).
- `TEST=...` not filtering `bin/rake test`: documented as unsupported in `AGENTS.md`.
- Oracle skips-with-reason: they never gate (`AGENTS.md` § Commands).
- The inert placeholders in `apps/fast-rspec/lib/compat/` and `exe/rspec` aborting: planned.
- `.keep` files in planned directories (`apps/fast-rspec/lib/fast_rspec/engine/` and its
  siblings), and the build output RuboCop excludes (`apps/fast-rspec/.rubocop.yml`).
- Formatting and style RuboCop already enforces.
- Docs house style (tables, fragments) and emoji headings in existing docs.
- The `.dz/` directory's own layout: the platform owns it.
