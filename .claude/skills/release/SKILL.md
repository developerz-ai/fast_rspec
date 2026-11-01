---
name: release
description: Prepare a fast_rspec release PR — bump version, move CHANGELOG Unreleased into a dated section, verify, smoke-test, open a `release: X.Y.Z` PR. Merging it publishes (release.yml). Use when asked to release, publish, ship or bump the version.
disable-model-invocation: true
---

# Release fast_rspec

Argument: `X.Y.Z` or `patch|minor|major`. Merging a change to `apps/fast-rspec/lib/fast_rspec/version.rb` on `main` runs `.github/workflows/release.yml`, which publishes to RubyGems, then tags and creates the GitHub release. Opening the PR is safe; **merging it is the publish**.

1. **Preflight** (stop on failure): clean tree; branch from fresh `origin/main`; `## [Unreleased]` non-empty; `git tag -l vX.Y.Z` and `gem list -r fast_rspec --all` lack X.Y.Z. A major needs the owner's go-ahead.
2. **Bump**: `VERSION = 'X.Y.Z'`; CHANGELOG `## [X.Y.Z] - <today>` + empty `## [Unreleased]`.
3. **Verify**: `bin/check full`, `bin/rake smoke`.
4. **PR**: branch `release/X.Y.Z`, one commit `release: X.Y.Z`, PR titled `release: X.Y.Z`, changelog section as body.
5. **Merge** only on green "CI OK" and with authorization (owner, or the `.dz` maintainer policy for non-majors). Then `gh run list --workflow release.yml --limit 1`.

Never: push a `v*` tag, `gem push`, `rake release`, reuse a version, `gem yank` unless the owner asks.
