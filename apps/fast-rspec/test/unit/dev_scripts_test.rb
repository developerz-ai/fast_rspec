# frozen_string_literal: true

require 'test_helper'
require 'fileutils'
require 'open3'
require 'tmpdir'

class DevScriptFixtureTest < Bootstrap::Test
  private

  def executable(name)
    ENV.fetch('PATH').split(File::PATH_SEPARATOR).map { |dir| File.join(dir, name) }
       .find { |path| File.file?(path) && File.executable?(path) } || raise("missing #{name}")
  end

  def stub(directory, name, body)
    path = File.join(directory, name)
    # A stub firing outside APP_DIR means a dev script lost its cd — exit 99, loudly.
    File.write(path, "#!/usr/bin/env bash\nset -eu\n[ \"$PWD\" = \"$APP_DIR\" ] || exit 99\n#{body}\n")
    File.chmod(0o755, path)
  end

  def command_stubs(directory, label)
    stub(directory, 'bundle', <<~BASH)
      echo "#{label} bundle $*" >> "$SCRIPT_LOG"
      if [ "$*" = "$FAIL_COMMAND" ]; then exit 37; fi
    BASH
    stub(directory, 'ruby', <<~BASH)
      echo "#{label} ruby" >> "$SCRIPT_LOG"
      printf '%s' "$TEST_ENGINE"
    BASH
    stub(directory, 'gem', %(echo "#{label} gem $*" >> "$SCRIPT_LOG"))
  end

  def mise_stub(directory)
    stub(directory, 'mise', <<~'BASH')
      echo "mise $*" >> "$SCRIPT_LOG"
      if [ "mise $*" = "$FAIL_COMMAND" ]; then exit 37; fi
      if [ "$1" = env ]; then printf 'export PATH="%s:$PATH"\n' "$SELECTED_BIN"; fi
    BASH
  end

  def prepare_fixture(root, mise)
    @root = root
    system_bin, selected_bin = mirror_layout(root)
    copy_scripts(root)
    system_stubs(system_bin)
    command_stubs(system_bin, 'system')
    command_stubs(selected_bin, 'selected')
    mise_stub(system_bin) if mise
    fixture_environment(system_bin, selected_bin)
  end

  # The real scripts cd to "$(dirname "$0")/../apps/fast-rspec" — the fixture mirrors that.
  def mirror_layout(root)
    FileUtils.mkdir_p([File.join(root, 'bin'), File.join(root, 'apps/fast-rspec'),
                       File.join(root, 'system'), File.join(root, 'selected')])
    [File.join(root, 'system'), File.join(root, 'selected')]
  end

  def copy_scripts(root)
    %w[setup dev check stop rake gem-smoke].each do |name|
      FileUtils.cp(File.expand_path("../../../../bin/#{name}", __dir__), "#{root}/bin")
    end
  end

  def system_stubs(directory)
    %w[bash dirname date].each { |name| File.symlink(executable(name), File.join(directory, name)) }
    stub(directory, 'dpkg', 'exit 0')
  end

  def fixture_environment(system_bin, selected_bin)
    @environment = {
      'PATH' => system_bin, 'SELECTED_BIN' => selected_bin,
      'SCRIPT_LOG' => File.join(@root, 'commands.log'),
      'APP_DIR' => File.join(@root, 'apps/fast-rspec'),
      'TEST_ENGINE' => 'ruby', 'FAIL_COMMAND' => '',
      'BASH_ENV' => nil, 'ENV' => nil
    }
  end

  def with_fixture(mise: false, engine: 'ruby', failure: '')
    Dir.mktmpdir('dev-scripts') do |root|
      prepare_fixture(root, mise)
      @environment['TEST_ENGINE'] = engine
      @environment['FAIL_COMMAND'] = failure
      yield
    end
  end

  def run_script(name, *)
    output, status = Open3.capture2e(
      @environment, File.join(@environment.fetch('PATH'), 'bash'),
      File.join(@root, 'bin', name), *, chdir: @root
    )
    raise Bootstrap::Failure, output unless status.exited?

    [status.exitstatus, command_log]
  end

  def command_log
    log = @environment.fetch('SCRIPT_LOG')
    File.exist?(log) ? File.readlines(log, chomp: true) : []
  end
end

