# frozen_string_literal: true

# Parses an upstream suite's totals line into the counts the oracle reports as
# `ORACLE RESULT pass=<n> fail=<n> skip=<n>`.
#
# The suites speak two dialects:
#
#   rspec     "12 examples, 0 failures" / "5 examples, 1 failure, 2 pending" /
#             "2 examples, 0 failures, 1 error occurred outside of examples"
#   minitest  "12 runs, 24 assertions, 0 failures, 0 errors, 0 skips"
#             (test-unit spells the same line "42 tests, ...")
#
# Errors outside of examples (a spec file that failed to load) fold into the
# failures, so a silently missing spec file never reads as a pass.
#
# The oracle run scripts used to carry their own copy of these regexes: a
# wrong one shipped unnoticed and a failing suite read as a skip. The parsing
# lives here once; the unit suite (test/unit/oracles_runner_test.rb) pins it.
module Oracles
  module Totals
    # The counts of one suite run and the unit the suite counts in.
    Result = Struct.new(:passed, :failed, :skipped, :unit) do
      def total = passed + failed + skipped
    end

    DIALECTS = {
      rspec: {
        unit: 'examples',
        pattern: /(\d+) examples?, (\d+) failures?(?:, (\d+) pending)?(?:, (\d+) errors? occurred outside of examples)?/
      },
      runs: {
        unit: 'runs',
        pattern: /(\d+) runs, \d+ assertions, (\d+) failures, (\d+) errors, (\d+) skips/
      },
      tests: {
        unit: 'runs',
        pattern: /(\d+) tests, \d+ assertions, (\d+) failures, (\d+) errors, (\d+) skips/
      }
    }.freeze

    class << self
      # Parses suite output into a Result, or nil when it holds no totals line.
      # `dialects` are tried in order and the first one with a totals line
      # wins; `policy` :sum adds every totals line of every dialect up
      # instead - faker's suite prints a test-unit line and a minitest line,
      # and both are real.
      def parse(text, dialects: [:rspec], policy: :last)
        found = dialects.map { |dialect| results(text, dialect) }.reject(&:empty?)
        return nil if found.empty?

        selected = chosen(found, policy)
        Result.new(selected.sum(&:passed), selected.sum(&:failed), selected.sum(&:skipped), selected.first.unit)
      end

      private

      # :last takes the last totals line of the first dialect that matched,
      # :sum adds the totals lines of every dialect up.
      def chosen(found, policy)
        policy == :sum ? found.flatten : [found.first.last]
      end

      def results(text, dialect)
        config = DIALECTS.fetch(dialect)
        text.to_s.scan(config[:pattern]).map { |match| result(dialect, match) }
      end

      def result(dialect, match)
        dialect == :rspec ? rspec_result(dialect, match) : runner_result(dialect, match)
      end

      # "12 examples, 0 failures" / "5 examples, 1 failure, 2 pending" /
      # "2 examples, 0 failures, 1 error occurred outside of examples".
      def rspec_result(dialect, match)
        examples, failures, pending_count, errors = match.map(&:to_i)
        failed = failures + errors
        Result.new(examples - failed - pending_count, failed, pending_count, DIALECTS.fetch(dialect)[:unit])
      end

      # "12 runs, 24 assertions, 0 failures, 0 errors, 0 skips".
      def runner_result(dialect, match)
        runs, failures, errors, skipped_count = match.map(&:to_i)
        failed = failures + errors
        Result.new(runs - failed - skipped_count, failed, skipped_count, DIALECTS.fetch(dialect)[:unit])
      end
    end

    # Command line entry point for the oracle run scripts:
    #   ruby totals.rb --dialect rspec --oracle NAME FILE
    # Prints `ORACLE RESULT pass=<n> fail=<n> skip=<n>` and exits 0; when the
    # counts cannot be decided it says why on stderr and exits 1.
    module CLI
      POLICIES = %i[last sum].freeze

      module_function

      def run(argv, out: $stdout, err: $stderr)
        options = parse(argv)
        result = Totals.parse(read(options[:file]), dialects: options[:dialects], policy: options[:policy])
        return no_totals(options[:oracle], err) unless result
        return nothing_executed(options[:oracle], result, err) if result.total.zero?

        out.puts("ORACLE RESULT pass=#{result.passed} fail=#{result.failed} skip=#{result.skipped}")
        0
      end

      def read(file) = file ? File.read(file) : $stdin.read

      def no_totals(oracle, err)
        err.puts("oracle #{oracle}: no totals line in the suite output - the suite never completed")
        1
      end

      def nothing_executed(oracle, result, err)
        err.puts("oracle #{oracle}: suite completed with 0 #{result.unit} - nothing executed")
        1
      end

      def parse(argv)
        options = defaults
        rest = argv.dup
        option(rest, options) until rest.empty?
        options[:dialects] = [:rspec] if options[:dialects].empty?
        options
      end

      def defaults
        { dialects: [], policy: :last, oracle: ENV.fetch('ORACLE_NAME', '?'), file: nil }
      end

      def option(rest, options)
        arg = rest.shift
        case arg
        when '--dialect' then options[:dialects] << dialect(rest.shift)
        when '--policy' then options[:policy] = policy(rest.shift)
        when '--oracle' then options[:oracle] = rest.shift
        else options[:file] = arg
        end
      end

      def dialect(name)
        DIALECTS.fetch(name.to_sym) { raise ArgumentError, "unknown totals dialect: #{name}" }
        name.to_sym
      end

      def policy(name)
        raise ArgumentError, "unknown totals policy: #{name}" unless POLICIES.include?(name.to_sym)

        name.to_sym
      end
    end
  end
end

exit Oracles::Totals::CLI.run(ARGV) if $PROGRAM_NAME == __FILE__
