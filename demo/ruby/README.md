# demo/ruby — plain-Ruby acceptance app

A small gem-shaped library (`Shop`, stdlib only, no Rails, no ActiveSupport) with **both** an RSpec suite (`spec/`) and a Minitest suite (`test/`) that use the batteries a typical non-Rails project uses. The same test files run on two stacks:

| `STACK` | Test gems | Expected today |
|---|---|---|
| `upstream` (default) | rspec 3.13, minitest 6 + minitest-mock, factory_bot, faker, webmock, vcr, simplecov | ✅ green, always |
| `fast_rspec` | `gem 'fast_rspec', path: '../../../apps/fast-rspec'` and nothing else | ❌ red until roadmap M1–M4 (`docs/idea/11-roadmap.md`) |

This app is an acceptance test for fast_rspec. When the fast_rspec stack fails, fix fast_rspec. Never change the tests to make it pass.

## The library

| File | What | Edge cases worth testing |
|---|---|---|
| `lib/shop/money.rb` | `Money` (`Data`): integer cents + currency | parsing, half-up rounding, `allocate` without losing cents, currency mismatch |
| `lib/shop/product.rb`, `cart.rb` | catalog item, cart with stock checks | overselling, merging lines, partial removal |
| `lib/shop/discounts.rb`, `pricing.rb` | percent / fixed / buy-X-get-Y, `:best` vs `:stack`, tax | coupon codes, expiry against an injected clock, never below zero |
| `lib/shop/order.rb` | order placement + state machine, JSON | invalid transitions, line snapshots |
| `lib/shop/exchange_rates.rb` | `Net::HTTP` client for the fake host `api.example.test` | caching, retries with backoff on 5xx/timeouts, 4xx not retried, bad JSON |
| `lib/shop/importer.rb` | CSV/JSON product import, atomic CSV export | row errors with line numbers, duplicates, quoting |
| `lib/shop/cache.rb`, `counter.rb` | thread-safe TTL cache and counter | compute-once under contention, real-clock expiry |

## Run

```bash
cd demo/ruby
bin/stacks                         # {rspec, rake test} x {upstream, fast_rspec} → matrix
STRICT=1 bin/stacks                # also fail on the fast_rspec stack

bundle exec rake                   # upstream: spec + test
bundle exec rspec                  # upstream RSpec only
bundle exec rake test              # upstream Minitest only
STACK=fast_rspec bundle exec rspec # same files on the fast_rspec stack
COVERAGE=1 bundle exec rake        # simplecov → coverage/
```

**Stack selection.** Each stack has its own Gemfile: `gemfiles/upstream.gemfile` and `gemfiles/fast_rspec.gemfile`. Both share `gemfiles/common.gemfile` through `eval_gemfile`. You can pick one in two ways:

- `BUNDLE_GEMFILE=gemfiles/<stack>.gemfile`. Each stack keeps its own lockfile. `bin/stacks` uses this.
- `STACK=<stack>` with the root `Gemfile`, which evals the matching gemfile. This is handy for one-off runs. The root `Gemfile.lock` is re-resolved whenever you switch stacks, and it is gitignored.

`bin/stacks` runs `bundle install --quiet` for each gemfile first, writes full logs to `tmp/stacks/<suite>-<stack>.log`, and exits non-zero only when an **upstream** run fails (any run with `STRICT=1`).

## Suites

- **RSpec** (`spec/`): ~131 examples. `.rspec` → `spec_helper`, which loads `spec/support/*`. Random order with `Kernel.srand`, `verify_partial_doubles`, `disable_monkey_patching!`.
- **Minitest** (`test/`): ~105 tests. `rake test` uses `Rake::TestTask`. `test_helper.rb` requires `minitest/autorun`, `minitest/mock`, `webmock/minitest`, vcr, factory_bot and faker, then includes helper modules into `Minitest::Test`.
- Both suites include a few slow tests (`sleep 0.2`, tagged `:slow` in RSpec) so that parallel speedup is visible.

### `parallelize_me!` (what plain-Ruby Minitest users do today)

Thread-parallel classes: `Shop::Money` (spec-style), `ProductTest`, `CartTest`, `OrderTest`, `CounterTest`, `CacheTest`. The other classes stay serial on purpose, because their tests touch process-global state that threads would share:

| Serial class | Why it can't be `parallelize_me!` |
|---|---|
| `ExchangeRatesTest`, `Checkout flow` | the WebMock stub registry is global and `webmock/minitest` resets it after every test |
| `PricingTest` | `Time.stub(:now)` patches a global singleton |
| `ImporterTest` | writes to a fixed path under the project's `tmp/` |

fast_rspec should run all of these in parallel through process isolation, without anyone editing the files.

## Battery coverage per file

