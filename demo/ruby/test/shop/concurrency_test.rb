# frozen_string_literal: true

require 'test_helper'

class CounterTest < Minitest::Test
  parallelize_me!

  def setup
    @counter = Shop::Counter.new
  end

  def test_increment
    assert_equal 5, @counter.increment(5)
  end

  def test_ids
    assert_equal %w[INV-000001 INV-000002], [@counter.next_id('INV'), @counter.next_id('INV')]
  end

  def test_reset
    @counter.increment

    assert_equal 10, @counter.reset!(10)
  end

  def test_threads_do_not_lose_increments
    Array.new(8) { Thread.new { 1_000.times { @counter.increment } } }.each(&:join)

    assert_equal 8_000, @counter.value
  end

  def test_slow_concurrent_ids_are_unique
    ids = Array.new(4) do
      Thread.new do
        sleep 0.2
        Array.new(5) { @counter.next_id('X') }
      end
    end.flat_map(&:value)

    assert_equal 20, ids.uniq.size
  end
end

class CacheTest < Minitest::Test
  parallelize_me!

  def setup
    @now = 100.0
    @cache = Shop::Cache.new(ttl: 10, clock: -> { @now })
  end

  def test_fetch_computes_once
    calls = 0
    2.times { @cache.fetch(:a) { calls += 1 } }

    assert_equal 1, calls
    assert_equal [1, 1], [@cache.hits, @cache.misses]
  end

  def test_fake_clock_expiry
    @cache.write(:a, 1)
    @now += 9.99

    assert_equal 1, @cache.read(:a)
    @now += 0.01

    assert_nil @cache.read(:a)
  end

  def test_real_clock_expiry
    cache = Shop::Cache.new(ttl: 0.1)
    cache.write(:a, 1)
    sleep 0.2

    refute cache.key?(:a)
  end

  def test_size_purges_expired
    @cache.write(:a, 1)
    @now += 5
    @cache.write(:b, 2)
    @now += 6

    assert_equal 1, @cache.size
  end

  def test_delete_and_clear
    @cache.write(:a, 1)

    assert_equal 1, @cache.delete(:a)
    @cache.clear

    assert_equal 0, @cache.size
  end

  def test_computes_once_under_contention
    calls = Shop::Counter.new
    cache = Shop::Cache.new(ttl: 60)
    values = Array.new(5) do
      Thread.new do
        cache.fetch(:rates) do
          calls.increment
          sleep 0.2
          :computed
        end
      end
    end.map(&:value)

    assert_equal [:computed] * 5, values
    assert_equal 1, calls.value
  end
end
