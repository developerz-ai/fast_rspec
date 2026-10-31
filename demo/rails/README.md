# Rails demo app — fast_rspec acceptance test

A small but real Rails 8.1 blog (users, posts, comments, a weather API client, a mailer, two jobs,
a few pages with forms) with **two complete test suites** — RSpec in `spec/` and Minitest in
`test/` — that use the usual test batteries the way real apps do.

The same test files run against two gem stacks, chosen with one env var:

| `STACK=` | Gemfile | What it is |
|---|---|---|
| `upstream` (default) | [`gemfiles/upstream.gemfile`](gemfiles/upstream.gemfile) | the real gems: rspec-rails, factory_bot_rails, faker, webmock, vcr, database_cleaner-active_record, simplecov, minitest-mock + shoulda-matchers, shoulda-context, capybara, cuprite. **Must be green.** |
| `fast_rspec` | [`gemfiles/fast_rspec.gemfile`](gemfiles/fast_rspec.gemfile) | `gem 'fast_rspec', path: '../..'` replaces everything fast_rspec rebuilds; keeps shoulda-*, capybara, cuprite. |

Both share [`gemfiles/common.gemfile`](gemfiles/common.gemfile) (rails, sqlite3, puma, shoulda-*,
capybara, cuprite) via `eval_gemfile`. Each stack gets its own lockfile
(`gemfiles/<stack>.gemfile.lock`, not committed).

> **The `fast_rspec` stack is expected to be red until roadmap M3–M4.** The gem has no
> implementation yet. This app is the acceptance test: it goes green when fast_rspec is a real
> drop-in. Never make it pass by editing tests.

## Run

```bash
bin/stacks                     # both suites × both stacks, prints the matrix
bin/stacks upstream            # one stack   (or: fast_rspec)
bin/stacks minitest            # one suite   (or: rspec)
STRICT=1 bin/stacks            # also fail (exit 1) when the fast_rspec stack is red
DEMO_JS=0 bin/stacks           # skip the Chrome/cuprite system tests
```

`bin/stacks` runs `bundle install` for each gemfile, `bin/rails db:prepare` (`RAILS_ENV=test`),
then `bundle exec rspec` and `bin/rails test:all` (includes `test/system`). It exits non-zero only
when an **upstream** run fails. Full output: `tmp/stacks/<suite>-<stack>.log`.

By hand:

```bash
bin/rspec                      # = bundle exec rspec on gemfiles/$STACK.gemfile
bin/rails test:all             # config/boot.rb picks gemfiles/$STACK.gemfile
STACK=fast_rspec bin/rails test:all
COVERAGE=1 bin/rspec           # SimpleCov → coverage/
BUNDLE_GEMFILE=gemfiles/upstream.gemfile bundle exec rspec spec/models
```

`config/boot.rb` and `bin/rspec` map `STACK` to `BUNDLE_GEMFILE` (an explicit `BUNDLE_GEMFILE`
wins). The root `Gemfile` just `eval_gemfile`s the chosen stack so a plain `bundle install` works.

Needs Ruby 3.4, SQLite, and Chrome/Chromium for the one JS test (found on `PATH` or via
`BROWSER_PATH`; skipped cleanly when absent or `DEMO_JS=0`).

## Matrix (2026-10-31, 12 cores, Chrome present)

```
| suite    | stack      | result | tests                   | wall |
|----------|------------|--------|-------------------------|------|
| rspec    | upstream   | green  | 98 ex, 0 fail, 0 pend   | 8.1s |
| minitest | upstream   | green  | 98 runs, 0 fail, 0 skip | 5.8s |
| rspec    | fast_rspec | red    | -                       | 0.4s |
| minitest | fast_rspec | red    | -                       | 2.1s |
```

Upstream RSpec runs serially (rspec-rails has no built-in parallelism); upstream Minitest runs
`parallelize(workers: :number_of_processors)` — 98 tests is above Rails' 50-test threshold, so it
forks. Wall time includes boot.

Current fast_rspec-stack failure modes (expected): `bundle exec rspec` finds no `rspec`
executable in the bundle; `bin/rails test:all` dies on `require "minitest/mock"`.

## Battery coverage

Both suites test the same behaviour with the same batteries; Minitest uses shoulda-context
(`context` / `should`) and shoulda-matchers one-liners where RSpec uses `describe` / `it`.

