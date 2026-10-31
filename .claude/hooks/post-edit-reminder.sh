#!/usr/bin/env bash
# PostToolUse hook (Edit|Write|MultiEdit). Cheap and non-blocking: always exits 0.
# Adds a context reminder when load-bearing code is edited.
input=$(cat)
path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$path" ] && exit 0

msg=""
case "$path" in
  */ext/fast_rspec/*)
    msg="C extension edited: run 'bundle exec rake compile' before tests (stale .so otherwise). Mirror the change in lib/fast_rspec/render/pure_ruby.rb (byte-identical) and run 'FAST_RSPEC_DISABLE_EXT=1 bundle exec rake test' too. RB_GC_GUARD any VALUE whose pointer outlives a call." ;;
  */lib/fast_rspec/render/pure_ruby.rb)
    msg="PureRuby twin edited: must stay byte-identical to ext/fast_rspec. Run tests in both modes." ;;
  */lib/fast_rspec/runner/*|*/lib/fast_rspec/isolation/*)
    msg="Runner/isolation edited: check fork safety (sockets closed before fork, reconnected in child), no per-example allocation in the parent loop, and that serial (-n 1) and parallel results match on a demo app (demo/*/bin/stacks)." ;;
  */lib/fast_rspec/rspec/*|*/lib/fast_rspec/minitest/*|*/lib/fast_rspec/engine/*|*/lib/compat/*)
    msg="Drop-in surface edited: match docs/target/*.md exactly (flags, output, exit codes, seed order). Run the relevant oracle ('bin/rake test:oracles'). Any intentional difference needs a row in docs/idea/parity-divergences.md." ;;
  */lib/fast_rspec/batteries/*)
    msg="Battery edited: same public API as upstream (docs/target/), lazy-loaded, idempotent install!, user config wins. Run that battery's oracle." ;;
  */fast_rspec.gemspec)
    msg="gemspec edited: zero runtime dependencies is a hard rule (AGENTS.md)." ;;
esac
[ -z "$msg" ] && exit 0
jq -cn --arg m "$msg" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $m}}'
exit 0
