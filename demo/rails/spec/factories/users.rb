FactoryBot.define do
  factory :user do
    name { Faker::Name.name }
    sequence(:email) { |n| "user#{n}@example.com" }
    city { Faker::Address.city }

    trait :admin do
      role { "admin" }
    end

    trait :without_city do
      city { nil }
    end

    factory :admin, traits: [ :admin ]
  end
end
