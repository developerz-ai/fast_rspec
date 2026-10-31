## What & why

<!-- One or two sentences. Link issues: Fixes #123 -->

## Changes

-

## Checklist

- [ ] `bin/check` passes (`full` if runner, adapters or batteries changed)
- [ ] Drop-in: no user file needs editing; flags, output, exit codes unchanged (or listed in `docs/idea/parity-divergences.md`)
- [ ] Serial and parallel runs give the same results on the demo apps
- [ ] C change mirrored in `lib/fast_rspec/render/pure_ruby.rb` (parity test passes)
- [ ] CRuby, JRuby, TruffleRuby green
- [ ] `CHANGELOG.md` `## [Unreleased]` updated for user-visible changes
- [ ] `AGENTS.md` / `README.md` / `docs/` updated if commands or behavior changed

## Performance (if relevant)

<!-- Before/after from `bin/rake bench`, same machine. Include `ruby -v` (YJIT?) and worker count. -->

| Suite | Before (s) | After (s) | Ratio |
|---|---|---|---|
