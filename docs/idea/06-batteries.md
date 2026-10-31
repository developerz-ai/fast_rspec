# 🔋 Batteries

## ⚖️ Which ones are worth rebuilding (decided 2026-10-31)
Rule: rebuild when upstream costs every run (boot) or every test (hot path) **and** the surface is bounded. Otherwise auto-wire the user's upstream gem.

| Gem | Cost today | Surface | Verdict | Why |
|---|---|---|---|---|
| rspec-core / -expectations / -support | 216 ms boot, ~0.27 ms/example | large, well specified | ✅ **rebuild** — M2 | biggest per-example tax; engine is the product |
| rspec-mocks | in the 216 ms; process-global state | medium | ✅ **rebuild** — M2.5 | thread-safety + teardown cost; can't ship RSpec without it |
| rspec-rails | depends on rspec-core | small (wraps Rails test cases) | ✅ **rebuild** — M3 | forced: it requires upstream rspec-core |
| minitest | 92 ms boot, 0.45 s/10k (already lean) | ~5.3k LOC | ✅ **rebuild** — M1 | not for raw speed: one engine, one pool, minitest 5 + 6 + Rails 7.2–8.1 in one API |
| webmock | **1291 ms** boot (addressable, crack, hashdiff…) | Net::HTTP stub + adapters | ✅ **rebuild** — M4 | largest boot win; core is small |
| faker | 428 ms + **1016 ms first call** | huge but mechanical | ✅ **rebuild** — M4 | 1.4 s per worker; precompiled lazy data; breadth suits agents |
| database_cleaner | tiny | tiny | ✅ **rebuild** — M3 | we own DB isolation anyway |
| simplecov | small, fork-unaware | small (+ HTML) | ✅ **rebuild** — M5 | we must own cross-worker merging anyway |
| vcr | 145 ms | ~4.9k LOC | ✅ **rebuild** — M4 | sits on our webmock; needs locked cassette writes |
| factory_bot | ~213 ms (mostly activesupport, free in Rails) | ~3k LOC | 🟡 **rebuild later** — M6 | hot path (`create` per test) but win is modest; do after profiling |
| shoulda-matchers / -context | cheap (only runs when used) | very wide AR/AM matcher API | ❌ **wire, don't rebuild** | low payoff, high surface; we ship the Rails 8.1 fix + auto `integrate` |
| capybara + cuprite | 553 ms boot, but system tests are browser-bound | ~27k LOC, subtle waiting semantics | ❌ **wire, don't rebuild** | Ruby isn't the bottleneck; we own ports, per-worker browsers, lazy load |

Wired gems (❌) stay optional: not in our gemspec, auto-configured when in the user's Gemfile. Zero runtime deps holds.

**Rebuilt batteries (✅/🟡)**: each = `lib/fast_rspec/batteries/<name>/`: a lean implementation of the upstream public API under the upstream constant, plus auto-wiring (`applies?` · `configured_by_user?` · idempotent `install!`). Exact upstream APIs and real-world defaults: [`../target/`](../target/README.md). Oracle: the upstream gem's own suite.

## Build notes per battery
| Battery | Lean approach | Hard part |
|---|---|---|
| factory_bot | definitions compiled to plain methods; `build`/`create`/`build_stubbed`/`attributes_for`, traits, sequences, associations, callbacks, `FactoryBot.lint` | association strategies, `factory_bot_rails` definition paths |
| faker | generators as methods; locale data precompiled to compact frozen tables, **lazy per locale + per module**; no I18n required | breadth (hundreds of generators); data licensing (MIT, keep attribution) |
| webmock | one `Net::HTTP` patch + adapters loaded only when that client is loaded (Faraday, HTTPX, httpclient, Excon, …); no addressable/crack | URI normalization parity without addressable |
| vcr | cassettes = YAML (same format, upstream cassettes readable), locked atomic writes; hooks into our webmock | request matching rules, record modes |
| database_cleaner | transaction / deletion / truncation for AR, Sequel, Redis | per-adapter truncation SQL |
| simplecov | stdlib `Coverage` + merged per-worker results, same `.resultset.json` + HTML/JSON formatters | HTML report |

**Wired upstream gems** (`lib/fast_rspec/wiring/<name>.rb`): shoulda (auto `integrate`, Rails 8.1 `executable` fix), capybara/cuprite (per-worker port, browser, `save_path`; required before user support files), devise, sidekiq/wurk, ActiveJob.

Fallback: until a rebuilt battery passes its oracle, if the user's bundle has the upstream gem we may delegate to it (logged at `FAST_RSPEC_DEBUG=1`); removed per battery once green.

| Battery | Applies when | Default wiring |
|---|---|---|
| factory_bot | always (Rails → we require factory_bot_rails before init; `Bundler.require` won't) | `find_definitions` only if `FactoryBot.factories` empty; `Syntax::Methods` in RSpec + Minitest + AS::TestCase; sequences **not** offset (per-worker DB) |
| faker | always | `I18n.backend.eager_load!` before fork (first call ~1.2 s otherwise); seed = suite seed + worker id; `unique.clear` per test |
| webmock | always | `disable_net_connect!(allow_localhost: true)`, reset per test |
| vcr | **only if** the app uses VCR (cassette dir exists or `VCR` referenced) — `hook_into :webmock` overrides WebMock's allow-list | `cassette_library_dir` = existing dir, rspec metadata, record `:once`, locked + atomic cassette writes |
| database_cleaner | AR / Sequel / Redis present | transactional tests first; truncation only for tests that need it |
| shoulda | always | `integrate` with detected framework + Rails; Rails 8.1 shoulda-context fix |
| time helpers | ActiveSupport present | `ActiveSupport::Testing::TimeHelpers` everywhere |
| capybara | `spec/system` / `test/system` exist | cuprite headless, per-worker port + save_path |
| devise | Devise present | integration + controller test helpers |
| jobs | Sidekiq / Wurk / ActiveJob present | fake mode, per-worker Redis DB, `perform_enqueued_jobs` |
| coverage | `COVERAGE=1` | simplecov started before app load, merged across workers |

Off switch: `FastRspec.configure { |c| c.batteries.disable :vcr }` or `FAST_RSPEC_DISABLE=vcr,capybara`.

Upstream details, real-world patterns and the full defaults table: [`../target/factories-faker-http.md`](../target/factories-faker-http.md), [`../target/db-matchers-system-coverage.md`](../target/db-matchers-system-coverage.md).

## Traps found in upstream source
- DatabaseCleaner adapters set `:transaction` on load → "user configured it" must be detected by their calls, not state.
- `require "capybara/cuprite"` re-registers `:cuprite` → require it before user support files, never after.
- shoulda-context 2.0.0 + Rails 8.1 `executable` NameError → ship the fix (6 apps hand-patch it).
- Some apps abort unless DB name contains `_test` → per-worker names keep it.
