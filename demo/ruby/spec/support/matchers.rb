# frozen_string_literal: true

# expect(cart).to cost('12.50 EUR')  — works on anything with #total or #subtotal.
RSpec::Matchers.define :cost do |expected|
  expected_money = expected.is_a?(Shop::Money) ? expected : Shop::Money.parse(expected)

  def amount_of(actual)
    return actual if actual.is_a?(Shop::Money)

    actual.respond_to?(:total) ? actual.total : actual.subtotal
  end

  match { |actual| amount_of(actual) == expected_money }

  description { "cost #{expected_money}" }

  failure_message do |actual|
    "expected #{actual.class} to cost #{expected_money}, but it costs #{amount_of(actual)}"
  end

  failure_message_when_negated { |_actual| "expected not to cost #{expected_money}" }
end

# expect(order).to allow_transition_to(:paid)
RSpec::Matchers.define :allow_transition_to do |target|
  match { |order| order.can?(target) }
  failure_message { |order| "expected #{order.status} -> #{target} to be allowed" }
  failure_message_when_negated { |order| "expected #{order.status} -> #{target} to be forbidden" }
end
