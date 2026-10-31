# frozen_string_literal: true

# Zero-dependency harness for our own suite until our Minitest can run it (roadmap M1).
# Deliberately tiny: no upstream minitest/rspec may load in this repo's tests.
module Bootstrap
  class Failure < StandardError; end

  class Test
    @classes = []

    class << self
      attr_reader :classes

      def inherited(klass)
        super
        Test.classes << klass
      end
    end

    def assert(cond, msg = 'expected truthy') = cond || raise(Failure, msg)
    def assert_equal(exp, act) = assert(exp == act, "expected #{exp.inspect}, got #{act.inspect}")
    def assert_includes(col, obj) = assert(col.include?(obj), "expected #{col.inspect} to include #{obj.inspect}")
    def refute_nil(obj) = assert(!obj.nil?, 'expected non-nil')
  end

  def self.run(files)
    files.each { |f| require File.expand_path(f) }
    failures = cases.filter_map { |klass, m| run_one(klass, m) }
    puts "\n#{cases.size} tests, #{failures.size} failures"
    failures.each { |f| puts "  #{f}" }
    exit(failures.empty? ? 0 : 1)
  end

  def self.cases
    @cases ||= Test.classes.flat_map { |k| k.public_instance_methods(false).grep(/\Atest_/).map { |m| [k, m] } }
  end

  def self.run_one(klass, meth)
    klass.new.public_send(meth)
    print '.'
    nil
  rescue StandardError => e
    print 'F'
    "#{klass}##{meth}: #{e.class}: #{e.message}"
  end
end
