# frozen_string_literal: true

module Shop
  Product = Data.define(:sku, :name, :price, :category, :stock) do
    def initialize(sku:, name:, price:, category: 'general', stock: 0)
      raise ArgumentError, 'sku must be present' if sku.to_s.strip.empty?
      raise ArgumentError, 'price must be Shop::Money' unless price.is_a?(Shop::Money)
      raise ArgumentError, 'price must not be negative' if price.negative?
      raise ArgumentError, 'stock must be >= 0' if stock.negative?

      super(sku: sku.to_s.upcase.freeze, name: name.to_s.freeze, price: price, category: category.to_s.freeze,
            stock: Integer(stock))
    end

    def in_stock?(quantity = 1) = stock >= quantity

    def to_h = { sku: sku, name: name, price: price.to_s, category: category, stock: stock }
  end
end
