# frozen_string_literal: true

module Shop
  class Counter
    def initialize(start = 0)
      @value = start
      @mutex = Mutex.new
    end

    def increment(by = 1) = @mutex.synchronize { @value += by }
    def value = @mutex.synchronize { @value }
    def reset!(to = 0) = @mutex.synchronize { @value = to }

    def next_id(prefix) = format('%<prefix>s-%<n>06d', prefix: prefix, n: increment)
  end
end
