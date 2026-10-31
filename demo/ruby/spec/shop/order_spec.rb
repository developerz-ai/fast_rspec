# frozen_string_literal: true

RSpec.describe Shop::Order do
  let(:cart) { build(:cart, products: [build(:product, sku: 'MUG', price: Shop::Money.parse('8.00 EUR'))], quantity: 2) }
  let(:ids) { instance_double(Shop::Counter, next_id: 'ORD-000042') }
  let(:now) { Time.utc(2026, 10, 31, 12, 0, 0) }

  subject(:order) { described_class.place(cart, ids: ids, now: now) }

  it 'is placed pending with an id from the counter' do
    expect(order).to have_attributes(id: 'ORD-000042', status: :pending)
    expect(order).to cost('16.00 EUR')
    expect(ids).to have_received(:next_id).with('ORD')
  end

  it 'refuses an empty cart' do
    expect { described_class.place(Shop::Cart.new) }.to raise_error(Shop::Order::EmptyCart)
  end

  it 'snapshots the cart lines' do
    order
    cart.clear
    expect(order.lines.map(&:sku)).to eq(['MUG'])
    expect(order.lines).to be_frozen
  end

  it 'uses the global id counter by default' do
    stub_const('Shop::Order::IDS', Shop::Counter.new(99))
    expect(described_class.place(cart).id).to eq('ORD-000100')
  end

  describe 'state machine' do
    it { is_expected.to allow_transition_to(:paid) }
    it { is_expected.to allow_transition_to(:cancelled) }
    it { is_expected.not_to allow_transition_to(:shipped) }

    it 'walks the happy path' do
      order.pay!.ship!.deliver!
      expect(order).to be_delivered
      expect(order).to be_final
      expect(order.history).to eq(%i[pending paid shipped delivered])
    end

    it 'raises on invalid transitions' do
      order.cancel!
      expect { order.pay! }.to raise_error(Shop::Order::InvalidTransition, 'ORD-000042: cancelled -> paid')
    end

    it 'can refund a paid order' do
      expect { order.pay!.refund! }.to change(order, :status).from(:pending).to(:refunded)
    end
  end

  it 'serializes to JSON' do
    json = JSON.parse(order.to_json)
    expect(json).to include('id' => 'ORD-000042', 'status' => 'pending', 'placed_at' => '2026-10-31T12:00:00Z',
                            'total' => '16.00 EUR')
    expect(json['lines']).to contain_exactly(a_hash_including('sku' => 'MUG', 'quantity' => 2))
  end
end