| File | factory_bot | faker | webmock | vcr | mocks | other |
|---|---|---|---|---|---|---|
| `spec/shop/money_spec.rb` | `build`, trait | `Faker::Number` | | | | shared examples, table-driven `it`, `aggregate_failures`, `have_attributes` |
| `spec/shop/product_spec.rb` | sequence, traits, `create` + `skip_create`, `build_list` | `Commerce`, `Book` | | | | shared examples, `all(match)`, one-liner `it { }` |
| `spec/shop/cart_spec.rb` | transient attrs, `after(:build)`, trait | ✓ | | | | custom matcher `cost`, `change{}.from.to`, `by` |
| `spec/shop/discounts_spec.rb` | `initialize_with(**attributes)` | `Alphanumeric.unique` | | | | shared examples with a `let` block, nested `describe Class` |
| `spec/shop/pricing_spec.rb` | ✓ | | | | `instance_double`, `double`, multiple `and_return`, `have_received.with(kind_of)`, `not_to receive` | `cost` |
| `spec/shop/order_spec.rb` | ✓ | | | | `instance_double`, `stub_const` | custom matcher `allow_transition_to`, `is_expected`, `a_hash_including` |
| `spec/shop/counter_spec.rb` | | | | | | threads, `:slow` |
| `spec/shop/cache_spec.rb` | | | | | | threads, fake clock, `:slow` |
| `spec/shop/exchange_rates_spec.rb` | | | `stub_request`, `with(query:, headers:)`, `to_timeout`, response sequences, `have_requested`, `a_request` | metadata `vcr:`, `use_cassette`, `turned_off`, `record: :none` | `spy` + `.ordered` | `:slow` |
| `spec/shop/importer_spec.rb` | `build_list` + trait | random prices, product names with commas | | | | `include_context` with `around` tmp dir, fixed project `tmp/` path |
| `spec/shop/checkout_spec.rb` | ✓ | | ✓ | metadata `vcr:` | | end-to-end, `:slow` |
| `test/shop/money_test.rb` | ✓ | ✓ | | | | **Minitest::Spec** (`describe`/`it`/`let`/`subject`, `_()` expectations), `parallelize_me!` |
| `test/shop/product_test.rb` | sequence, traits, `create` | ✓ | | | | classic `Minitest::Test`, `parallelize_me!` |
| `test/shop/cart_test.rb` | transient, trait | ✓ | | | | custom `assert_costs`, `parallelize_me!` |
| `test/shop/discounts_test.rb` | ✓ | `unique` | | | | Spec + shared tests via an included module |
| `test/shop/pricing_test.rb` | ✓ | | | | `Minitest::Mock` (kwargs), `Time.stub` | `assert_mock` |
| `test/shop/order_test.rb` | ✓ | | | | `Minitest::Mock`, `Object#stub` on a constant | `parallelize_me!` |
| `test/shop/concurrency_test.rb` | | | | | | two classes, threads, `sleep`, `parallelize_me!` |
| `test/shop/exchange_rates_test.rb` | | | `stub_request`, `assert_requested`, `to_timeout`, sequences | `use_cassette`, `turned_off` | lambda sleeper | serial, slow |
| `test/shop/importer_test.rb` | `build_list` | ✓ | | | | `Dir.mktmpdir`, fixed `tmp/` path, `assert_output` |
| `test/shop/checkout_test.rb` | ✓ | | ✓ | `use_cassette` | | Spec-style end-to-end, slow |

simplecov: `COVERAGE=1` in `spec_helper.rb` / `test_helper.rb`, with branch coverage. The two runs merge into `coverage/`.

Cassettes (`spec/cassettes/`, `test/cassettes/`) are hand-written VCR 6 YAML and are never recorded. `Authorization` is filtered to `<RATES_API_KEY>`.

## Quirks the fast_rspec stack must reproduce

- **minitest 6 split out `minitest/mock`.** `Minitest::Mock` and `Object#stub` now come from the `minitest-mock` gem. fast_rspec must still answer `require 'minitest/mock'`.
- **VCR guards before WebMock.** With VCR hooked into WebMock, an unstubbed real request raises `VCR::Errors::UnhandledHTTPRequestError`, not `WebMock::NetConnectNotAllowedError`. It only raises the WebMock error inside `VCR.turned_off`. Both tests assert this order.
- **Mixed suite styles.** `Rakefile` uses the common `begin require 'rspec/core/rake_task' … rescue LoadError` idiom and `Rake::TestTask`. Both must keep working unchanged.
- **Faker seeding.** RSpec seeds `Faker::Config.random` from `config.seed` and clears `Faker::UniqueGenerator` after each test.
- **Fixed `tmp/` paths.** Tests that write to fixed paths under `tmp/` (e.g. `tmp/exports/catalog.csv`) collide across workers unless each worker gets its own tmp dir.
