# frozen_string_literal: true

FactoryBot.define do
  sequence(:sku) { |n| format('SKU-%04d', n) }

  factory :money, class: 'Shop::Money' do
    skip_create
    cents { 1000 }
    currency { 'EUR' }
    initialize_with { new(cents: cents, currency: currency) }

    trait(:usd) { currency { 'USD' } }
  end

  factory :product, class: 'Shop::Product' do
    skip_create
    sku { generate(:sku) }
    name { Faker::Commerce.product_name }
    price { Shop::Money.new(cents: 1999, currency: 'EUR') }
    category { 'general' }
    stock { 10 }
    initialize_with { new(**attributes) }

    trait :book do
      category { 'books' }
      name { Faker::Book.title }
    end
    trait(:cheap) { price { Shop::Money.new(cents: 100, currency: 'EUR') } }
    trait(:out_of_stock) { stock { 0 } }
    trait(:usd) { price { Shop::Money.new(cents: 2500, currency: 'USD') } }
    trait(:random_price) { price { Shop::Money.new(cents: Faker::Number.between(from: 100, to: 9_999), currency: 'EUR') } }
  end

  factory :cart, class: 'Shop::Cart' do
    skip_create
    transient do
      products { [] }
      quantity { 1 }
      currency { 'EUR' }
    end
    initialize_with { new(currency: currency) }
    after(:build) { |cart, ctx| ctx.products.each { |p| cart.add(p, ctx.quantity) } }

    trait(:with_items) { products { FactoryBot.build_list(:product, 3) } }
  end

  factory :percent_off, class: 'Shop::Discounts::PercentOff' do
    skip_create
    name { "#{percent}% off" }
    percent { 10 }
    category { nil }
    code { nil }
    expires_at { nil }
    initialize_with { new(**attributes) }

    trait(:books_only) { category { 'books' } }
    trait(:coupon) { code { Faker::Alphanumeric.unique.alpha(number: 8).upcase } }
    trait(:expired) { expires_at { Time.now - 3600 } }
  end

  factory :fixed_off, class: 'Shop::Discounts::FixedOff' do
    skip_create
    name { 'Five off' }
    amount { Shop::Money.new(cents: 500, currency: 'EUR') }
    min_subtotal { nil }
    code { nil }
    initialize_with { new(**attributes) }
  end

  factory :buy_x_get_y, class: 'Shop::Discounts::BuyXGetY' do
    skip_create
    name { '3 for 2' }
    sku { 'SKU-3FOR2' }
    buy { 2 }
    free { 1 }
    initialize_with { new(**attributes) }
  end
end
