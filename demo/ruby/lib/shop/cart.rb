# frozen_string_literal: true

module Shop
  class Cart
    OutOfStock = Class.new(Shop::Error)
    LineItem = Data.define(:product, :quantity) do
      def total = product.price * quantity
      def sku = product.sku
    end

    attr_reader :currency

    def initialize(currency: 'EUR')
      @currency = currency
      @lines = {}
    end

    def add(product, quantity = 1)
      raise ArgumentError, 'quantity must be positive' unless quantity.positive?
      raise Money::CurrencyMismatch, "cart is #{currency}" unless product.price.currency == currency

      wanted = quantity(product.sku) + quantity
      raise OutOfStock, "#{product.sku}: wanted #{wanted}, have #{product.stock}" unless product.in_stock?(wanted)

      @lines[product.sku] = LineItem.new(product: product, quantity: wanted)
      self
    end

    def remove(sku, quantity = nil)
      line = @lines[sku.to_s.upcase] or return self
      left = quantity ? line.quantity - quantity : 0
      if left.positive?
        @lines[line.sku] = line.with(quantity: left)
      else
        @lines.delete(line.sku)
      end
      self
    end

    def quantity(sku) = @lines[sku.to_s.upcase]&.quantity || 0
    def items = @lines.values
    def empty? = @lines.empty?
    def item_count = items.sum(&:quantity)
    def subtotal = items.map(&:total).reduce(Money.zero(currency), :+)

    def clear
      @lines.clear
      self
    end
  end
end
