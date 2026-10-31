# frozen_string_literal: true

RSpec.describe Shop::Cache do
  let(:now) { [100.0] }
  let(:clock) { -> { now.first } }

  subject(:cache) { described_class.new(ttl: 10, clock: clock) }

  it 'computes a missing value once and then hits' do
    calls = 0
    2.times { cache.fetch(:a) { calls += 1 } }
    expect(calls).to eq(1)
    expect([cache.hits, cache.misses]).to eq([1, 1])
  end

  it 'passes the key to the block' do
    expect(cache.fetch('k', &:upcase)).to eq('K')
  end

  it 'expires entries after the ttl (fake clock)' do
    cache.write(:a, 1)
    now[0] += 9.99
    expect(cache.read(:a)).to eq(1)
    now[0] += 0.01
    expect(cache.read(:a)).to be_nil
  end

  it 'expires entries after the ttl (real clock)', :slow do
    real = described_class.new(ttl: 0.1)
    real.write(:a, 1)
    sleep 0.2
    expect(real.key?(:a)).to be(false)
  end

  it 'purges expired entries when sizing' do
    cache.write(:a, 1)
    now[0] += 5
    cache.write(:b, 2)
    now[0] += 6
    expect(cache.size).to eq(1)
  end

  it 'deletes and clears' do
    cache.write(:a, 1)
    cache.write(:b, 2)
    expect(cache.delete(:a)).to eq(1)
    cache.clear
    expect(cache.size).to eq(0)
  end

  it 'computes once under contention', :slow do
    calls = Shop::Counter.new
    real = described_class.new(ttl: 60)
    values = Array.new(5) do
      Thread.new do
        real.fetch(:rates) do
          calls.increment
          sleep 0.2
          :computed
        end
      end
    end.map(&:value)
    expect(values).to all(eq(:computed))
    expect(calls.value).to eq(1)
  end
end
