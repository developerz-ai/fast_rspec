# frozen_string_literal: true

RSpec.describe Shop::Pricing do
  let(:book) { build(:product, :book, sku: 'BOOK', price: Shop::Money.parse('20.00 EUR'), stock: 50) }
  let(:cart) { build(:cart, products: [book], quantity: 3) }
  let(:ten_percent) { build(:percent_off, percent: 10) }
  let(:five_off) { build(:fixed_off) }

  it 'quotes the subtotal when there are no discounts' do
    quote = described_class.new.quote(cart)
    expect(quote).to have_attributes(subtotal: Shop::Money.parse('60.00 EUR'), applied: [])
    expect(quote).to cost('60.00 EUR')
  end

  it 'applies only the best discount by default' do
    quote = described_class.new(discounts: [ten_percent, five_off]).quote(cart)
    expect(quote.applied).to eq(['10% off'])
    expect(quote).to cost('54.00 EUR')
  end

  it 'stacks discounts when asked' do
    quote = described_class.new(discounts: [ten_percent, five_off], strategy: :stack).quote(cart)
    expect(quote.applied).to contain_exactly('10% off', 'Five off')
    expect(quote).to cost('49.00 EUR')
  end

  it 'never goes below zero' do
    huge = build(:fixed_off, amount: Shop::Money.parse('500.00 EUR'))
    quote = described_class.new(discounts: [huge, ten_percent], strategy: :stack).quote(cart)
    expect(quote).to have_attributes(discount: quote.subtotal)
    expect(quote).to cost('0.00 EUR')
  end

  it 'adds tax after discounts, rounding half up' do
    quote = described_class.new(discounts: [five_off], tax_rate: '0.19').quote(cart)
    expect(quote.tax).to eq(Shop::Money.parse('10.45 EUR'))
    expect(quote).to cost('65.45 EUR')
  end

  it 'ignores coupons that were not entered' do
    coupon = build(:percent_off, percent: 50, code: 'HALF')
    pricing = described_class.new(discounts: [coupon])
    expect(pricing.quote(cart)).to cost('60.00 EUR')
    expect(pricing.quote(cart, codes: ['half'])).to cost('30.00 EUR')
  end

  it 'evaluates expiry against the injected clock' do
    promo = build(:percent_off, percent: 20, expires_at: Time.utc(2026, 11, 1))
    clock = double('clock')
    allow(clock).to receive(:call).and_return(Time.utc(2026, 10, 31), Time.utc(2026, 11, 2))
    pricing = described_class.new(discounts: [promo], clock: clock)

    expect(pricing.quote(cart)).to cost('48.00 EUR')
    expect(pricing.quote(cart)).to cost('60.00 EUR')
    expect(clock).to have_received(:call).twice
  end

  it 'asks every discount for its amount (verified doubles)' do
    discount = instance_double(Shop::Discounts::PercentOff, name: 'mocked', applicable?: true,
                                                            amount_for: Shop::Money.parse('1.00 EUR'))
    expect(described_class.new(discounts: [discount]).quote(cart)).to cost('59.00 EUR')
    expect(discount).to have_received(:amount_for).with(cart).once
    expect(discount).to have_received(:applicable?).with(cart, codes: [], now: kind_of(Time))
  end

  it 'skips discounts that are not applicable without computing them' do
    discount = instance_double(Shop::Discounts::FixedOff, applicable?: false)
    expect(discount).not_to receive(:amount_for)
    described_class.new(discounts: [discount]).quote(cart)
  end

  it 'rejects unknown strategies' do
    expect { described_class.new(strategy: :cheapest) }.to raise_error(ArgumentError, /unknown strategy :cheapest/)
  end
end
