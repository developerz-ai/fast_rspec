---
name: upgrade-deps
description: Upgrade dev dependencies and track upstream releases of the gems we reimplement (rspec, minitest, rails, webmock, vcr, faker, factory_bot, database_cleaner, simplecov, shoulda, capybara). Use for Dependabot failures, upstream majors, or the weekly compat checkup.
---

# Upgrade deps / track upstream

fast_rspec has zero runtime deps; "upgrading" means (a) dev deps in `Gemfile`, (b) keeping our reimplementations matched to new upstream releases.

## Dev deps
`bundle outdated` → `bundle update <gem>` → `bin/check`. One PR per group (rubocop*, rake*, …).

## Upstream release of a gem we reimplement
1. `gem list <gem> --remote --exact` vs the version dated in `docs/target/<file>.md`.
2. Read the upstream CHANGELOG + diff of public API (`gem contents`, GitHub compare).
3. Update `docs/target/<file>.md` first (new dated "As of" line).
4. Bump the oracle pin (`test/oracles/<gem>/.sha`) and run it (`oracle` skill).
5. Implement new/changed surface; one `compat` issue + PR per change.
6. Upstream removed something users still call → keep supporting both (we serve users on both versions), like minitest 5 + 6.
