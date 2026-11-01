# Reviewer instructions — developerz-ai/fast_rspec

> Read by the developerz.ai reviewer at EVERY review of this repository, at the reviewed
> commit, as this repo's own layer of the reviewer's prompt — established by dz-runner setup mode.
> It refines the platform rules (a finding is cited or withheld; the bot always discloses)
> and never overrides them. Edit freely; keep it under 12,000 characters — past that it is cut.

## Stack

Ruby + Bundler + C extension. The gate is `bin/check` (`bundle exec rubocop && bundle exec rake compile && bundle exec rake test`): a change that does not pass it is not proven, whatever its description says.

## Review conventions

- Hold every change to the three pillars: 100% drop-in (no user file edits, same flags, output and exit codes), zero config (the user's own configuration wins), measured (no speed claim without numbers).
- Treat `docs/target/*.md` as the authoritative spec for every public surface; implement from it, never from upstream source.
- Refuse any change that adds a runtime dependency to `fast_rspec.gemspec`.
- Refuse copied upstream code: public behaviour only, from `docs/target/` plus oracles.
- Require a C change in `ext/fast_rspec/` to land with its twin in `lib/fast_rspec/render/pure_ruby.rb` and a parity test.
- Require any intentional upstream divergence to be listed in `docs/idea/parity-divergences.md`.
- Keep plain Ruby working without Rails: Rails code only under `defined?(Rails::Railtie)`.
- Keep batteries lazy and idempotent (`applies?`, `configured_by_user?`, `install!`); user config wins, never double-configure.
- Keep the fork pool safe: sockets closed before fork, reconnected in the child, nothing shared across a fork.
- Require `CHANGELOG.md` `## [Unreleased]` to be updated for user-visible changes, and `AGENTS.md`/`README.md`/`docs/` when commands or behaviour change.
- Keep RuboCop at zero offenses; do not accept a `rubocop:disable` that hides a real finding.
- Keep upstream minitest and rspec out of this repo's tests — `test/bootstrap/harness.rb` is the only framework in `test/`.

## Gates that matter

- `bin/check` must be green on the branch: `bundle exec rubocop && bundle exec rake compile && bundle exec rake test`. The PR template requires it.
- The suite must pass with the C extension built and with `FAST_RSPEC_DISABLE_EXT=1 bundle exec rake test`; CI runs both modes across Ruby 3.2, 3.4, JRuby and TruffleRuby.
- `bundle exec rake smoke` must pass (CI job "Package / build + smoke"): it installs the built gem into a throwaway `GEM_HOME` and requires it without Rails.
- CI's aggregate "CI OK" check (needs lint + test + package) is the merge gate; a pull request merges only when it is green.
- A change under `lib/fast_rspec/runner/**` or `lib/fast_rspec/isolation/**` must show serial (`-n 1`) and parallel results identical on a sample app.
- A perf claim needs before/after numbers from `bundle exec rake bench` on the same machine, recorded in `docs/benchmarks.md`.
- `rake test:oracles` and `rake test:apps` abort as unimplemented today — their absence is roadmap work, not a defect in the change under review.

## Never flag

- `lib/fast_rspec/fast_rspec.so`, `tmp/**`, `pkg/**`, `Makefile`, `mkmf.log` — build artifacts, gitignored.
- The empty `.keep` placeholder directories under `lib/fast_rspec/{engine,rspec,minitest,runner,reporter,isolation,wiring,batteries}/` — planned layout.
- `lib/compat/**` shim files whose whole body is `require 'fast_rspec'` — intentional upstream require-path mapping.
- The frozen-string-literal headers, the `Style/Documentation` disable and the `Minitest` exclusion for `test/bootstrap/**` — deliberate `.rubocop.yml` settings.
- The `bin/rake …` commands named in docs and skills while no `bin/rake` script exists — a known doc/script gap; the real command is `bundle exec rake …`.
- Version bumps, CHANGELOG section headers and dev-dependency bumps from dependency bots.
- The `exe/fast_rspec` / `exe/rspec` abort message "runner not implemented yet" — the runner is roadmap work.
