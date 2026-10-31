FactoryBot.define do
  factory :comment do
    post
    association :user
    body { Faker::Lorem.sentence(word_count: 6) }
  end
end
