# frozen_string_literal: true

module Shop
  # Thread-safe TTL cache. `fetch` computes a missing key once even under contention.
  class Cache
    Entry = Data.define(:value, :expires_at)

    attr_reader :ttl, :hits, :misses

    def initialize(ttl:, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @ttl = ttl
      @clock = clock
      @store = {}
      @mutex = Mutex.new
      @hits = 0
      @misses = 0
    end

    def fetch(key)
      @mutex.synchronize do
        entry = live_entry(key)
        if entry
          @hits += 1
          return entry.value
        end
        @misses += 1
        value = yield(key)
        @store[key] = Entry.new(value: value, expires_at: @clock.call + ttl)
        value
      end
    end

    def read(key) = @mutex.synchronize { live_entry(key)&.value }

    def write(key, value)
      @mutex.synchronize { @store[key] = Entry.new(value: value, expires_at: @clock.call + ttl) }
      value
    end

    def delete(key) = @mutex.synchronize { @store.delete(key)&.value }
    def key?(key) = @mutex.synchronize { !live_entry(key).nil? }

    def size
      @mutex.synchronize do
        @store.delete_if { |_, e| expired?(e) }
        @store.size
      end
    end

    def clear = @mutex.synchronize { @store.clear }

    private

    def live_entry(key)
      entry = @store[key]
      return unless entry
      return entry unless expired?(entry)

      @store.delete(key)
      nil
    end

    def expired?(entry) = @clock.call >= entry.expires_at
  end
end
