# frozen_string_literal: true

require 'test_helper'
require 'open3'
require 'tmpdir'

class CheckTest < Bootstrap::Test
  SCRIPT = File.expand_path('../../bin/check', __dir__).freeze
  DEFAULT_COMMANDS = [
    'exec rubocop|',
    'exec rake compile|',
    'exec rake test|',
    'exec rake test|1',
    'exec rake smoke|'
  ].freeze
  FULL_COMMANDS = (DEFAULT_COMMANDS + ['exec rake test:oracles|', 'exec rake test:apps|']).freeze
  PORTABLE_COMMANDS = ['exec rubocop|', 'exec rake test|', 'exec rake smoke|'].freeze
  BUNDLE_STUB = <<~'SH'
    #!/bin/sh
    command="$*|${FAST_RSPEC_DISABLE_EXT-}"
    printf '%s\n' "$command" >> "$CHECK_LOG"
    [ "$command" != "$CHECK_FAIL" ]
  SH
  RUBY_STUB = <<~SH
    #!/bin/sh
    [ "$#" -eq 2 ] && [ "$1" = '-e' ] && [ "$2" = 'print RUBY_ENGINE' ] || exit 64
    printf '%s' "$CHECK_ENGINE"
  SH

  def test_default_runs_all_cruby_gates_in_order
    commands, output, status = run_check

    assert_success(commands, output, status, DEFAULT_COMMANDS)
  end

  def test_non_cruby_skips_native_and_redundant_pure_ruby_stages
    %w[jruby truffleruby].each do |engine|
      commands, output, status = run_check(engine: engine)

      assert_success(commands, output, status, PORTABLE_COMMANDS)
    end
  end

  def test_fast_is_only_lint_and_unit_on_every_engine
    %w[ruby jruby truffleruby].each do |engine|
      commands, output, status = run_check('fast', engine: engine)

      assert_success(commands, output, status, ['exec rubocop|', 'exec rake test|'])
    end
  end

  def test_full_adds_oracles_and_apps_after_required_gates
    commands, output, status = run_check('full')

    assert_success(commands, output, status, FULL_COMMANDS)
  end

  def test_full_on_non_cruby_keeps_portable_gates_and_extras
    %w[jruby truffleruby].each do |engine|
      commands, output, status = run_check('full', engine: engine)
      expected = PORTABLE_COMMANDS + ['exec rake test:oracles|', 'exec rake test:apps|']

      assert_success(commands, output, status, expected)
    end
  end

  def test_each_default_failure_is_reported_without_skipping_later_gates
    DEFAULT_COMMANDS.each_with_index do |command, index|
      assert_stage_failure(nil, command, index, DEFAULT_COMMANDS)
    end
  end

  def test_each_full_failure_is_reported_without_skipping_later_gates
    FULL_COMMANDS.each_with_index do |command, index|
      assert_stage_failure('full', command, index, FULL_COMMANDS)
    end
  end

  private

  def assert_success(commands, output, status, expected)
    assert_equal expected, commands
    assert_equal 0, status.exitstatus
    assert_includes output, '✓ all green'
  end

  def assert_stage_failure(mode, command, index, expected)
    commands, output, status = run_check(mode, failure: command)
    stages = output.scan(/^==> (.+)$/).flatten

    assert_equal expected, commands
    assert_equal expected.size, stages.size
    assert_equal 1, status.exitstatus
    assert_includes output, "✗ failed: #{stages.fetch(index)}\n"
  end

  def run_check(mode = nil, engine: 'ruby', failure: '')
    Dir.mktmpdir('check-test-') do |dir|
      write_stub(dir, 'bundle', BUNDLE_STUB)
      write_stub(dir, 'ruby', RUBY_STUB)
      env = check_environment(dir, engine, failure)
      output, status = Open3.capture2e(env, 'bash', SCRIPT, *[mode].compact,
                                       chdir: dir, unsetenv_others: true)
      [File.readlines(env.fetch('CHECK_LOG'), chomp: true), output, status]
    end
  end

  def check_environment(dir, engine, failure)
    {
      'PATH' => "#{dir}:/usr/bin:/bin",
      'TMPDIR' => dir,
      'HOME' => dir,
      'CHECK_LOG' => File.join(dir, 'commands.log'),
      'CHECK_ENGINE' => engine,
      'CHECK_FAIL' => failure
    }
  end

  def write_stub(dir, name, body)
    path = File.join(dir, name)
    File.write(path, body)
    File.chmod(0o700, path)
  end
end
