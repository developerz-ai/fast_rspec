# frozen_string_literal: true

module ShopAssertions
  # assert_costs '12.50 EUR', cart_or_quote_or_order
  def assert_costs(expected, actual, msg = nil)
    expected = Shop::Money.parse(expected) unless expected.is_a?(Shop::Money)
    amount = if actual.is_a?(Shop::Money) then actual
             elsif actual.respond_to?(:total) then actual.total
             else actual.subtotal
             end
    msg = message(msg) { "Expected #{actual.class} to cost #{expected}, but it costs #{amount}" }
    assert(amount == expected, msg)
  end

  def assert_transition(order, target)
    assert order.can?(target), "expected #{order.status} -> #{target} to be allowed"
  end

  def refute_transition(order, target)
    refute order.can?(target), "expected #{order.status} -> #{target} to be forbidden"
  end
end
