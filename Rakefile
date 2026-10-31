# frozen_string_literal: true

require 'bundler/gem_tasks'

if RUBY_ENGINE == 'ruby'
  require 'rake/extensiontask'
  Rake::ExtensionTask.new('fast_rspec') { |ext| ext.lib_dir = 'lib/fast_rspec' }
end

desc 'Own suite (bootstrap harness until our Minitest runs it — roadmap M1)'
task :test do
  ruby '-Itest', '-e', "require 'test_helper'; Bootstrap.run(Dir['test/unit/**/*_test.rb'].sort)"
end

namespace :test do
  desc 'Run upstream suites (rspec-core, minitest, factory_bot, …) against FastRspec'
  task :oracles do
    abort 'test:oracles: not implemented yet — see docs/idea/09-compat-oracles.md'
  end

  desc 'Run the sample apps (rails_rspec, rails_minitest, plain_ruby)'
  task :apps do
    abort 'test:apps: not implemented yet — see docs/idea/10-testing-ci.md'
  end
end

desc 'Benchmarks vs our own past self'
task :bench do
  abort 'bench: not implemented yet — see docs/idea/08-performance.md'
end

desc 'Build the gem, install into a temp GEM_HOME, require it without Rails'
task smoke: :build do
  sh 'bin/gem-smoke'
end

task default: :test
