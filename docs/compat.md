# Compat status

Upstream suites run against fast_rspec with `bin/rake test:oracles`. The runner
writes one row per pinned suite to `apps/fast-rspec/tmp/oracles/results.json`.
See [`idea/09-compat-oracles.md`](idea/09-compat-oracles.md).

**Only a `pass` or `fail` verdict against a real compat adapter counts as
completed compatibility verification.** A `blocked` row (fetch, install,
timeout, crash or an inert placeholder), an accepted `skip`, and any run
delegated to an installed upstream gem are *not* FastRspec compatibility proof.
They are recorded here so the gap stays visible and actionable. A percentage is
meaningless without a completed run: `0%` below means "no evidence", never
"no examples passed". The runner exits `1` when a completed suite fails, `2`
when there are no completed suites and at least one is blocked, and `0`
otherwise.

## Latest run

`bin/rake test:oracles`, 10 suites. Summary line:

```text
oracle summary: completed=0 pass=0 fail=0 blocked=10 skip=0 - no compatibility verification: all available executions blocked
```

Pins are the first line of each `apps/fast-rspec/test/oracles/<suite>/.sha`.
`upstream_exit` is `—` when the upstream process never ran.

| Oracle | Pinned | Verdict | Pass | Fail | Skip | Upstream exit | Blocker |
|---|---|---|---|---|---|---|---|
| database_cleaner | `23fb7a71531791b38996b4107fd8741df9962ac2` | blocked | 0 | 0 | 0 | — | `bundle install` exit 39: running Bundler 2.6.9 does not match the specification installed for it (4.0.20) |
| factory_bot | `5d399535578de5d1c32a76d6d91a8f816ec01965` | blocked | 0 | 0 | 0 | — | `bundle install` exit 39: Bundler 2.6.9 vs specification 4.0.20 |
| faker | `e48d35f4fa0d4bda8257975d9549e4d9422a0ba4` | blocked | 0 | 0 | 0 | — | `bundle install` exit 7: `simplecov-json_formatter` not found on rubygems.org or locally |
| minitest | `819e9b5f873d7ab6d4edfeaed48542279367ff93` | blocked | 0 | 0 | 0 | — | `bundle install` exit 7: gem `minitest` not found in the pinned source at `tmp/oracles/minitest` |
| rspec-core | `4d8e9c3699dbc821b4603c3c01b6e81c85e3784c` | blocked | 0 | 0 | 0 | — | `bundle install` exit 39: Bundler 2.6.9 vs specification 4.0.20 |
| rspec-expectations | `cafd53dd142b97503b27555ebdb90cd15e0a2e7e` | blocked | 0 | 0 | 0 | — | `bundle install` exit 39: Bundler 2.6.9 vs specification 4.0.20 |
| rspec-mocks | `712e3ca92458b1bbd28931604fac2bb15d304cd2` | blocked | 0 | 0 | 0 | — | `bundle install` exit 39: Bundler 2.6.9 vs specification 4.0.20 |
| simplecov | `0e35b257e24381e4ec2c99b321954509ae21eaf0` | blocked | 0 | 0 | 0 | — | `bundle install` exit 39: Bundler 2.6.9 vs specification 4.0.20 |
| vcr | `5dcacdf69bd64b61a339cf57bb6d4c17eeef5eea` | blocked | 0 | 0 | 0 | — | `bundle install` exit 39: Bundler 2.6.9 vs specification 4.0.20 |
| webmock | `11392e455b9ee025b72cbebcaaa9e0a9f201bac0` | blocked | 0 | 0 | 0 | — | `bundle install` exit 39: Bundler 2.6.9 vs specification 4.0.20 |

**Completed: 0 of 10.** No suite executed, so there is no compatibility
percentage to report and no claim of drop-in parity follows from this run.

## Clearing the blockers

- Bundler 2.6.9 / specification 4.0.20 (8 suites): the Ruby installation has a
  stale upgraded default Bundler gem. Align the installed Bundler with its gem
  specification (a clean Ruby install for this series), then rerun the oracle.
- `simplecov-json_formatter` (faker): resolve the dependency in faker's pinned
  `Gemfile` or make it available in the oracle's gem source before rerunning.
- `minitest` missing from the pinned source (minitest): the local checkout must
  contain the gemspec/gem expected by its oracle `Gemfile`; verify the pinned
  SHA was fetched in full, then rerun.

Full failure text is in `apps/fast-rspec/tmp/oracles/<suite>-install.log`. After
a blocker clears, rerun `bin/rake test:oracles` and update each row from
`results.json`. Only completed rows may carry a pass rate.
