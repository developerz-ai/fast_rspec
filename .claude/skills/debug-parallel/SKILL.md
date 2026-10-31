---
name: debug-parallel
description: Debug a test that passes serially but fails (or flakes) under fast_rspec's parallel pool — order dependence, shared state, isolation gaps, fork/thread hazards. Use when a failure only appears with workers > 1, differs between fork/thread/spawn pools, or differs from stock rspec/minitest.
---

# Debug parallel-only failures

## 1. Classify
```bash
FAST_RSPEC_WORKERS=1 <cmd>          # serial: passes? → parallel-only
<cmd>                               # all cores: fails? note the printed one-line repro
FAST_RSPEC_POOL=spawn <cmd>         # fork vs spawn: differs? → state inherited across fork
```

## 2. Reproduce exactly
Run the printed repro (`fast_rspec -n1 --seed N <worker's unit sequence>`). Fails serially now → order dependence, not parallelism.

## 3. Bisect order dependence
`fast_rspec bisect --seed N <files>` (uses the failing worker's recorded order) → minimal polluter + victim pair.

## 4. Isolation gap?
Compare the resource the test touches against `docs/idea/07-isolation.md`: DB name, Redis DB, port, tmp dir, cassette, coverage file, ActiveStorage root, ENV, class-level state. Ask the `fork-safety-auditor` agent for a second read.

## 5. Fix where it belongs
- Our isolation missed a resource → fix in `lib/fast_rspec/isolation/` + a sample-app test proving serial == parallel.
- User's test is order-dependent under stock rspec too → not our bug; report with the bisect output.
- Divergence from stock behavior → `compat` issue + `docs/idea/parity-divergences.md` if intentional.
