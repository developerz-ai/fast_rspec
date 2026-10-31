# Brief: is the project healthy?

Daily checkup, fired by `schedules: health` in `.dz/maintainer/maintainer.yml`. fast_rspec is
maintained so that nobody has to watch it. This covers the failures no issue or PR announces.

| Signal | Command | Healthy |
|---|---|---|
| `main` is green | `gh run list --workflow ci.yml --branch main --event push --limit 1 --json conclusion,headSha` | `success` |
| the last release published | `gh run list --workflow release.yml --limit 1 --json conclusion,displayTitle` | `success` (or no run yet) |
| RubyGems serves `FastRspec::VERSION` | `gem list fast_rspec --remote --exact` vs `lib/fast_rspec/version.rb` | equal, or a release run is in flight |
| Dependabot is not stuck | `gh pr list --app dependabot --json number,createdAt` | none older than 7 days |
| canary ran | `gh run list --workflow canary.yml --limit 1 --json conclusion,createdAt` | a run in the last 35 days (its failures are `improve`'s job) |

For each unhealthy signal, file one issue unless an open issue already names it. Title names the
signal (`main is red at <sha>`); body carries the command, its output and the run URL. A red `main`
comes first. Never delete a tag, re-run a publish or `gem push` from here.
