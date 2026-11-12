# frozen_string_literal: true

require 'test_helper'
require 'fileutils'
require 'json'
require 'stringio'
require 'tmpdir'
require_relative '../oracles/support/runner'

# Offline coverage for the oracle runner: fake oracle dirs with `local <path>`
# pins, stub bundle/version-control scripts on PATH, and the real
# spawn/timeout/classification machinery in between. One file, several small
# classes, so each stays under the Metrics class budget.

module OracleScripts
  SHA = '819e9b5f873d7ab6d4edfeaed48542279367ff93'
  ALT_SHA = '555979f5bae76e83a52f166dd7060daf504c6177'

  PASS_SCRIPT = <<~SH
    #!/bin/sh
    echo "ORACLE RESULT pass=3 fail=0 skip=0"
  SH
  FAIL_SCRIPT = <<~SH
    #!/bin/sh
    echo "ORACLE RESULT pass=1 fail=2 skip=1"
  SH
  CRASH_SCRIPT = <<~SH
    #!/bin/sh
    echo "upstream boom" >&2
    exit 1
  SH
  HANG_SCRIPT = <<~SH
    #!/bin/sh
    sleep 30
  SH
  ENV_SCRIPT = <<~SH
    #!/bin/sh
    {
      echo "RUBYOPT=$RUBYOPT"
      echo "ORACLE_SRC=$ORACLE_SRC"
      echo "ORACLE_NAME=$ORACLE_NAME"
      echo "FAST_RSPEC_ROOT=$FAST_RSPEC_ROOT"
      echo "BUNDLE_GEMFILE=$BUNDLE_GEMFILE"
    } > "$RUN_ENV_LOG"
    echo "ORACLE RESULT pass=1 fail=0 skip=0"
  SH
  BUNDLE_STUB = <<~SH
    #!/bin/sh
    printf '%s\n' "bundle $* BUNDLE_GEMFILE=$BUNDLE_GEMFILE" >> "$STUB_LOG"
    exit "${STUB_EXIT:-0}"
  SH
  # Fakes a checkout: init stamps GIT_REV as the checked-out HEAD, rev-parse
  # reads it back; every invocation is logged so tests can assert call counts.
  SCM_STUB = <<~SH
    #!/bin/sh
    printf '%s\\n' "scm $*" >> "$GIT_LOG"
    if [ "$1" = "-C" ]; then dir="$2"; shift 2; else dir="."; fi
    case "$1" in
      init) target="${3:-$dir}"; mkdir -p "$target/.git"; echo "$GIT_REV" > "$target/.git/HEAD" ;;
      rev-parse) [ -f "$dir/.git/HEAD" ] && cat "$dir/.git/HEAD" ;;
    esac
    exit "${GIT_EXIT:-0}"
  SH
  SKIP_TXT = <<~TXT
    # <id> <reason> (<issue url>)
    alpha:run frontends unimplemented (https://example.com/issue/42)
  TXT
end

class OracleFixtureTest < Bootstrap::Test
  include OracleScripts

  private

  # The bootstrap harness ships only assert/assert_equal/assert_includes/
  # refute_nil; these are its complements, same primitive style.
  def refute(cond, msg = 'expected falsy') = cond && raise(Bootstrap::Failure, msg)

  def refute_includes(collection, obj)
    return unless collection.include?(obj)

    raise Bootstrap::Failure, "expected #{obj.inspect} to be absent"
  end

  def assert_predicate(obj, predicate, msg = 'expected predicate to hold')
    assert(obj.public_send(predicate), msg)
  end

  def refute_predicate(obj, predicate, msg = 'expected predicate to fail')
    refute(obj.public_send(predicate), msg)
  end

  def refute_path_exists(path, msg = 'expected no file at path')
    File.exist?(path) && raise(Bootstrap::Failure, msg)
  end

  def pin_error(dir)
    Oracles::Pin.read(dir)
    nil
  rescue RuntimeError => e
    e
  end

  def local_pin(root, name)
    dir = File.join(root, 'src', name)
    FileUtils.mkdir_p(dir)
    "local #{dir}\n"
  end

  def build_oracle(root, name, sha:, run:, skip_txt: "# no documented skips\n")
    dir = File.join(root, 'test', 'oracles', name)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, '.sha'), sha)
    File.write(File.join(dir, 'Gemfile'), "# frozen_string_literal: true\nsource 'https://rubygems.org'\n")
    File.write(File.join(dir, 'run'), run)
    File.chmod(0o700, File.join(dir, 'run'))
    File.write(File.join(dir, 'skip.txt'), skip_txt)
    dir
  end

  # Returns [exit-status, parsed results.json rows, runner output].
  def run_runner(root, filter: nil, env: {}, bundle: BUNDLE_STUB)
    stubs = File.join(root, 'bin')
    FileUtils.mkdir_p(stubs)
    write_stub(stubs, 'bundle', bundle)
    write_stub(stubs, 'git', SCM_STUB)
    io = StringIO.new
    runner = Oracles::Runner.new(root, env: base_env(root, stubs).merge(env), io: io)
    status = runner.run(filter)
    rows = JSON.parse(File.read(File.join(root, 'tmp', 'oracles', 'results.json')))
    [status, rows, io.string]
  end

  def write_stub(dir, name, body)
    path = File.join(dir, name)
    File.write(path, body)
    File.chmod(0o700, path)
  end

  def base_env(root, stubs)
    {
      'PATH' => "#{stubs}:/usr/bin:/bin",
      'HOME' => root,
      'GIT_LOG' => File.join(root, 'git.log'),
      'STUB_LOG' => File.join(root, 'bundle.log'),
      'ORACLE_TIMEOUT' => '10'
    }
  end

  def fetch_count(root)
    File.readlines(File.join(root, 'git.log'), chomp: true).grep(/scm .*fetch/).size
  end

  def silence_stderr
    old = $stderr
    $stderr = StringIO.new
    yield
  ensure
    $stderr = old
  end
