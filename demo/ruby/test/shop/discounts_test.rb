# frozen_string_literal: true

require 'test_helper'

# Minitest's take on shared examples: a module of tests included into each spec.
module DiscountBehaviour
  def test_applies_to_eligible_cart_with_expected_amount
    assert discount.applicable?(eligible_cart, codes: Array(discount.code))
    assert_equal Shop::Money.parse(expected_amount), discount.amount_for(eligible_cart)
  end

  def test_never_applies_to_empty_cart
    refute discount.applicable?(Shop::Cart.new, codes: Array(discount.code))
  end

  def test_stops_applying_once_expired
    refute expired_discount.applicable?(eligible_cart, codes: Array(expired_discount.code))
  end
end

describe Shop::Discounts do
  let(:book) { build(:product, :book, sku: 'BOOK', price: Shop::Money.parse('20.00 EUR'), stock: 50) }
  let(:pen) { build(:product, sku: 'PEN', price: Shop::Money.parse('2.00 EUR'), stock: 50) }
  let(:eligible_cart) { build(:cart, products: [book, pen], quantity: 2) }

  describe Shop::Discounts::PercentOff do
    include DiscountBehaviour

    let(:discount) { build(:percent_off, percent: 10) }
    let(:expired_discount) { build(:percent_off, :expired) }
    let(:expected_amount) { '4.40 EUR' }

    it 'limits to a category' do
      _(build(:percent_off, :books_only, percent: 25).amount_for(eligible_cart)).must_equal Shop::Money.parse('10.00 EUR')
    end

    it 'needs the coupon code, case-insensitively' do
      coupon = build(:percent_off, :coupon)
      _(coupon.applicable?(eligible_cart, codes: [])).must_equal false
      _(coupon.applicable?(eligible_cart, codes: [coupon.code.downcase])).must_equal true
    end

    it 'gets distinct codes from Faker.unique' do
      _(build_list(:percent_off, 5, :coupon).map(&:code).uniq.size).must_equal 5
    end

    it 'validates the percent' do
      _ { build(:percent_off, percent: -1) }.must_raise ArgumentError
    end
  end

  describe Shop::Discounts::FixedOff do
    include DiscountBehaviour

    let(:discount) { build(:fixed_off) }
    let(:expired_discount) { build(:fixed_off, expires_at: Time.at(0)) }
    let(:expected_amount) { '5.00 EUR' }

    it 'never exceeds the subtotal' do
      cart = build(:cart, products: [build(:product, :cheap)])
      _(discount.amount_for(cart)).must_equal Shop::Money.parse('1.00 EUR')
    end

    it 'respects a minimum subtotal' do
      _(build(:fixed_off, min_subtotal: Shop::Money.parse('100.00 EUR')).applicable?(eligible_cart)).must_equal false
    end
  end

  describe Shop::Discounts::BuyXGetY do
    include DiscountBehaviour

    let(:item) { build(:product, sku: 'SKU-3FOR2', price: Shop::Money.parse('3.00 EUR'), stock: 20) }
    let(:discount) { build(:buy_x_get_y) }
    let(:expired_discount) { build(:buy_x_get_y, expires_at: Time.now - 60) }
    let(:eligible_cart) { build(:cart, products: [item], quantity: 7) }
    let(:expected_amount) { '6.00 EUR' }

    it 'gives nothing below a full group' do
      _(discount.amount_for(build(:cart, products: [item], quantity: 2))).must_be :zero?
    end
  end
end
