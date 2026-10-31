# Brief: are we still drop-in?

Weekly checkup, fired by `schedules: compat`. Drop-in is pillar 1; upstream moves every week.

1. For each gem in `fast_rspec.gemspec` and `docs/target/*.md`: `gem list <name> --remote --exact` vs the version the target doc is dated against.
2. A new upstream minor/major → read its CHANGELOG for changes to the surface in the target doc.
3. Surface changed → update `docs/target/<file>.md` first, then open one issue per change (`compat` label) with the upstream link and the doc diff.
4. Oracles (`bin/rake test:oracles`) still pinned to a SHA older than the latest release → one PR bumping the pin; it merges only on green.

No change upstream → do nothing.