end

class OraclePinTest < OracleFixtureTest
  def test_pin_parses_sha_tag_and_comments
    Dir.mktmpdir do |root|
      dir = build_oracle(root, 'minitest', sha: "# fetched this run\n#{SHA}\ntag v5.27.0\n", run: PASS_SCRIPT)

      pin = Oracles::Pin.read(dir)

      assert_equal SHA, pin.sha
      assert_equal 'v5.27.0', pin.tag
      refute_predicate(pin, :local?, 'a 40-hex pin is not local')
    end
  end

  def test_local_pins_parse_with_no_tag
    Dir.mktmpdir do |root|
      pin = Oracles::Pin.read(build_oracle(root, 'fake', sha: "local #{root}\n", run: PASS_SCRIPT))

      assert_predicate(pin, :local?, 'a local line must parse as local')
      assert_equal root, pin.sha
      refute(pin.tag, 'local pins carry no tag')
    end
  end

  def test_untagged_pins_parse_the_commit_only
    Dir.mktmpdir do |root|
      pin = Oracles::Pin.read(build_oracle(root, 'webmock', sha: "#{ALT_SHA}\n", run: PASS_SCRIPT))

      assert_equal ALT_SHA, pin.sha
      refute(pin.tag, 'untagged pins parse with no tag')
    end
  end

  def test_pin_rejects_malformed_sha_files
    Dir.mktmpdir do |root|
      ['abc', "#{SHA}\noops", "#{SHA}\ntag v1\nextra", ''].each do |sha|
        dir = build_oracle(root, 'broken', sha: "#{sha}\n", run: PASS_SCRIPT)

        assert pin_error(dir), ".sha #{sha.inspect} must be rejected"
      end
    end
  end

  def test_discovers_oracle_dirs_and_excludes_support
    Dir.mktmpdir do |root|
      build_oracle(root, 'alpha', sha: local_pin(root, 'alpha'), run: PASS_SCRIPT)
      build_oracle(root, 'beta', sha: local_pin(root, 'beta'), run: PASS_SCRIPT)
      support = File.join(root, 'test', 'oracles', 'support')
      FileUtils.mkdir_p(support)
      File.write(File.join(support, 'runner.rb'), "# support, not an oracle\n")

      _status, rows, _output = run_runner(root)

      assert_equal(%w[alpha beta], rows.map { |row| row['name'] })
    end
  end

  def test_oracle_filter_runs_exactly_one
    Dir.mktmpdir do |root|
      build_oracle(root, 'alpha', sha: local_pin(root, 'alpha'), run: PASS_SCRIPT)
      build_oracle(root, 'beta', sha: local_pin(root, 'beta'), run: PASS_SCRIPT)

      status, rows, _output = run_runner(root, filter: 'beta')

      assert_equal 0, status
      assert_equal(%w[beta], rows.map { |row| row['name'] })
    end
  end

  def test_unknown_oracle_filter_aborts
    Dir.mktmpdir do |root|
      build_oracle(root, 'alpha', sha: local_pin(root, 'alpha'), run: PASS_SCRIPT)

      exited = silence_stderr do
        run_runner(root, filter: 'nope')
        false
      rescue SystemExit
        true
      end

      assert exited, 'unknown ORACLE filter must abort'
    end
  end
