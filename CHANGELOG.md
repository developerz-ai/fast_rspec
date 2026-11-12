# Changelog

## [Unreleased]

## [0.1.0] - 2026-11-12

- Project skeleton: gemspec, C ext + pure-Ruby twin stubs, docs/idea design set, docs/target compat specs, agent setup (.claude, .dz maintainer, CI OK gate, release-on-version-bump).

### Changed

- Drop README.md and CHANGELOG.md from the packaged gem files; they remain repo-root docs (b8184fe).
- Fix Ruby 3.2 compilation of the native C extension by including `<stdbool.h>` before `<ruby.h>` (d5ad9f3).
- Reframe README.md, llms.txt and the gemspec summary/description as design-phase target contracts; drop unmeasured performance claims and references to env knobs that do not exist yet (b132352).
