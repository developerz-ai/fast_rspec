# frozen_string_literal: true

RSpec.describe Shop::Cart do
  subject(:cart) { build(:cart) }

  let(:mug) { build(:product, sku: 'MUG', price: Shop::Money.parse('8.50 EUR'), stock: 5) }
  let(:tea) { build(:product, sku: 'TEA', price: Shop::Money.parse('3.25 EUR'), stock: 100) }

  it 'starts empty' do
    expect(cart).to be_empty
    expect(cart).to cost('0.00 EUR')
  end

  it 'adds products and sums the subtotal' do
    cart.add(mug).add(tea, 4)
    expect(cart).to cost('21.50 EUR')
    expect(cart.item_count).to eq(5)
  end

  it 'merges repeated adds of the same sku' do
    expect { cart.add(mug).add(mug, 2) }.to change { cart.quantity('mug') }.from(0).to(3)
    expect(cart.items.map(&:sku)).to contain_exactly('MUG')
  end

  it 'refuses to oversell' do
    cart.add(mug, 5)
    expect { cart.add(mug) }.to raise_error(Shop::Cart::OutOfStock, 'MUG: wanted 6, have 5')
  end

  it 'refuses products in another currency' do
    expect { cart.add(build(:product, :usd)) }.to raise_error(Shop::Money::CurrencyMismatch)
  end

  it 'rejects non-positive quantities' do
    expect { cart.add(mug, 0) }.to raise_error(ArgumentError)
  end

  describe '#remove' do
    before { cart.add(tea, 4) }

    it 'removes part of a line' do
      expect { cart.remove('tea', 3) }.to change(cart, :item_count).by(-3)
    end

    it 'removes the whole line without a quantity' do
      cart.remove('TEA')
      expect(cart).to be_empty
    end

    it 'ignores unknown skus' do
      expect { cart.remove('NOPE') }.not_to change(cart, :item_count)
    end
  end

  it 'is built with items by the factory trait' do
    expect(build(:cart, :with_items).items.size).to eq(3)
  end

  it 'clears' do
    expect(build(:cart, products: [mug, tea], quantity: 2).clear).to be_empty
  end
end