end

class OracleGuardsTest < OracleFixtureTest
  def test_missing_required_file_aborts
    Oracles::Runner::FILES.each do |file|
      Dir.mktmpdir do |root|
        dir = build_oracle(root, 'alpha', sha: local_pin(root, 'alpha'), run: PASS_SCRIPT)
        File.delete(File.join(dir, file))

        stderr = aborting_run(root)

        assert_includes stderr, "test/oracles/alpha/#{file} is missing"
      end
    end
  end

  def test_non_executable_run_script_aborts
    Dir.mktmpdir do |root|
      dir = build_oracle(root, 'alpha', sha: local_pin(root, 'alpha'), run: PASS_SCRIPT)
      File.chmod(0o600, File.join(dir, 'run'))

      stderr = aborting_run(root)

      assert_includes stderr, 'test/oracles/alpha/run is not executable'
    end
  end

  def test_invalid_oracle_timeout_raises_argument_error
    Dir.mktmpdir do |root|
      # 'soon' trips the ArgumentError rescue, nil the TypeError one: one contract.
      ['soon', nil].each do |timeout|
        assert_raise(ArgumentError, 'ORACLE_TIMEOUT must be an integer number of seconds') do
          Oracles::Runner.new(root, env: { 'ORACLE_TIMEOUT' => timeout })
        end
      end
    end
  end

  private

  def assert_raise(klass, message = nil)
    yield
  rescue klass => e
    assert_includes e.message, message if message
    e
  else
    raise Bootstrap::Failure, "expected #{klass} to be raised"
  end

  # Runs the runner expecting a setup abort; returns the stderr it died with.
  def aborting_run(root)
    silence_stderr do
      run_runner(root)
      raise Bootstrap::Failure, 'expected the runner to abort with SystemExit'
    rescue SystemExit
      $stderr.string
    end
  end
end

