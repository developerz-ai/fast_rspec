# frozen_string_literal: true

module Shop
  # Each discount answers #amount_for(cart) with a non-negative Money in the cart's currency.
  module Discounts
    class Base
      attr_reader :name, :code, :expires_at

      def initialize(name:, code: nil, expires_at: nil)
        @name = name
        @code = code&.upcase
        @expires_at = expires_at
      end

      def applicable?(cart, codes: [], now: Time.now)
        return false if expires_at && now >= expires_at
        return false if code && !codes.map(&:upcase).include?(code)

        !cart.empty?
      end
    end

    class PercentOff < Base
      attr_reader :percent, :category

      def initialize(percent:, category: nil, **)
        raise ArgumentError, 'percent must be within 0..100' unless (0..100).cover?(percent)

        super(**)
        @percent = percent
        @category = category
      end

      def amount_for(cart)
        lines = category ? cart.items.select { |l| l.product.category == category } : cart.items
        lines.map(&:total).reduce(Money.zero(cart.currency), :+) * Rational(percent, 100)
      end
    end

    class FixedOff < Base
      attr_reader :amount, :min_subtotal

      def initialize(amount:, min_subtotal: nil, **)
        super(**)
        @amount = amount
        @min_subtotal = min_subtotal
      end

      def applicable?(cart, **)
        super && (min_subtotal.nil? || cart.subtotal >= min_subtotal)
      end

      def amount_for(cart) = [amount, cart.subtotal].min
    end

    # Buy `buy` of a SKU, get `free` more of it for nothing; repeats per full group.
    class BuyXGetY < Base
      attr_reader :sku, :buy, :free

      def initialize(sku:, buy:, free:, **)
        super(**)
        @sku = sku.upcase
        @buy = buy
        @free = free
      end

      def amount_for(cart)
        line = cart.items.find { |l| l.sku == sku }
        return Money.zero(cart.currency) unless line

        line.product.price * ((line.quantity / (buy + free)) * free)
      end
    end
  end
end
