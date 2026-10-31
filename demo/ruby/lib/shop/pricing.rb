# frozen_string_literal: true

module Shop
  # Turns a cart + discounts into a Quote. `:best` applies the single largest discount,
  # `:stack` applies all of them; the total never goes below zero.
  class Pricing
    Quote = Data.define(:subtotal, :discount, :tax, :total, :applied)

    STRATEGIES = %i[best stack].freeze

    def initialize(discounts: [], strategy: :best, tax_rate: 0, clock: -> { Time.now })
      raise ArgumentError, "unknown strategy #{strategy.inspect}" unless STRATEGIES.include?(strategy)

      @discounts = discounts
      @strategy = strategy
      @tax_rate = Rational(tax_rate.to_s)
      @clock = clock
    end

    def quote(cart, codes: [])
      subtotal = cart.subtotal
      now = @clock.call
      candidates = @discounts.select { |d| d.applicable?(cart, codes: codes, now: now) }
                             .map { |d| [d, d.amount_for(cart)] }
                             .reject { |_, amount| amount.zero? }
      chosen = @strategy == :best ? [candidates.max_by { |_, amount| amount.cents }].compact : candidates

      discount = [chosen.map(&:last).reduce(Money.zero(cart.currency), :+), subtotal].min
      taxable = (subtotal - discount).clamp_zero
      tax = taxable * @tax_rate
      Quote.new(subtotal: subtotal, discount: discount, tax: tax, total: taxable + tax,
                applied: chosen.map { |d, _| d.name })
    end
  end
end