class OraclesRunnerTest < OracleFixtureTest
  def test_classification_matrix_pass_fail_and_crash_skip
    Dir.mktmpdir do |root|
      build_oracle(root, 'alpha', sha: local_pin(root, 'alpha'), run: PASS_SCRIPT)
      build_oracle(root, 'beta', sha: local_pin(root, 'beta'), run: FAIL_SCRIPT)
      build_oracle(root, 'gamma', sha: local_pin(root, 'gamma'), run: CRASH_SCRIPT)

      status, rows, _output = run_runner(root)
      by_name = rows.to_h { |row| [row['name'], row] }

      assert_matrix(by_name, status)
    end
  end

  def assert_matrix(by_name, status)
    assert_equal 1, status
    assert_pass_row(by_name.fetch('alpha'))
    assert_fail_row(by_name.fetch('beta'))
    assert_crash_row(by_name.fetch('gamma'))
  end

  def assert_pass_row(row)
    assert_equal 'pass', row['verdict']
    assert_equal 100, row['pct']
    refute(row['reason'], 'a passing row has no reason')
  end

  def assert_fail_row(row)
    assert_equal 'fail', row['verdict']
    assert_equal 25, row['pct']
    assert_equal '2 failure(s)', row['reason']
  end

  def assert_crash_row(row)
    assert_equal 'skip', row['verdict']
    assert_includes row['reason'], 'no ORACLE RESULT after exit 1'
    assert_includes row['reason'], 'upstream boom'
  end

  def test_skips_never_gate_the_exit_status
    Dir.mktmpdir do |root|
      build_oracle(root, 'gamma', sha: local_pin(root, 'gamma'), run: CRASH_SCRIPT)

      status, rows, _output = run_runner(root)

      assert_equal 0, status
      assert_equal 'skip', rows[0]['verdict']
    end
  end

  def test_fetch_failure_skips_and_falls_back_to_the_tag_ref
    Dir.mktmpdir do |root|
      build_oracle(root, 'minitest', sha: "#{SHA}\ntag v5.27.0\n", run: PASS_SCRIPT)

      status, rows, _output = run_runner(root, env: { 'GIT_EXIT' => '1' })
      row = rows[0]

      assert_equal 0, status
      assert_equal 'skip', row['verdict']
      assert_tag_fallback(root, row)
    end
  end

  def assert_tag_fallback(root, row)
    reason = row['reason']

    assert_includes reason, 'fetch failed'
    assert_includes reason, SHA
    assert_includes reason, 'tag v5.27.0'
    fetches = File.readlines(File.join(root, 'git.log'), chomp: true).grep(/scm .*fetch/)

    assert_equal 2, fetches.size
    assert_includes fetches[0], SHA
    assert_includes fetches[1], 'refs/tags/v5.27.0'
  end

  def test_fetched_head_mismatching_the_pin_skips
    Dir.mktmpdir do |root|
      build_oracle(root, 'minitest', sha: "#{SHA}\n", run: PASS_SCRIPT)

      status, rows, _output = run_runner(root, env: { 'GIT_REV' => ALT_SHA })

      assert_equal 0, status
      assert_equal 'skip', rows[0]['verdict']
      assert_includes rows[0]['reason'], "fetched HEAD #{ALT_SHA} does not match pin #{SHA}"
    end
  end
end

class OracleLifecycleTest < OracleFixtureTest
  def test_bundle_install_failure_skips
    Dir.mktmpdir do |root|
      build_oracle(root, 'faker', sha: local_pin(root, 'faker'), run: PASS_SCRIPT)

      status, rows, _output = run_runner(root, env: { 'STUB_EXIT' => '3' })

      assert_equal 0, status
      assert_equal 'skip', rows[0]['verdict']
      assert_install_skip(root, rows[0])
    end
  end

  def assert_install_skip(root, row)
    assert_includes row['reason'], 'bundle install failed (exit 3)'
    overlay = File.join(root, 'test', 'oracles', 'faker', 'Gemfile')

    assert_includes File.read(File.join(root, 'bundle.log')), overlay
  end

  def test_timeout_expires_the_suite_and_skips
    Dir.mktmpdir do |root|
      build_oracle(root, 'vcr', sha: local_pin(root, 'vcr'), run: HANG_SCRIPT)

      status, rows, _output = run_runner(root, env: { 'ORACLE_TIMEOUT' => '1' })

      assert_equal 0, status
      assert_equal 'skip', rows[0]['verdict']
      assert_includes rows[0]['reason'], 'timed out after 1s'
    end
  end

  def test_cached_checkout_is_reused_and_stale_pins_are_refetched
    Dir.mktmpdir do |root|
      build_oracle(root, 'minitest', sha: "#{SHA}\n", run: PASS_SCRIPT)
      run_runner(root, env: { 'GIT_REV' => SHA })
      run_runner(root, env: { 'GIT_REV' => SHA })

      assert_cache_reuse(root)
    end
  end

  def assert_cache_reuse(root)
    sha_path = File.join(root, 'test', 'oracles', 'minitest', '.sha')

    assert_equal 1, fetch_count(root)

    File.write(sha_path, "#{ALT_SHA}\n")
    run_runner(root, env: { 'GIT_REV' => ALT_SHA })

    assert_equal 2, fetch_count(root)
  end

  def test_local_pin_bypasses_version_control_entirely
    Dir.mktmpdir do |root|
      build_oracle(root, 'faker', sha: local_pin(root, 'faker'), run: PASS_SCRIPT)

      status, rows, _output = run_runner(root, env: { 'GIT_EXIT' => '127' })
      log = File.join(root, 'git.log')

      assert_equal 0, status
      assert_equal 'pass', rows[0]['verdict']
      refute_path_exists(log, 'local pins must not invoke the scm stub')
    end
  end

  def test_bundle_install_timeout_skips
    Dir.mktmpdir do |root|
      build_oracle(root, 'faker', sha: local_pin(root, 'faker'), run: PASS_SCRIPT)

      status, rows, _output = run_runner(root, env: { 'ORACLE_TIMEOUT' => '1' }, bundle: HANG_SCRIPT)
      log = File.join(root, 'tmp', 'oracles', 'faker-install.log')

      assert_equal 0, status
      assert_equal 'skip', rows[0]['verdict']
      assert_includes rows[0]['reason'], "bundle install timed out after 1s (#{log})"
    end
  end

  def test_local_pin_missing_directory_skips_the_fetch
    Dir.mktmpdir do |root|
      build_oracle(root, 'faker', sha: "local #{File.join(root, 'src', 'ghost')}\n", run: PASS_SCRIPT)

      status, rows, _output = run_runner(root, env: { 'GIT_EXIT' => '127' })

      assert_equal 0, status
      assert_equal 'skip', rows[0]['verdict']
      assert_broken_local_pin(rows[0], root)
    end
  end

  def assert_broken_local_pin(row, root)
    assert_includes row['reason'], "local pin #{row['pin']} is not a directory"
    refute_path_exists(File.join(root, 'git.log'), 'broken local pins must not invoke the scm stub')
  end
