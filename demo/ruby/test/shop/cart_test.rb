# frozen_string_literal: true

require 'test_helper'

class CartTest < Minitest::Test
  parallelize_me!

  def setup
    @cart = build(:cart)
    @mug = build(:product, sku: 'MUG', price: Shop::Money.parse('8.50 EUR'), stock: 5)
    @tea = build(:product, sku: 'TEA', price: Shop::Money.parse('3.25 EUR'), stock: 100)
  end

  def test_starts_empty
    assert_empty @cart
    assert_costs '0.00 EUR', @cart
  end

  def test_sums_subtotal
    @cart.add(@mug).add(@tea, 4)

    assert_costs '21.50 EUR', @cart
    assert_equal 5, @cart.item_count
  end

  def test_merges_repeated_adds
    @cart.add(@mug).add(@mug, 2)

    assert_equal 3, @cart.quantity('mug')
    assert_equal %w[MUG], @cart.items.map(&:sku)
  end

  def test_refuses_to_oversell
    @cart.add(@mug, 5)
    error = assert_raises(Shop::Cart::OutOfStock) { @cart.add(@mug) }
    assert_equal 'MUG: wanted 6, have 5', error.message
  end

  def test_refuses_other_currency
    assert_raises(Shop::Money::CurrencyMismatch) { @cart.add(build(:product, :usd)) }
  end

  def test_rejects_zero_quantity
    assert_raises(ArgumentError) { @cart.add(@mug, 0) }
  end

  def test_partial_remove
    @cart.add(@tea, 4).remove('tea', 3)

    assert_equal 1, @cart.quantity('TEA')
  end

  def test_full_remove
    @cart.add(@tea, 4).remove('TEA')

    assert_empty @cart
  end

  def test_remove_unknown_is_a_noop
    assert_same @cart, @cart.remove('NOPE')
  end

  def test_factory_trait_with_items
    assert_equal 3, build(:cart, :with_items).items.size
  end
end
