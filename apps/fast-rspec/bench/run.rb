# frozen_string_literal: true

# Boot-cost and floor benchmarks. Plain Ruby, stdlib only.
# Every sample runs in a fresh `ruby -I lib` child; the median of BENCH_RUNS (default 15) is reported.
#
#   cd apps/fast-rspec && bundle exec rake bench
require 'etc'
require 'open3'
require 'rbconfig'

RUNS = Integer(ENV.fetch('BENCH_RUNS', '15'))
EXAMPLES = 10_000
LIB = File.expand_path('../lib', __dir__)

REQUIRE_PROBE = <<~RUBY
  GC.start
  allocs = GC.stat(:total_allocated_objects)
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  require 'fast_rspec'
  ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000
  puts "\#{ms} \#{GC.stat(:total_allocated_objects) - allocs}"
RUBY

# No example engine exists yet (lib/fast_rspec/engine/ is empty): invoke empty blocks serially.
FLOOR_PROBE = <<~RUBY.freeze
  blocks = Array.new(#{EXAMPLES}) { proc {} }
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  blocks.each(&:call)
  puts Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
RUBY

NATIVE_PROBE = <<~RUBY
  require 'fast_rspec'
  puts FastRspec::Render.native?
RUBY

def child(code)
  out, err, status = Open3.capture3(RbConfig.ruby, '-I', LIB, '-e', code)
  abort "bench child failed: #{err}" unless status.success?

  out.split.map { Float(_1, exception: false) || _1 }
end

def median(values)
  sorted = values.sort
  mid = sorted.size / 2
  sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
end

require_samples = Array.new(RUNS) { child(REQUIRE_PROBE) }
floor_samples = Array.new(RUNS) { child(FLOOR_PROBE).first }
native = child(NATIVE_PROBE).first == 'true'
yjit = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?

require_ms = median(require_samples.map(&:first))
allocs = median(require_samples.map(&:last))
floor_s = median(floor_samples)

puts RUBY_DESCRIPTION
puts "YJIT: #{yjit ? 'on' : 'off'} | cores: #{Etc.nprocessors} | render: #{native ? 'native' : 'pure'} | " \
     "serial | median of #{RUNS} fresh processes"
puts
puts '| Metric | Result | Target |'
puts '|---|---|---|'
puts format('| `require "fast_rspec"` | %<ms>.2f ms | < 20 ms |', ms: require_ms)
puts format('| Allocations during `require` | %<n>d | < 5k |', n: allocs)
puts format('| %<n>d empty blocks, serial (harness floor, no engine) | %<s>.4f s | < 0.5 s (10k trivial examples) |',
            n: EXAMPLES, s: floor_s)
puts
puts 'Note: no example engine exists yet, so the 10k row is an empty-block floor, not an example-run number.'
