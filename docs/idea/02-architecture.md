# 🏗️ Architecture

## Our own RSpec + Minitest (decided 2026-10-31)
| Option | Verdict |
|---|---|
| Depend on upstream, own only the runner | ❌ inherits 216 ms boot, 84k allocs, ~0.27 ms/example of framework overhead per worker; can't fix the core |
| **Reimplement RSpec + Minitest on one lean engine** | ✅ wurk-style: public API identical, internals ours, upstream suites as oracles |
| Reimplement the batteries too | ✅ where worth it (webmock, faker, vcr, database_cleaner, simplecov, later factory_bot); ❌ shoulda + capybara are wired, not rebuilt — [06-batteries.md](06-batteries.md) |

### One engine, two frontends
```
RSpec DSL ─┐                         ┌─ RSpec formatters (progress, documentation, json, junit)
           ├─► Engine: Group/Example ┤
Minitest ──┘    hooks · let · world  └─ Minitest reporters (summary, progress, plugins)
                filters · ordering
                       │
                    Runner (preload → pool → work-steal)
```
- Engine knows nothing about RSpec vs Minitest; frontends compile DSL → engine structs at load time.
- One unit type for the scheduler → mixed suites (`spec/` + `test/`) run in one pool.

### Drop-in mechanics
| Concern | Mechanism |
|---|---|
| `require 'rspec/core'`, `'rspec/expectations'`, `'rspec/mocks'`, `'rspec/rails'`, `'rspec/autorun'` | shim files in `lib/compat/` loading ours |
| `require 'minitest'`, `'minitest/autorun'`, `'minitest/spec'`, `'minitest/mock'`, `'minitest/pride'` | same; `lib/compat` is unshifted onto `$LOAD_PATH` when `fast_rspec` loads |
| minitest gem still installed (activesupport depends on it) | our path wins; guard raises a clear error if upstream `Minitest` loaded first |
| `rspec` executable | `exe/rspec` (users drop rspec-core, so no clash) |
| Battery require paths (`factory_bot`, `factory_bot_rails`, `faker`, `vcr`, `webmock`, `webmock/rspec`, `webmock/minitest`, `database_cleaner/active_record`, `simplecov`) | shims in `lib/compat/` → ours; same constants. **No** shims for shoulda/capybara — those load upstream |
| Other third-party gems that hook RSpec/Minitest (e.g. `rspec-sidekiq`, `minitest-reporters`, `pundit-matchers`) | they call our public API; top ones get oracle runs |
| Version checks (`RSpec::Core::Version::STRING`, `Minitest::VERSION`) | report the upstream version we're compatible with |

## Process tree (CRuby, fork pool)
```
fast_rspec (parent)
├─ boot: load Gemfile, app, spec_helper/test_helper ONCE
├─ prepare isolation: template DB, worker DB clones, Redis DBs
├─ close parent sockets (DB, Redis, HTTP pools)
├─ fork N workers ──► each: reconnect, set TEST_ENV_NUMBER, install per-worker isolation
├─ queue: longest-first work units over a pipe/UNIX socket; idle workers steal
├─ collect: serialized notifications → one ordered reporter
└─ exit with upstream's exit code
```
JRuby/TruffleRuby: same tree, workers are threads; isolation by thread-local DB connection ownership (Ecto-sandbox style, see [07-isolation.md](07-isolation.md)).

## Layers
See the table in [`AGENTS.md`](../../AGENTS.md#layout-planned). Rules:
- `Detect` is pure; `Batteries` are idempotent; `Runner` and `Engine` know nothing about RSpec vs Minitest (frontends translate).
- Plain Ruby never loads Rails code.
- One reason to change per class.

## 💤 Lazy loading (load nothing you don't use)
`require 'fast_rspec'` must cost ~nothing (target < 5 ms, < 1 MB; measured in `bin/rake bench`).

| Rule | How |
|---|---|
| Gem deps installed ≠ required | gemspec lists the batteries; we `require` a battery only when `applies?` is true |
| Constants via `autoload` | every `FastRspec::*` constant autoloads (Zeitwerk-free, plain `autoload`) |
| Detect without requiring | `Gem.loaded_specs`, `defined?`, file existence — never `require` to probe |
| Rails code behind Railtie | `lib/fast_rspec/rails/**` loads only under `defined?(Rails::Railtie)` |
| Capybara/cuprite/simplecov | loaded only if `spec/system` / `test/system` exist / `COVERAGE=1` |
| Upstream requires are deferred in workers too | a worker running no system test never loads Capybara |
| C ext loaded on first hot-path use | `FastRspec::Render` resolves `IMPL` at first reference |

## 🧵 Concurrency primitives — no concurrent-ruby in core
| Need | Use | Why not concurrent-ruby |
|---|---|---|
| fork pool IPC | `IO.pipe` / `UNIXSocket.pair` + `IO.select` (epoll) | processes, not threads — concurrent-ruby doesn't help |
| thread pool (JRuby/Truffle) | `Thread` + `Thread::Queue` / `SizedQueue` | core Ruby is enough; one less dep and fork-safety surface |
| atomic counters (fail-fast, sequences) | parent-owned (fork) / `Mutex` (threads) | trivial; no CAS needed off the hot path |
| Ractors | 🔬 research only | upstream gems aren't Ractor-safe; tests mutate globals |

concurrent-ruby is still present in Rails apps (ActiveSupport dep); we just don't depend on it. Revisit only with a benchmark.
