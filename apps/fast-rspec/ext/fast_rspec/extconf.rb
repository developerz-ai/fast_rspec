# frozen_string_literal: true

# Only CRuby gets the C fast path. Elsewhere write a no-op Makefile so
# `gem install` succeeds and FastRspec::PureRuby is used.
if RUBY_ENGINE == 'ruby'
  require 'mkmf'
  $CFLAGS << ' -O3 -std=c99 -Wall' # rubocop:disable Style/GlobalVars -- mkmf API
  create_makefile('fast_rspec/fast_rspec')
else
  File.write('Makefile', "all:\n\ttrue\ninstall:\n\ttrue\nclean:\n\ttrue\n")
end
