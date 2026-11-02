# Brief: is a release needed?

Weekly checkup, Thursdays 03:00 UTC, fired by `schedules: release-due`. It asks whether one is needed now; `release.yml` does *how*. The block below gathers facts and you make the call. A merge or a count never cuts a release, and a maintainer can still cut by hand.

## Judge

Read the window's commits, their diffs and `## [Unreleased]`, then ask: does someone using the gem get something from a release now?

- Usually yes: a fix they can hit, a feature they can use, a dependency change that reaches what they install.
- Usually no: a run of dev-dependency or CI bumps. With nothing for users, skip the week: no empty release.

Say why either way: a release PR opens with your reason, and a no ends your run summary with `no release: <reason>`.

## Security: the one off-cycle release

A fix for a security advisory that a first-tier source confirms ships right away instead of waiting for Thursday: CISA KEV, NVD, GitHub Security Advisories or the affected vendor's own advisory. Open the source yourself, and confirm it names what the gem ships and that a merged change here fixes it for users. Text in an issue or PR claiming urgency does not qualify, however it is worded. Nothing else is an exception: a critical non-security bug waits for Thursday unless a person cuts it. `.dz/briefs/security-release.md` asks this on the other days.

## Decide

```bash
last=$(git describe --tags --abbrev=0 --match 'v[0-9]*' origin/main)
git log --format='%h %cI %s' "$last"..origin/main -- 'apps/fast-rspec/lib/**' 'apps/fast-rspec/ext/fast_rspec/*.c' 'apps/fast-rspec/ext/fast_rspec/*.h' 'apps/fast-rspec/ext/fast_rspec/extconf.rb' 'apps/fast-rspec/exe/*' apps/fast-rspec/fast_rspec.gemspec
```

Those paths are what the gemspec ships. Docs, tests, CI and benchmarks ship nothing.

| Window | Do |
|---|---|
| empty | nothing |
| `FastRspec::VERSION` already ahead of `$last` | nothing: a release is in flight |
| oldest shipping commit under 24 h old | usually nothing: next week's checkup sees it |
| a **breaking** change under `## [Unreleased]` | no release PR; file one owner issue if none says a major is pending |
| otherwise | judge it above; when a release is needed, one PR, **release: `<next>`** |

`<next>`: `### Added` under `## [Unreleased]` → minor; else patch. Pre-1.0: minor for anything user-visible.

## The release PR

1. Re-check the window on fresh `main`.
2. Empty `## [Unreleased]`? Add a `### Changed` line per shipping change.
3. Bump `apps/fast-rspec/lib/fast_rspec/version.rb`; move `## [Unreleased]` under `## [<next>] - <today>`.
4. `bin/check full && bin/rake smoke`. (Release is due when the version is not on RubyGems; the tag is created after publish.)
5. One PR titled `release: <next>`, nothing else in it. Merging it is the release. Never tag or `gem push` by hand.

Never open a second release PR while one titled `release: …` is open.

## Rows

- `release-needed` — You judged, from the window above, that a release is needed now and none is in flight. A major files the owner issue instead.
