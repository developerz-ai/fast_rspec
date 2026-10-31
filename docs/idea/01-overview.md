# 🎯 Overview

## What
Lean reimplementations of RSpec and Minitest (same API, our engine) + a parallel runner + upstream batteries, wired. Not a new DSL: your specs/tests run unchanged on our engine.

## Who
| User | Today | With FastRspec |
|---|---|---|
| Rails + RSpec | rspec-rails + 10 gems + `spec/support/*` + parallel_tests | 1 gem, `bundle exec rspec` |
| Rails + Minitest | `parallelize(workers: :number_of_processors)` + support files | 1 gem, `bin/rails test` |
| Plain Ruby gem | rspec or minitest, serial | 1 gem, all cores |
| AI coding agents | slow inner loop, flaky parallel config | fast, deterministic, one-line repro on failure |

## Drop-in means
- Existing `spec/**`, `test/**`, `.rspec`, `*_helper.rb`, `support/**` untouched.
- Same commands: `rspec`, `rspec spec/x_spec.rb:12`, `bin/rails test`, `rake test`, `ruby -Itest test/x_test.rb`.
- Same flags, same output format, same exit codes, same `--seed` semantics.
- User config always wins over ours; we never configure something twice.
- Removing the gem (and re-adding the replaced gems) gives back the old behavior exactly.

## Workspace evidence (2026-10)
Survey of ~30 local Ruby projects: Minitest in most Rails apps, RSpec mostly in gems. Top test gems: factory_bot_rails, webmock, capybara, vcr, faker, cuprite, shoulda-matchers/-context, database_cleaner, minitest-reporters. Every Minitest app sets `parallelize(workers: :number_of_processors)` and hand-writes per-worker fixes (Redis namespaces, I18n reset, shoulda Rails 8.1 patch).

## Non-goals
- A new DSL or matcher library.
- Reimplementing the batteries (factory_bot, vcr, …) — only RSpec + Minitest are ours.
- Distributed CI queue as v1 (single machine first; `--partition i/n` for CI splitting).
