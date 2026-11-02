# frozen_string_literal: true

require_relative 'lib/fast_rspec/version'

Gem::Specification.new do |spec|
  spec.name    = 'fast_rspec'
  spec.version = FastRspec::VERSION
  spec.authors = ['developerz.ai']
  spec.email   = ['admin@developerz.ai']

  spec.summary     = 'Lean drop-in RSpec + Minitest, parallel on every core, whole test stack bundled.'
  spec.description = 'One gem line replaces rspec-rails, factory_bot, faker, vcr, webmock, database_cleaner, ' \
                     'shoulda, capybara and simplecov. Parallel on every core by default (fork on CRuby, ' \
                     'threads on JRuby/TruffleRuby). Works with Rails and plain Ruby.'
  spec.homepage = 'https://github.com/developerz-ai/fast_rspec'
  spec.license  = 'MIT'
  spec.required_ruby_version = '>= 3.2.0'

  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri']   = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['bug_tracker_uri'] = "#{spec.homepage}/issues"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir['lib/fast_rspec.rb', 'lib/fast_rspec/**/*.rb', 'ext/fast_rspec/*.{c,h,rb}', 'exe/fast_rspec',
                   'LICENSE'] # README.md and CHANGELOG.md remain repo-root docs; they do not ship in the gem
  spec.bindir        = 'exe'
  spec.executables   = ['fast_rspec'] # exe/rspec joins at M2, once our RSpec runs specs
  # lib/compat (upstream require paths → ours) joins require_paths at M1, once our Minitest exists;
  # shipping it earlier would shadow the real minitest/rspec for anyone who installs a placeholder.
  spec.require_paths = ['lib']

  # C fast path on CRuby; extconf writes a no-op Makefile elsewhere → PureRuby twin.
  spec.extensions = ['ext/fast_rspec/extconf.rb']

  # Zero runtime dependencies. RSpec, Minitest and every battery (factory_bot, faker, vcr, webmock,
  # database_cleaner, shoulda, capybara, simplecov) are FastRspec's own lean implementations of
  # the upstream public API. See docs/idea/02-architecture.md.
end