end

class OracleResultsTest < OracleFixtureTest
  def test_run_script_receives_contract_env_and_rubyopt_prefix
    Dir.mktmpdir do |root|
      env_log = File.join(root, 'run-env.log')
      build_oracle(root, 'minitest', sha: "#{SHA}\ntag v5.27.0\n", run: ENV_SCRIPT)

      _status, rows, _output = run_runner(root, env: { 'RUN_ENV_LOG' => env_log, 'GIT_REV' => SHA })

      assert_equal 'pass', rows[0]['verdict']
      lines = File.readlines(env_log, chomp: true).to_h { |line| line.split('=', 2) }

      assert_contract_env(lines, root)
    end
  end

  def assert_contract_env(lines, root)
    assert_equal Oracles::RUBYOPT_PREFIX, lines.fetch('RUBYOPT')
    assert_equal File.join(root, 'tmp', 'oracles', 'minitest'), lines.fetch('ORACLE_SRC')
    assert_equal 'minitest', lines.fetch('ORACLE_NAME')
    assert_equal File.expand_path(root), lines.fetch('FAST_RSPEC_ROOT')
    assert_equal File.join(root, 'test', 'oracles', 'minitest', 'Gemfile'), lines.fetch('BUNDLE_GEMFILE')
  end

  def test_skip_txt_entries_merge_into_matching_rows_only
    Dir.mktmpdir do |root|
      build_oracle(root, 'alpha', sha: local_pin(root, 'alpha'), run: CRASH_SCRIPT, skip_txt: SKIP_TXT)
      build_oracle(root, 'beta', sha: local_pin(root, 'beta'), run: CRASH_SCRIPT)

      _status, rows, _output = run_runner(root)

      assert_skip_txt_merged(rows.to_h { |row| [row['name'], row] })
    end
  end

  def assert_skip_txt_merged(by_name)
    assert_includes by_name.fetch('alpha')['reason'], 'frontends unimplemented'
    assert_includes by_name.fetch('alpha')['reason'], 'https://example.com/issue/42'
    refute_includes(by_name.fetch('beta')['reason'], 'example.com')
  end

  def test_results_json_mirrors_the_docs_compat_columns
    Dir.mktmpdir do |root|
      build_oracle(root, 'alpha', sha: local_pin(root, 'alpha'), run: PASS_SCRIPT)

      status, rows, output = run_runner(root)

      assert_equal 0, status
      assert_row_shape(rows[0], root)
      assert_includes output, 'suites →'
    end
  end

  def assert_row_shape(row, root)
    assert_equal %w[name pin pass fail skip pct verdict reason], row.keys
    assert_equal expected_row(root), row
  end

  def expected_row(root)
    {
      'name' => 'alpha',
      'pin' => File.join(root, 'src', 'alpha'),
      'pass' => 3,
      'fail' => 0,
      'skip' => 0,
      'pct' => 100,
      'verdict' => 'pass',
      'reason' => nil
    }
  end
end
