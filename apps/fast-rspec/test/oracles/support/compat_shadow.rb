# frozen_string_literal: true

# RUBYOPT requires run before any suite code. `bundle exec` prepends its own
# `-rbundler/setup` to RUBYOPT (Bundler::SharedHelpers#set_rubyopt unshifts
# it), so the suite process has the bundle activated before this file loads -
# but the `bundle` process itself inherits our RUBYOPT unchanged and loads
# this shim first. Activating the bundle here covers both processes: the gem
# paths are on $LOAD_PATH before the unshift below, so lib/compat stays ahead
# of upstream and `require 'fast_rspec'` resolves against the activated
# bundle.
require 'bundler/setup'

compat_dir = File.expand_path('../../../lib/compat', __dir__)
$LOAD_PATH.unshift(compat_dir) unless $LOAD_PATH.include?(compat_dir)
require 'fast_rspec'
