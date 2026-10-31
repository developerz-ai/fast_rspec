# frozen_string_literal: true

require 'test_helper'

class PricingTest < Minitest::Test
  def setup
    @book = build(:product, :book, sku: 'BOOK', price: Shop::Money.parse('20.00 EUR'), stock: 50)
    @cart = build(:cart, products: [@book], quantity: 3)
    @ten_percent = build(:percent_off, percent: 10)
    @five_off = build(:fixed_off)
  end

  def test_no_discounts
    quote = Shop::Pricing.new.quote(@cart)

    assert_empty quote.applied
    assert_costs '60.00 EUR', quote
  end

  def test_best_discount_only
    quote = Shop::Pricing.new(discounts: [@ten_percent, @five_off]).quote(@cart)

    assert_equal ['10% off'], quote.applied
    assert_costs '54.00 EUR', quote
  end

  def test_stacking
    quote = Shop::Pricing.new(discounts: [@ten_percent, @five_off], strategy: :stack).quote(@cart)

    assert_equal ['10% off', 'Five off'].sort, quote.applied.sort
    assert_costs '49.00 EUR', quote
  end

  def test_never_below_zero
    huge = build(:fixed_off, amount: Shop::Money.parse('500.00 EUR'))
    quote = Shop::Pricing.new(discounts: [huge, @ten_percent], strategy: :stack).quote(@cart)

    assert_equal quote.subtotal, quote.discount
    assert_costs '0.00 EUR', quote
  end

  def test_tax_after_discount
    quote = Shop::Pricing.new(discounts: [@five_off], tax_rate: '0.19').quote(@cart)

    assert_costs '10.45 EUR', quote.tax
    assert_costs '65.45 EUR', quote
  end

  def test_coupons_need_codes
    pricing = Shop::Pricing.new(discounts: [build(:percent_off, percent: 50, code: 'HALF')])

    assert_costs '60.00 EUR', pricing.quote(@cart)
    assert_costs '30.00 EUR', pricing.quote(@cart, codes: ['half'])
  end

  def test_expiry_uses_time_now_via_stub
    promo = build(:percent_off, percent: 20, expires_at: Time.utc(2026, 11, 1))
    pricing = Shop::Pricing.new(discounts: [promo])

    Time.stub(:now, Time.utc(2026, 10, 31)) { assert_costs '48.00 EUR', pricing.quote(@cart) }
    Time.stub(:now, Time.utc(2026, 11, 2)) { assert_costs '60.00 EUR', pricing.quote(@cart) }
  end

  def test_asks_discounts_via_mock
    discount = Minitest::Mock.new
    discount.expect(:applicable?, true, [@cart], codes: [], now: Time)
    discount.expect(:amount_for, Shop::Money.parse('1.00 EUR'), [@cart])
    discount.expect(:name, 'mocked')

    quote = Shop::Pricing.new(discounts: [discount]).quote(@cart)

    assert_costs '59.00 EUR', quote
    assert_equal ['mocked'], quote.applied
    assert_mock discount
  end

  def test_unknown_strategy
    error = assert_raises(ArgumentError) { Shop::Pricing.new(strategy: :cheapest) }
    assert_match(/unknown strategy/, error.message)
  end
end
