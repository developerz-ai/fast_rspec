---
description: Write a concise, self-contained plan to docs/plans/<YYYY>/<MM>/<DD>/<1NN>-<slug>/ for another AI to execute
argument-hint: [the feature or change you want planned]
allowed-tools: Write, Read, Glob, Grep, Agent, Bash
---

# /planx

Plan only — no code outside the plan dir. The executor should need nothing but the plan and the files it cites.

## Goal
$ARGUMENTS

## Steps

1. **Resolve path.** `date +%Y`, `+%m`, `+%d`. `Glob docs/plans/<YYYY>/<MM>/<DD>/1*` → next `1NN` (else `101`). Slug: kebab-case, ≤5 words.
2. **Explore.** Explore agent (very thorough): affected layers (see `AGENTS.md`), upstream surface in `docs/target/*.md`, existing code `file:line`, oracles + sample apps that prove it, C ext / PureRuby impact, engines affected. No worktrees.
3. **Write files.** Always `overview.md` + one `<NN>-<aspect>.md` per PR-sized slice. Never one big `plan.md`.

   `overview.md`: `## Goal` (1–2 lines) · `## Context` (layers, target docs, pillars at risk) · `## Plan files (execute in order)` · `## Done when` (bin/check green, oracles green, engines green, bench delta recorded) · `## Risks / open questions`.

   Each slice: `## Files to change` · `## Steps` · `## Tests` (unit + oracle + sample app) · `## Compat` (which upstream surface; what must stay identical) · `## Perf` (expected effect, how measured) · `## Done when`.

4. **`status.yml`:**
```yaml
plan: <1NN>-<slug>
title: <title>
status: not_started   # not_started | in_progress | blocked | complete | superseded
owner: <git config user.name>
percent: 0
slices:
  - file: 01-<aspect>.md
    status: not_started
evidence: []
last_updated: <YYYY-MM-DD>
```

## Rules
- House style: rule first, fragments, tables, no meta-framing. Reference, don't restate.
- No checkboxes; `status.yml` is the only tracker.
- Parallel slices = disjoint file sets, one checkout, never worktrees.
- Every slice preserves the three pillars; a slice that can't → stop and flag in Risks.

## Output
```
✓ docs/plans/<YYYY>/<MM>/<DD>/<1NN>-<slug>/overview.md + 0N slices + status.yml
Next: /feature docs/plans/.../overview.md
```
