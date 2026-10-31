# STACK=upstream (default) | fast_rspec picks gemfiles/<stack>.gemfile, each with its own lockfile.
# An explicit BUNDLE_GEMFILE wins.
ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../gemfiles/#{ENV.fetch('STACK', 'upstream')}.gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.
