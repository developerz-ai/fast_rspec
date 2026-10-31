# frozen_string_literal: true

require 'test_helper'

class OrderTest < Minitest::Test
  parallelize_me!

  def setup
    mug = build(:product, sku: 'MUG', price: Shop::Money.parse('8.00 EUR'))
    @cart = build(:cart, products: [mug], quantity: 2)
    @ids = Minitest::Mock.new
    @ids.expect(:next_id, 'ORD-000042', ['ORD'])
    @order = Shop::Order.place(@cart, ids: @ids, now: Time.utc(2026, 10, 31, 12))
  end

  def test_placed_pending_with_counter_id
    assert_equal 'ORD-000042', @order.id
    assert_predicate @order, :pending?
    assert_costs '16.00 EUR', @order
    assert_mock @ids
  end

  def test_empty_cart
    assert_raises(Shop::Order::EmptyCart) { Shop::Order.place(Shop::Cart.new) }
  end

  def test_snapshots_lines
    @cart.clear

    assert_equal %w[MUG], @order.lines.map(&:sku)
  end

  def test_default_counter_can_be_stubbed
    Shop::Order::IDS.stub(:next_id, 'ORD-STUB') do
      assert_equal 'ORD-STUB', Shop::Order.place(@cart).id
    end
  end

  def test_allowed_transitions
    assert_transition @order, :paid
    assert_transition @order, :cancelled
    refute_transition @order, :shipped
  end

  def test_happy_path
    @order.pay!.ship!.deliver!

    assert_predicate @order, :delivered?
    assert_predicate @order, :final?
    assert_equal %i[pending paid shipped delivered], @order.history
  end

  def test_invalid_transition
    @order.cancel!
    error = assert_raises(Shop::Order::InvalidTransition) { @order.pay! }
    assert_equal 'ORD-000042: cancelled -> paid', error.message
  end

  def test_refund
    assert_equal :refunded, @order.pay!.refund!.status
  end

  def test_json
    json = JSON.parse(@order.to_json)

    assert_equal '2026-10-31T12:00:00Z', json['placed_at']
    assert_equal '16.00 EUR', json['total']
    assert_equal [{ 'sku' => 'MUG', 'quantity' => 2, 'total' => '16.00 EUR' }], json['lines']
  end
end