| What | RSpec | Minitest | Batteries exercised |
|---|---|---|---|
| User model | `spec/models/user_spec.rb` | `test/models/user_test.rb` | shoulda-matchers (associations, presence/length/inclusion/uniqueness, `allow_value`), unique DB index, factory_bot sequences + `:admin` child factory + traits, faker |
| Post model | `spec/models/post_spec.rb` | `test/models/post_test.rb` | scopes, `travel_to` / `freeze_time`, `build_stubbed`, slug uniqueness index, traits (`:published`, `:scheduled`, `:long`) |
| Comment model | `spec/models/comment_spec.rb` | `test/models/comment_test.rb` | `counter_cache` matcher, `after_create_commit` → `have_enqueued_mail` / `assert_enqueued_email_with`, transient factory attributes |
| WeatherClient (Net::HTTP to `api.example.test`) | `spec/services/weather_client_spec.rb` | `test/services/weather_client_test.rb` | webmock (`stub_request`, `with(query:, headers:)`, `to_timeout`, lambda responses, `have_been_requested` / `assert_requested`), net blocked (`WebMock::NetConnectNotAllowedError`), vcr (`vcr:` metadata / `use_cassette`, multi-request cassette, unknown request → `UnhandledHTTPRequestError`, `turned_off`, `filter_sensitive_data`), one slow test (0.2 s) |
| PostStats report | `spec/services/post_stats_spec.rb` | `test/services/post_stats_test.rb` | deliberately slow (`sleep 0.2` per test) so parallel speedup shows |
| Posts pages | `spec/requests/posts_spec.rb` | `test/integration/posts_flow_test.rb` | request / integration tests, HTML + JSON, `attributes_for`, `have_enqueued_job` / `assert_enqueued_with`, `assert_select` |
| Weather page | `spec/requests/weather_spec.rb` | `test/integration/weather_test.rb` | vcr cassettes through a controller, webmock timeout → 503 |
| PublishPostJob | `spec/jobs/publish_post_job_spec.rb` | `test/jobs/publish_post_job_test.rb` | ActiveJob test adapter, `perform_enqueued_jobs`, enqueued mail, `freeze_time` |
| RefreshWeatherJob | `spec/jobs/refresh_weather_job_spec.rb` | `test/jobs/refresh_weather_job_test.rb` | rspec-mocks (`instance_double`, `allow`/`have_received`, `expect_any_instance_of`, `allow_any_instance_of`) / `Minitest::Mock` + `Object#stub`; `retry_on` re-enqueue; vcr |
| Mailers | `spec/mailers/*_spec.rb` | `test/mailers/*_test.rb` | ActionMailer test helpers, multipart, `deliver_later` |
| System, rack_test | `spec/system/posts_spec.rb` | `test/system/posts_test.rb` | capybara forms/selects/links, `perform_enqueued_jobs` around a click |
| System, JS | `spec/system/body_counter_spec.rb` | `test/system/body_counter_test.rb` | cuprite (headless Chrome) + database_cleaner **truncation** (browser + server thread) |
| Factories | `spec/factories_spec.rb` | `test/factories_test.rb` | `FactoryBot.lint traits: true` |
| Coverage | `spec/spec_helper.rb` | `test/test_helper.rb` | simplecov under `COVERAGE=1`; Minitest names each forked worker (`parallelize_setup`) and merges |

Support boilerplate, the way real apps write it:

- `spec/rails_helper.rb`, `spec/spec_helper.rb`, `spec/support/*` — `FactoryBot::Syntax::Methods`,
  DatabaseCleaner (transaction by default, truncation for `js: true`, `use_transactional_fixtures = false`),
  shoulda `integrate`, `webmock/rspec` + VCR (`configure_rspec_metadata!`), `TimeHelpers`,
  `ActiveJob::TestHelper`, capybara + cuprite driver registration.
- `test/test_helper.rb`, `test/application_system_test_case.rb`, `test/support/*` —
  `parallelize(workers: :number_of_processors)`, SimpleCov per-worker command names,
  FactoryBot/ActionMailer/ActiveJob helpers, `webmock/minitest` + VCR, DatabaseCleaner truncation
  for JS system tests only (`TruncationCleaning`), shoulda `integrate` **plus the Rails 8.1
  shoulda-context `executable` shim** (without it, any failing test crashes the reporter).

Shared data: factories live in `spec/factories/` and serve both suites (factory_bot_rails loads
`spec/factories` and `test/factories`; defining them twice would raise `DuplicateDefinitionError`).
VCR cassettes are hand-written YAML for the fake host, one copy per suite
(`spec/cassettes/`, `test/cassettes/`), replayed with `record: :none` — no network needed.
