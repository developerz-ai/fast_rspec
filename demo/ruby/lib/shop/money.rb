# frozen_string_literal: true

module Shop
  # Integer cents + ISO currency. Immutable; arithmetic across currencies raises.
  Money = Data.define(:cents, :currency) do
    include Comparable

    const_set(:CurrencyMismatch, Class.new(Shop::Error))
    const_set(:ParseError, Class.new(Shop::Error))

    def self.zero(currency = 'EUR') = new(cents: 0, currency: currency)

    # "12.50 EUR", "12 EUR", "-0.99 USD"
    def self.parse(text)
      match = /\A\s*(-?\d+)(?:\.(\d{1,2}))?\s+([A-Z]{3})\s*\z/.match(text.to_s)
      raise self::ParseError, "cannot parse money: #{text.inspect}" unless match

      whole = match[1].to_i
      frac = (match[2] || '0').ljust(2, '0').to_i
      sign = match[1].start_with?('-') ? -1 : 1
      new(cents: (whole * 100) + (sign * frac), currency: match[3])
    end

    def initialize(cents:, currency:)
      raise ArgumentError, 'cents must be an Integer' unless cents.is_a?(Integer)
      raise ArgumentError, "bad currency #{currency.inspect}" unless currency.to_s.match?(/\A[A-Z]{3}\z/)

      super(cents: cents, currency: currency.to_s.dup.freeze)
    end

    def +(other) = with(cents: cents + same_currency!(other).cents)
    def -(other) = with(cents: cents - same_currency!(other).cents)
    def -@ = with(cents: -cents)

    # Rounds half away from zero, like most tills.
    def *(factor)
      with(cents: (Rational(cents) * Rational(factor.to_s)).round(half: :up))
    end

    def <=>(other)
      return nil unless other.is_a?(Money) && other.currency == currency

      cents <=> other.cents
    end

    def zero? = cents.zero?
    def negative? = cents.negative?
    def positive? = cents.positive?
    def abs = with(cents: cents.abs)

    def clamp_zero = negative? ? with(cents: 0) : self

    # Splits into `ratios` parts without losing a cent; remainder goes to the first parts.
    def allocate(ratios)
      ratios = Array.new(ratios, 1) if ratios.is_a?(Integer)
      raise ArgumentError, 'need at least one ratio' if ratios.empty? || ratios.sum.zero?

      total = ratios.sum
      sign = cents.negative? ? -1 : 1
      parts = ratios.map { |r| sign * ((cents.abs * r) / total) }
      remainder = cents - parts.sum
      parts.each_index.take(remainder.abs).each { |i| parts[i] += sign }
      parts.map { |c| with(cents: c) }
    end

    def to_s
      sign = negative? ? '-' : ''
      format('%<sign>s%<whole>d.%<frac>02d %<cur>s', sign: sign, whole: cents.abs / 100, frac: cents.abs % 100,
                                                     cur: currency)
    end

    def inspect = "#<Shop::Money #{self}>"

    private

    def same_currency!(other)
      raise TypeError, "expected Shop::Money, got #{other.class}" unless other.is_a?(Money)
      raise self.class::CurrencyMismatch, "#{currency} vs #{other.currency}" unless other.currency == currency

      other
    end
  end
end
