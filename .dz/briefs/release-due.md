# Brief: is a release due?

Weekday checkup, fired by `schedules: release-due`. Decides *when*; `release.yml` does *how*.

## Decide

```bash
last=$(git describe --tags --abbrev=0 --match 'v[0-9]*' origin/main)
git log --format='%h %cI %s' "$last"..origin/main -- 'apps/fast-rspec/lib/**' 'apps/fast-rspec/ext/fast_rspec/*.c' 'apps/fast-rspec/ext/fast_rspec/*.h' 'apps/fast-rspec/ext/fast_rspec/extconf.rb' 'apps/fast-rspec/exe/*' apps/fast-rspec/fast_rspec.gemspec
```

Those paths are what the gemspec ships. Docs, tests, CI and benchmarks never owe a release.

| Window | Do |
|---|---|
| empty | nothing |
| `FastRspec::VERSION` already ahead of `$last` | nothing: a release is in flight |
| oldest shipping commit under 24 h old | nothing |
| a **breaking** change under `## [Unreleased]` | no release PR; file one owner issue if none says a major is pending |
| otherwise | one PR, **release: `<next>`** |

`<next>`: `### Added` under `## [Unreleased]` → minor; else patch. Pre-1.0: minor for anything user-visible.

## The release PR

1. Re-check the window on fresh `main`.
2. Empty `## [Unreleased]`? Add a `### Changed` line per shipping change.
3. Bump `apps/fast-rspec/lib/fast_rspec/version.rb`; move `## [Unreleased]` under `## [<next>] - <today>`.
4. `bin/check full && bin/rake smoke`. (Release is due when the version is not on RubyGems; the tag is created after publish.)
5. One PR titled `release: <next>`, nothing else in it. Merging it is the release. Never tag or `gem push` by hand.

Never open a second release PR while one titled `release: …` is open.
