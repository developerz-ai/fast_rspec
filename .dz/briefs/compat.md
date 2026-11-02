# Brief: are we still drop-in?

Weekly checkup, fired by `schedules: compat`. Drop-in is pillar 1; upstream moves every week.

1. For each gem in `fast_rspec.gemspec` and `docs/target/*.md`: `gem list <name> --remote --exact` vs the version the target doc is dated against.
2. A new upstream minor/major → read its CHANGELOG for changes to the surface in the target doc.
3. Surface changed → update `docs/target/<file>.md` first, then open one issue per change (`compat` label) with the upstream link and the doc diff.
4. Oracles (`bin/rake test:oracles`) still pinned to a SHA older than the latest release → one PR bumping the pin; it merges only on green.
5. Run `bin/rake test:oracles`. If verification cannot run — a missing launcher, an existing launcher with an unimplemented oracle task, or another execution blocker — report an explicit **blocked/unavailable** finding with the command, reason (including exact error output when available), and scope left unverified. Launcher existence alone does not establish availability.

Report upstream release/version and pin observations separately from oracle execution outcomes. Describe an oracle as **passed** only after a completed successful run, identifying the scope it verified. Failed or incomplete runs are not passes; report their errors and unverified scope.

No change upstream → do nothing only when supported by completed upstream checks and no blocked/unavailable oracle finding remains to report. Unavailable verification is never evidence of no upstream change and never permits an overall “no change upstream” conclusion; report the blocker even if independent release/version and pin observations show no changes.