class SetupScriptTest < DevScriptFixtureTest
  def test_absent_mise_uses_system_ruby
    with_fixture do
      assert_equal [0, ['system bundle install', 'system ruby', 'system bundle exec rake compile']], run_script('setup')
    end
  end

  def test_mise_selects_bundle_ruby_and_rake
    with_fixture(mise: true) do
      assert_equal [0, ['mise install', 'mise env --shell bash', 'selected bundle install',
                        'selected ruby', 'selected bundle exec rake compile']], run_script('setup')
    end
  end

  def test_mise_install_failure_stops_provisioning
    with_fixture(mise: true, failure: 'mise install') do
      assert_equal [37, ['mise install']], run_script('setup')
    end
  end

  def test_mise_environment_failure_stops_provisioning
    with_fixture(mise: true, failure: 'mise env --shell bash') do
      assert_equal [37, ['mise install', 'mise env --shell bash']], run_script('setup')
    end
  end

  def test_bundle_install_failure_stops_before_compilation
    with_fixture(failure: 'install') do
      assert_equal [37, ['system bundle install']], run_script('setup')
    end
  end

  def test_compile_failure_is_propagated
    with_fixture(failure: 'exec rake compile') do
      assert_equal [37, ['system bundle install', 'system ruby', 'system bundle exec rake compile']],
                   run_script('setup')
    end
  end

  def test_alternate_engines_skip_compilation
    %w[jruby truffleruby].each do |engine|
      with_fixture(mise: true, engine: engine) do
        assert_equal [0, ['mise install', 'mise env --shell bash', 'selected bundle install',
                          'selected ruby']], run_script('setup')
      end
    end
  end
end

class DevAndStopScriptTest < DevScriptFixtureTest
  def test_dev_delegates_to_the_test_task
    with_fixture { assert_equal [0, ['system bundle exec rake test']], run_script('dev') }
  end

  def test_dev_propagates_test_failure
    with_fixture(failure: 'exec rake test') do
      assert_equal [37, ['system bundle exec rake test']], run_script('dev')
    end
  end

  def test_stop_is_an_idempotent_no_op
    with_fixture do
      2.times { assert_equal [0, []], run_script('stop') }
    end
  end
end

class CheckScriptTest < DevScriptFixtureTest
  def test_default_stages
    with_fixture do
      assert_equal [0, ['system bundle exec rubocop', 'system ruby', 'system bundle exec rake compile',
                        'system bundle exec rake test']], run_script('check')
    end
  end

  def test_default_stage_failures_are_propagated
    ['exec rubocop', 'exec rake compile', 'exec rake test'].each do |failure|
      with_fixture(failure: failure) { assert_equal 1, run_script('check').first }
    end
  end

  def test_fast_mode_skips_compilation
    with_fixture do
      assert_equal [0, ['system bundle exec rubocop', 'system bundle exec rake test']], run_script('check', 'fast')
    end
  end

  def test_alternate_engine_skips_compilation
    with_fixture(engine: 'jruby') do
      assert_equal [0, ['system bundle exec rubocop', 'system ruby', 'system bundle exec rake test']],
                   run_script('check')
    end
  end

  def test_full_mode_adds_oracles_and_apps
    with_fixture do
      assert_equal [0, ['system bundle exec rubocop', 'system ruby', 'system bundle exec rake compile',
                        'system bundle exec rake test', 'system bundle exec rake test:oracles',
                        'system bundle exec rake test:apps']], run_script('check', 'full')
    end
  end

  def test_optional_stage_failures_are_propagated
    ['exec rake test:oracles', 'exec rake test:apps'].each do |failure|
      with_fixture(failure: failure) { assert_equal 1, run_script('check', 'full').first }
    end
  end
end

class RakeScriptTest < DevScriptFixtureTest
  def test_rake_delegates_from_the_app_dir
    with_fixture { assert_equal [0, ['system bundle exec rake test:oracles']], run_script('rake', 'test:oracles') }
  end
end

class GemSmokeScriptTest < DevScriptFixtureTest
  def gem_smoke_stubs(directory)
    stub(directory, 'ls', <<~'BASH')
      while [ "${1#-}" != "$1" ]; do shift; done
      printf '%s\n' "$@"
    BASH
    stub(directory, 'head', <<~'BASH')
      IFS= read -r first
      printf '%s\n' "$first"
    BASH
    stub(directory, 'mktemp', 'echo "$PWD/.smoke-home"')
    stub(directory, 'rm', 'exit 0')
  end

  def fake_built_gem
    FileUtils.mkdir_p("#{app_dir}/pkg")
    File.write("#{app_dir}/pkg/fast_rspec-0.0.1.gem", 'stub gem archive')
  end

  def app_dir
    @environment.fetch('APP_DIR')
  end

  def test_gem_smoke_installs_the_built_gem_from_the_app_dir
    with_fixture do
      fake_built_gem
      gem_smoke_stubs(@environment.fetch('PATH'))

      assert_equal [0, ['system gem env gempath',
                        'system gem install --no-document pkg/fast_rspec-0.0.1.gem',
                        'system ruby']], run_script('gem-smoke')
    end
  end
end
