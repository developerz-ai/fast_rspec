# frozen_string_literal: true

# A small shop domain: money, catalog, carts, pricing, orders, an HTTP rates client,
# a CSV/JSON importer and two thread-safe helpers. Stdlib only.
module Shop
  Error = Class.new(StandardError)
end

require_relative 'shop/version'
require_relative 'shop/money'
require_relative 'shop/product'
require_relative 'shop/cart'
require_relative 'shop/discounts'
require_relative 'shop/pricing'
require_relative 'shop/counter'
require_relative 'shop/order'
require_relative 'shop/cache'
require_relative 'shop/exchange_rates'
require_relative 'shop/importer'
