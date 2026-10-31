# frozen_string_literal: true

RSpec.describe 'Checkout flow' do
  let(:catalog) do
    [build(:product, :book, sku: 'BOOK', price: Shop::Money.parse('24.00 EUR'), stock: 3),
     build(:product, sku: 'SKU-3FOR2', price: Shop::Money.parse('2.50 EUR'), stock: 30)]
  end
  let(:pricing) do
    Shop::Pricing.new(discounts: [build(:percent_off, :books_only, percent: 25), build(:buy_x_get_y)],
                      strategy: :stack, tax_rate: '0.07')
  end
  let(:cart) { Shop::Cart.new.add(catalog[0], 2).add(catalog[1], 6) }

  it 'prices, places and pays an order' do
    order = Shop::Order.place(cart, pricing: pricing, ids: Shop::Counter.new)
    expect(order.quote).to have_attributes(subtotal: Shop::Money.parse('63.00 EUR'),
                                           discount: Shop::Money.parse('17.00 EUR'))
    expect(order).to cost('49.22 EUR')
    expect(order.pay!).to be_paid
  end

  it 'shows the total in USD using live rates', vcr: { cassette_name: 'exchange_rates/eur' } do
    order = Shop::Order.place(cart, pricing: pricing)
    usd = Shop::ExchangeRates.new(api_key: 'test-key').convert(order.total, to: 'USD')
    expect(usd).to eq(Shop::Money.parse('53.32 USD'))
  end

  it 'survives a flaky rates API', :slow do
    stub_request(:get, 'https://api.example.test/v1/rates?base=EUR')
      .to_return({ status: 503 }, { status: 200, body: { base: 'EUR', rates: { GBP: 0.5 } }.to_json })
    rates = Shop::ExchangeRates.new(retries: 1)
    expect(rates.convert(Shop::Money.parse('10.00 EUR'), to: 'GBP')).to eq(Shop::Money.parse('5.00 GBP'))
  end
end
