# frozen_string_literal: true

require 'test_helper'

class ProductTest < Minitest::Test
  parallelize_me!

  def setup
    @product = build(:product, sku: 'abc-1', name: 'Mug')
  end

  def test_normalizes_sku
    assert_equal 'ABC-1', @product.sku
  end

  def test_value_equality
    assert_equal build(:product, sku: 'ABC-1', name: 'Mug'), @product
    refute_equal build(:product, sku: 'ABC-2', name: 'Mug'), @product
    assert_predicate @product, :frozen?
  end

  def test_sequence_gives_unique_skus
    skus = build_list(:product, 5).map(&:sku)

    assert_equal 5, skus.uniq.size
    skus.each { |sku| assert_match(/\ASKU-\d{4}\z/, sku) }
  end

  def test_traits
    book = build(:product, :book, :cheap)

    assert_equal 'books', book.category
    assert_costs '1.00 EUR', book.price
  end

  def test_create_with_skip_create
    refute_predicate create(:product, :out_of_stock), :in_stock?
  end

  def test_in_stock_for_quantity
    assert @product.in_stock?(10)
    refute @product.in_stock?(11)
  end

  def test_to_h
    assert_equal({ sku: 'ABC-1', name: 'Mug', price: '19.99 EUR', category: 'general', stock: 10 }, @product.to_h)
  end

  def test_validations
    assert_raises(ArgumentError) { build(:product, sku: ' ') }
    assert_raises(ArgumentError) { build(:product, price: 5) }
    assert_raises(ArgumentError) { build(:product, stock: -1) }
    error = assert_raises(ArgumentError) { build(:product, price: Shop::Money.parse('-1 EUR')) }
    assert_match(/negative/, error.message)
  end
end
