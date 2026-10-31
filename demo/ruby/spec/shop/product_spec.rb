# frozen_string_literal: true

RSpec.describe Shop::Product do
  subject(:product) { build(:product, sku: 'abc-1', name: 'Mug') }

  it_behaves_like 'a value object' do
    let(:twin) { build(:product, sku: 'ABC-1', name: 'Mug') }
    let(:different) { build(:product, sku: 'ABC-2', name: 'Mug') }
  end

  it 'normalizes the sku to upper case' do
    expect(product.sku).to eq('ABC-1')
  end

  it 'builds unique skus from the factory sequence' do
    skus = build_list(:product, 5).map(&:sku)
    expect(skus.uniq.size).to eq(5)
    expect(skus).to all(match(/\ASKU-\d{4}\z/))
  end

  it 'supports traits' do
    book = build(:product, :book, :cheap)
    expect(book).to have_attributes(category: 'books', price: Shop::Money.parse('1.00 EUR'))
  end

  it 'works with `create` thanks to skip_create' do
    expect(create(:product, :out_of_stock)).not_to be_in_stock
  end

  it 'exposes in_stock? for a quantity' do
    expect(product).to be_in_stock(10)
    expect(product).not_to be_in_stock(11)
  end

  it 'serializes to a hash' do
    expect(product.to_h).to include(sku: 'ABC-1', price: '19.99 EUR', stock: 10)
  end

  describe 'validation' do
    it { expect { build(:product, sku: ' ') }.to raise_error(ArgumentError, /sku/) }
    it { expect { build(:product, price: 5) }.to raise_error(ArgumentError, /Shop::Money/) }
    it { expect { build(:product, price: Shop::Money.parse('-1 EUR')) }.to raise_error(ArgumentError, /negative/) }
    it { expect { build(:product, stock: -1) }.to raise_error(ArgumentError, /stock/) }
  end
end
