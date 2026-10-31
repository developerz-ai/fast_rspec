# frozen_string_literal: true

require 'test_helper'

describe 'Checkout flow' do
  let(:book) { build(:product, :book, sku: 'BOOK', price: Shop::Money.parse('24.00 EUR'), stock: 3) }
  let(:item) { build(:product, sku: 'SKU-3FOR2', price: Shop::Money.parse('2.50 EUR'), stock: 30) }
  let(:pricing) do
    Shop::Pricing.new(discounts: [build(:percent_off, :books_only, percent: 25), build(:buy_x_get_y)],
                      strategy: :stack, tax_rate: '0.07')
  end
  let(:cart) { Shop::Cart.new.add(book, 2).add(item, 6) }

  it 'prices, places and pays an order' do
    order = Shop::Order.place(cart, pricing: pricing, ids: Shop::Counter.new)
    _(order.quote.discount).must_equal Shop::Money.parse('17.00 EUR')
    assert_costs '49.22 EUR', order
    _(order.pay!).must_be :paid?
  end

  it 'shows the total in USD using recorded rates' do
    VCR.use_cassette('exchange_rates/eur') do
      total = Shop::Order.place(cart, pricing: pricing).total
      _(Shop::ExchangeRates.new(api_key: 'test-key').convert(total, to: 'USD')).must_equal Shop::Money.parse('53.32 USD')
    end
  end

  it 'survives a flaky rates API' do
    stub_request(:get, 'https://api.example.test/v1/rates?base=EUR')
      .to_return({ status: 503 }, { status: 200, body: { base: 'EUR', rates: { GBP: 0.5 } }.to_json })
    _(Shop::ExchangeRates.new(retries: 1).convert(Shop::Money.parse('10.00 EUR'), to: 'GBP'))
      .must_equal Shop::Money.parse('5.00 GBP')
  end
end
