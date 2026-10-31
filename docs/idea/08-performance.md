# 🏎️ Performance

Claim nothing without numbers in `docs/benchmarks.md`.

| Optimization | Why |
|---|---|
| Preload once, fork | boot is often > 50% of a small run; parallel_tests pays it N times |
| Work-stealing, longest-first | no idle tail waiting on one slow file |
| Runtime log | stable plan across runs |
| Template DB clone | seconds → ms per worker vs schema load |
| Serial for tiny runs | `rspec file:line` must stay as fast as stock (agents' inner loop) |
| One message per unit | IPC cost independent of example count |
| C ext on CRuby | result encode/decode, runtime log parse, output buffer — PureRuby twin elsewhere |
| GC tuning in workers | `GC.compact` before fork; optional GC deferral between units |

Bench suites: `rake bench` (vs our past self, regression >5% flagged) · `rake bench:vs_stock` (vs `rspec`, `rails test`, parallel_tests, turbo_tests on sample apps). Report wall clock, CPU, peak RSS, per Ruby engine.

## 🪶 Lean engine tricks (why our RSpec/Minitest are faster per example)
| Trick | Upstream today | Ours |
|---|---|---|
| Example = compact struct | `RSpec::Core::Example` + metadata Hash per example (dozens of keys) | struct with fixed fields; metadata Hash built lazily on first `metadata` access |
| Hooks compiled per group at load | resolved per example through hook collections + filters | flat arrays per group, filters pre-applied; zero work per example when no hooks |
| `let` memo | `__memoized` Hash + thread-safe wrapper object | ivar slot per `let` (method defined once), Mutex only under thread pool |
| `expect(x).to eq(y)` | allocates target + matcher + handler each call | fast path for built-ins: no allocation on success; message built only on failure |
| Failure messages / diffs / backtrace filtering | partly eager | 100% lazy, only on failure |
| Descriptions | string-built per example | frozen once at definition |
| Mocks teardown | global space walk | per-example registry of what was touched |
| Reporter notifications | object per event | no events unless a formatter subscribes; progress formatter writes bytes |
| Require cost | ~90 files / 216 ms | single-digit files at boot; matchers, mocks, formatters autoload on first use |
| Minitest assertions | `assert_equal` builds message proc + diff check | message/diff only on failure |

Targets (verified in `docs/benchmarks.md` before any claim): `require` < 20 ms, < 5k allocs; 10k trivial examples serial < 0.5 s (rspec today 2.71 s).

## 🧰 Trick catalog

Every trick ships behind a benchmark. ✅ = default on · ⚙️ = opt-in · 🔬 = research.

### Scheduling
| Trick | Status | Note |
|---|---|---|
| Work-stealing queue (pull, not push) | ✅ | workers ask for the next unit; no static groups |
| Longest-processing-time first (LPT) | ✅ | from runtime log; unknown files estimated by size/example count |
| Split hot files into example/method units | ✅ | when one file > total/N; keeps `before(:context)` groups together |
| Batch tiny units | ✅ | send K fast files per message to cut IPC round-trips |
| Prefetch 1 unit per worker | ✅ | hides queue latency |
| Tail stealing | ⚙️ | idle worker re-runs a straggler's remaining examples |
| Run last-failed first | ✅ | `--only-failures` data → fast red signal |
| Serial fallback for tiny runs | ✅ | no fork tax on `rspec file:line` |
| Affinity: same worker for files sharing heavy `before(:context)` | 🔬 | |

### Boot
| Trick | Status | Note |
|---|---|---|
| Preload app once, fork after | ✅ | copy-on-write; boot paid once |
| `GC.compact` + `Process.warmup` before fork | ✅ | Ruby 3.3+ `Process.warmup` improves CoW |
| Eager-load app in parent (CI) / lazy (local) | ✅ | `CI=1` → eager |
| bootsnap honored | ✅ | |
| Warm lazy upstream caches before fork | ✅ | `I18n.backend.eager_load!` (Faker), FactoryBot definitions, Capybara drivers |
| Persistent warm parent (Spring-like server) | 🔬 | `fast_rspec --server` for agent inner loops |

### Data
| Trick | Status | Note |
|---|---|---|
| Template DB + clone per worker | ✅ | schema digest cache; PG `TEMPLATE`, SQLite file copy |
| Transactional tests by default | ✅ | truncation only where needed |
| Unlogged tables / `fsync=off` hints for PG test DB | ⚙️ | documented, not forced |
| Fixtures loaded once per worker | ✅ | Rails fixture cache |
| Factory `build_stubbed` hints | 🔬 | profiler suggests where `create` isn't needed |

### Runtime
| Trick | Status | Note |
|---|---|---|
| Out-of-band GC between units | ⚙️ | `GC.disable` in unit, `GC.start` between |
| YJIT on by default in workers (CRuby) | ✅ | `RubyVM::YJIT.enable` if available |
| Buffered output, flushed per unit | ✅ | no interleaving, fewer writes |
| Compact result encoding (C ext) | ✅ | PureRuby twin on JRuby/Truffle |
| Slowest-tests report | ✅ | `--profile`, feeds the runtime log |

### Skipping work
| Trick | Status | Note |
|---|---|---|
| `--failed` / `--next-failure` | ✅ | upstream semantics |
| `--stale` test impact analysis (coverage map → changed files) | 🔬 | ExUnit `--stale`, Crystalball |
| `--partition i/n` for CI | ✅ | ExUnit-style, runtime-balanced |

## 🧮 Data structures & algorithms

Hot loops are the parent's dispatch loop and the result path. Pick structures for O(1)/O(log n) there; anything O(n) per message is a bug.

| Concern | Structure / algorithm | Complexity | Why |
|---|---|---|---|
| Plan order | sort units by est. duration desc (LPT) | O(n log n) once | LPT ≤ 4/3 × optimal makespan; with work-stealing, near-optimal in practice |
| Dispatch | array used as a stack (pop from end of sorted array) | O(1) per pull | no heap needed once sorted; plain array beats a priority queue |
| Mid-run re-prioritization (retries, failures-first) | binary heap keyed by est. duration | O(log n) | only when units are re-inserted |
| Worker readiness | `IO.select` / `epoll` over worker pipes; JRuby: `Queue` | O(ready) | one syscall wakes on any worker |
| Unit ids | dense integer ids, file paths interned once | O(1) | messages carry ints, not strings |
| Runtime log | flat `path\tms` file, loaded into a Hash; EWMA per path (α=0.3) | O(n) load, O(1) lookup | smooths noisy timings; C ext parses on CRuby |
| Unknown durations | median of known files scaled by size | O(1) | better than "0" (which sorts slow new files last) |
| Results | fixed-shape tuples `[unit_id, status, ms, payload_offset]`, Marshal/C-encoded | O(1) per message | no per-example hash allocation in the parent |
| Ordered output | per-unit buffer, flushed in arrival order (progress) or plan order (documentation) | O(1) amortized | no interleaving, no global lock |
| Failure dedupe / status file merge | Hash by example id | O(1) | merging N worker status files is linear |
| Seeding | `seed ⊕ worker_id` via SplitMix64 | O(1) | independent, reproducible streams per worker |
| Sequence offsets (shared-DB mode only) | worker_id × 1_000_000 base | O(1) | disjoint ranges, no coordination |
| Port allocation | base + worker_id, probe-on-bind fallback | O(1) | |
| Test impact map (🔬) | file → bitset of covering tests | O(changed × tests/64) | fast `--stale` lookup |

Rules:
- No allocation per example in the parent's hot loop; reuse buffers.
- Strings frozen and interned; ids are Integers.
- Measure with `stackprof` + `memory_profiler` on the parent before optimizing; record the delta in `docs/benchmarks.md`.
