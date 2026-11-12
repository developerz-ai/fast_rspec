# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'

module Oracles
  SUPPORT_DIR = __dir__
  # Preamble handed to every suite process via RUBYOPT: support/compat_shadow.rb
  # unshifts lib/compat onto $LOAD_PATH so our require paths shadow upstream.
  RUBYOPT_PREFIX = "-I#{SUPPORT_DIR} -rcompat_shadow".freeze

  # One row per oracle suite, mirroring the docs/compat.md columns (Pinned/Pass/Skip/%).
  Row = Struct.new(:name, :pin, :pass, :fail, :skip, :pct, :verdict, :reason, keyword_init: true)

  # test/oracles/<name>/.sha — the first entry is the pinned 40-hex upstream
  # commit (or `local <path>` to bypass version control entirely), an optional
  # `tag <ref>` line is the fetch fallback, `# `-lines are comments.
  class Pin
    SHA_PATTERN = /\A[0-9a-f]{40}\z/
    TAG_PATTERN = /\Atag (.+)\z/
    LOCAL_PATTERN = /\Alocal (.+)\z/

    attr_reader :sha, :tag

    def self.read(dir)
      lines = File.readlines(File.join(dir, '.sha'), chomp: true).map(&:strip)
      new(*parse(lines.reject { |line| line.empty? || line.start_with?('#') }))
    end

    def self.parse(entries)
      first = entries.first
      raise 'no pin line found' unless first

      local = first[LOCAL_PATTERN, 1]
      return [local, nil, true] if local

      raise "#{first.inspect} is not a 40-hex commit or `local <path>`" unless first.match?(SHA_PATTERN)
      raise "unexpected extra entry #{entries[2].inspect}" if entries[2]
      return [first, nil, false] unless entries[1]

      tagged(first, entries[1])
    end

    def self.tagged(first, fallback)
      ref = fallback[TAG_PATTERN, 1]
      raise "expected `tag <ref>` fallback, got #{fallback.inspect}" unless ref

      [first, ref, false]
    end

    def initialize(sha, tag, local)
      @sha = sha
      @tag = tag
      @local = local
    end

    def local? = @local
  end

  # Process plumbing: bounded spawns (the whole process group dies on timeout)
  # and captured subprocess output for the fetch steps.
  module Shell
    module_function

    # Runs cmd with stdout+stderr streamed into log; returns Process::Status,
    # or :timeout once the deadline passes.
    def run(env, cmd, chdir:, log:, timeout:)
      FileUtils.mkdir_p(File.dirname(log))
      File.open(log, 'w') do |io|
        pid = Process.spawn(env, *cmd, chdir: chdir, pgroup: true, in: '/dev/null', out: io, err: io)
        await(pid, timeout)
      end
    end

    def await(pid, timeout)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      loop do
        _pid, status = Process.waitpid2(pid, Process::WNOHANG)
        return status if status

        if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          kill_group(pid)
          return :timeout
        end
        sleep(0.2)
      end
    end

    def kill_group(pid)
      Process.kill('KILL', -pid)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    ensure
      begin
        Process.waitpid2(pid)
      rescue Errno::ECHILD
        nil
      end
    end

    # Captures a subprocess; returns [success?, combined stdout+stderr, stripped].
    def capture(env, cmd)
      out, err, status = Open3.capture3(env, *cmd)
      [status.success?, "#{err}#{out}".strip]
    end

    def tail(path, limit = 200)
      File.readlines(path, chomp: true).reverse_each.find { |line| !line.empty? }.to_s[0, limit]
    end

    def clip(text, limit = 200) = text.to_s[0, limit]
  end

  # Acquires the pinned upstream checkout: a `local <path>` pin is used as-is,
  # anything else is fetched from the pin's remote (tag fallback) into
  # tmp/oracles/<name>.
  class Fetch
    SCM = 'git'

    def initialize(name:, pin:, root:, env:)
      @name = name
      @pin = pin
      @root = File.expand_path(root)
      @env = env
    end

    # Returns [source, nil] on success or [nil, reason] when no checkout can be acquired.
    def checkout
      return [nil, "local pin #{@pin.sha} is not a directory"] if @pin.local? && !File.directory?(@pin.sha)
      return [@pin.sha, nil] if @pin.local?

      fetch_checkout
    end

    private

    def fetch_checkout
      cache = cache_dir
      return [cache, nil] if cached_head(cache) == @pin.sha

      FileUtils.rm_rf(cache)
      Shell.capture(@env, [SCM, 'init', '--quiet', cache])
      scm(cache, ['remote', 'add', 'origin', url])
      ok, err = scm(cache, ['fetch', '--depth', '1', '--quiet', 'origin', @pin.sha])
      ok, err = scm(cache, ['fetch', '--depth', '1', '--quiet', 'origin', tag_ref]) if !ok && @pin.tag
      return [nil, fetch_reason(err)] unless ok

      verify_checkout(cache)
    end

    def verify_checkout(cache)
      ok, err = scm(cache, %w[checkout --detach --quiet FETCH_HEAD])
      return [nil, "checkout failed: #{Shell.clip(err)}"] unless ok

      _ok, head = scm(cache, %w[rev-parse HEAD])
      return [nil, "fetched HEAD #{head} does not match pin #{@pin.sha}"] unless head == @pin.sha

      [cache, nil]
    end

    # A cached checkout whose HEAD matches the pin makes reruns offline-safe.
    def cached_head(cache)
      return unless File.file?(File.join(cache, '.git', 'HEAD'))

      ok, head = scm(cache, %w[rev-parse HEAD])
      head if ok
    end

    def fetch_reason(err)
      desc = "pin #{@pin.sha}"
      desc += " (tag #{@pin.tag})" if @pin.tag
      "fetch failed for #{desc}: #{Shell.clip(err)}"
    end

    def scm(dir, args) = Shell.capture(@env, [SCM, '-C', dir, *args])

    def cache_dir = File.join(@root, 'tmp', 'oracles', @name)

    def url = "https://github.com/#{Runner::REMOTES.fetch(@name)}"

    def tag_ref = "refs/tags/#{@pin.tag}"
  end

  # Runs one oracle: bundle-installs the overlay Gemfile, executes the run
  # script, classifies the outcome into a Row. Checkout, install and
  # crash/timeout failures all classify as skip; only counted suite failures
  # fail, and skips never gate the exit status.
  class Suite
    RESULT_LINE = /\AORACLE RESULT pass=(\d+) fail=(\d+) skip=(\d+)\z/

    def initialize(name:, pin:, root:, env:, io:)
      @name = name
      @pin = pin
      @root = File.expand_path(root)
      @env = env
      @io = io
      @timeout = Integer(env.fetch('ORACLE_TIMEOUT', Runner::DEFAULT_TIMEOUT))
    end

    def call
      @io.puts("==> #{@name} (#{@pin.sha})")
      src, reason = Fetch.new(name: @name, pin: @pin, root: @root, env: @env).checkout
      return skip_row('fetch', reason) if reason

      skip = install(src)
      return skip if skip

      finish(src)
    end

    private

    def install(src)
      log = File.join(tmp_dir, "#{@name}-install.log")
      status = Shell.run(child_env(src), %w[bundle install], chdir: @root, log: log, timeout: @timeout)
      return nil if status.is_a?(Process::Status) && status.success?

      return skip_row('install', "bundle install timed out after #{@timeout}s (#{log})") if status == :timeout

      skip_row('install', "bundle install failed (exit #{status.exitstatus}): #{Shell.tail(log)} (#{log})")
    end

    def finish(src)
      log = File.join(tmp_dir, "#{@name}.log")
      script = File.join(oracle_dir, 'run')
      status = Shell.run(child_env(src, shadow: true), [script], chdir: @root, log: log, timeout: @timeout)
      counts = result_counts(log)
      return skip_row('timeout', "run timed out after #{@timeout}s (#{log})") if status == :timeout

      return skip_row('run', "no ORACLE RESULT after exit #{status.exitstatus}: #{Shell.tail(log)}") unless counts

      counted_row(counts, status)
    end

    def counted_row(counts, status)
      pass, fail, skip = counts
      return row(pass:, fail:, skip:, verdict: 'pass') if status.success? && fail.zero?

      reason = "#{fail} failure(s)"
      reason << ", exit #{status.exitstatus}" unless status.success?
      row(pass:, fail:, skip:, verdict: 'fail', reason: reason)
    end

    def result_counts(log)
      line = File.readlines(log, chomp: true).reverse.map(&:strip).find { |entry| RESULT_LINE.match?(entry) }
      match = line&.match(RESULT_LINE)
      return unless match

      [match[1].to_i, match[2].to_i, match[3].to_i]
    end

    def row(pass:, fail:, skip:, verdict:, reason: nil)
      total = pass + fail + skip
      pct = total.zero? ? 0 : (pass * 100.0 / total).round
      Row.new(name: @name, pin: @pin.sha, pass:, fail:, skip:, pct:, verdict:, reason:)
    end

    def skip_row(stage, reason)
      documented = documented_skip("#{@name}:#{stage}")
      reason = "#{reason} — documented: #{documented}" if documented
      row(pass: 0, fail: 0, skip: 0, verdict: 'skip', reason: reason)
    end

    # skip.txt documents accepted skips as `<id> <reason> (<issue url>)`; a
    # matching entry is merged into the row so the printed reason carries it.
    def documented_skip(id)
      entry = skip_entries.find { |line| line.split.first == id }
      entry.split(' ', 2).last if entry&.include?(' ')
    end

    def skip_entries
      File.readlines(File.join(oracle_dir, 'skip.txt'), chomp: true)
          .map(&:strip)
          .reject { |line| line.empty? || line.start_with?('#') }
    end

    # The runner usually starts under `bundle exec rake`, whose RUBYOPT/BUNDLE_*
    # point at the app's own bundle: unset them so the overlay bundle stands
    # alone. BUNDLE_GEMFILE is what `bundle exec` inside the run script needs to
    # find the overlay; shadow adds the RUBYOPT preamble for the suite itself.
    def child_env(src, shadow: false)
      env = @env.to_h { |key, value| [key, key == 'RUBYOPT' || key.start_with?('BUNDLE_') ? nil : value] }
      env['RUBYOPT'] = RUBYOPT_PREFIX if shadow
      env['ORACLE_SRC'] = src
      env['FAST_RSPEC_ROOT'] = @root
      env['ORACLE_NAME'] = @name
      env['BUNDLE_GEMFILE'] = File.join(oracle_dir, 'Gemfile')
      env
    end

    def oracle_dir = File.join(@root, 'test', 'oracles', @name)

    def tmp_dir = File.join(@root, 'tmp', 'oracles')
  end

  # Discovers test/oracles/<name>/ dirs, runs each pinned suite and reports one
  # Row per suite. Exit status is 1 only when a suite ran and failed
  # un-skipped; skips (fetch, install, crash, timeout) never gate.
  class Runner
    REMOTES = {
      'minitest' => 'minitest/minitest',
      'rspec-core' => 'rspec/rspec-core',
      'rspec-expectations' => 'rspec/rspec-expectations',
      'rspec-mocks' => 'rspec/rspec-mocks',
      'webmock' => 'webmock/webmock',
      'vcr' => 'vcr/vcr',
      'faker' => 'faker-ruby/faker',
      'database_cleaner' => 'DatabaseCleaner/database_cleaner',
      'simplecov' => 'simplecov-ruby/simplecov',
      'factory_bot' => 'thoughtbot/factory_bot'
    }.freeze
    DEFAULT_TIMEOUT = 1800
    FILES = %w[.sha Gemfile run skip.txt].freeze
    # [column title, width, padding]; nil padding runs to the end of the line.
    TABLE = [
      ['oracle', 19, :ljust], ['pinned', 41, :ljust], ['pass', 5, :rjust], ['fail', 5, :rjust],
      ['skip', 5, :rjust], ['%', 5, :rjust], ['verdict', 8, :ljust], ['reason', 0, nil]
    ].freeze

    def initialize(app_root, env: ENV, io: $stdout)
      @root = File.expand_path(app_root)
      @env = env
      @io = io
      @timeout = resolve_timeout
    end

    def run(filter = nil)
      names = discover(filter)
      pins = names.to_h { |name| [name, checked_pin(name)] }
      rows = names.map { |name| suite(name, pins.fetch(name)).call }
      write_results(rows)
      print_table(rows)
      rows.any? { |row| row.verdict == 'fail' } ? 1 : 0
    end

    private

    def resolve_timeout
      Integer(@env.fetch('ORACLE_TIMEOUT', DEFAULT_TIMEOUT))
    rescue ArgumentError, TypeError
      raise ArgumentError, 'ORACLE_TIMEOUT must be an integer number of seconds'
    end

    def discover(filter)
      base = File.join(@root, 'test', 'oracles')
      names = Dir.children(base).select { |entry| oracle?(base, entry) }.sort
      return names unless filter

      abort "ORACLE=#{filter} matches none of #{names.join(', ')}" unless names.include?(filter)
      [filter]
    end

    # support/ holds the runner itself and the RUBYOPT shim — not an oracle.
    def oracle?(base, entry)
      entry != 'support' && File.directory?(File.join(base, entry))
    end

    def suite(name, pin)
      Suite.new(name: name, pin: pin, root: @root, env: @env, io: @io)
    end

    def oracle_dir(name) = File.join(@root, 'test', 'oracles', name)

    def checked_pin(name)
      dir = oracle_dir(name)
      FILES.each do |file|
        abort "test/oracles/#{name}/#{file} is missing" unless File.file?(File.join(dir, file))
      end
      pin = read_pin(dir)
      abort "test/oracles/#{name}/run is not executable" unless File.executable?(File.join(dir, 'run'))
      abort "no REMOTES entry for test/oracles/#{name}" if !pin.local? && !REMOTES.key?(name)
      pin
    end

    def read_pin(dir)
      Pin.read(dir)
    rescue RuntimeError => e
      abort "#{dir}/.sha: #{e.message}"
    end

    def write_results(rows)
      FileUtils.mkdir_p(File.join(@root, 'tmp', 'oracles'))
      File.write(File.join(@root, 'tmp', 'oracles', 'results.json'), "#{JSON.pretty_generate(rows.map(&:to_h))}\n")
    end

    def print_table(rows)
      lines = ['', header]
      rows.each { |row| lines << table_row(row) }
      lines << "#{rows.size} suites → #{File.join(@root, 'tmp', 'oracles', 'results.json')}"
      @io.puts(lines.join("\n"))
    end

    def header
      TABLE.map { |title, width, pad| pad ? title.public_send(pad, width) : title }.join(' ')
    end

    def table_row(row)
      values = [row.name, row.pin, row.pass, row.fail, row.skip, "#{row.pct}%", row.verdict, row.reason.to_s]
      cells = TABLE.zip(values).map do |(_title, width, pad), value|
        pad ? value.to_s.public_send(pad, width) : value.to_s
      end
      cells.join(' ')
    end
  end
end
