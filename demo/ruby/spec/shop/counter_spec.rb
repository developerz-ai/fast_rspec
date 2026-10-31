# frozen_string_literal: true

RSpec.describe Shop::Counter do
  subject(:counter) { described_class.new }

  it 'increments' do
    expect { counter.increment(5) }.to change(counter, :value).from(0).to(5)
  end

  it 'formats ids' do
    expect([counter.next_id('INV'), counter.next_id('INV')]).to eq(%w[INV-000001 INV-000002])
  end

  it 'resets' do
    counter.increment
    expect(counter.reset!(10)).to eq(10)
  end

  it 'does not lose increments across threads' do
    Array.new(8) { Thread.new { 1_000.times { counter.increment } } }.each(&:join)
    expect(counter.value).to eq(8_000)
  end

  it 'hands out unique ids to slow concurrent callers', :slow do
    ids = Queue.new
    Array.new(4) do
      Thread.new do
        sleep 0.2
        5.times { ids << counter.next_id('X') }
      end
    end.each(&:join)
    all = Array.new(ids.size) { ids.pop }
    expect(all.uniq.size).to eq(20)
  end
end
