# 🔮 Compat oracles

Our RSpec/Minitest are reimplementations, so upstream's suites ARE the spec — wurk's parity model. Pinned SHAs in `test/oracles/<gem>/.sha`, run against FastRspec in CI. Coverage of each oracle is tracked as a % in `docs/compat.md` and only goes up.

| Oracle | Proves |
|---|---|
| rspec-core features (cucumber/aruba) | CLI, config, output, exit codes |
| rspec-expectations, rspec-mocks specs | matchers, mocks, messages byte-identical |
| minitest's own test suite (5.x + 6.x) | assertions, spec DSL, reporters, plugins |
| shoulda-matchers, webmock, vcr, capybara, factory_bot rspec/minitest integration specs | third-party hooks into our RSpec/Minitest work |
| Output golden files | same spec run under stock rspec/minitest vs ours → identical stdout (modulo timings) |
| activesupport/railties testing | `parallelize`, `rails test` |
| factory_bot, vcr, webmock | batteries don't change behavior |
| Sample apps `test/apps/*` | end-to-end: serial result == parallel result |

Divergence → we're wrong, unless listed in [parity-divergences.md](parity-divergences.md).
