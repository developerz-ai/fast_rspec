# frozen_string_literal: true

# RUBYOPT requires run before any suite code, and `bundle exec` injects its own
# `-rbundler/setup` ahead of ours — by the time this loads, gem paths are already
# on $LOAD_PATH, so only an unshift here keeps lib/compat ahead of upstream.
compat_dir = File.expand_path('../../../lib/compat', __dir__)
$LOAD_PATH.unshift(compat_dir) unless $LOAD_PATH.include?(compat_dir)
require 'fast_rspec'
