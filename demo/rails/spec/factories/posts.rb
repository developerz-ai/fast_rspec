FactoryBot.define do
  factory :post do
    user
    title { Faker::Book.title }
    body { Faker::Lorem.paragraph(sentence_count: 4) }

    trait :published do
      published_at { 1.day.ago }
    end

    trait :scheduled do
      published_at { 1.week.from_now }
    end

    trait :long do
      body { Faker::Lorem.words(number: 650).join(" ") }
    end

    trait :with_comments do
      transient do
        number_of_comments { 2 }
      end

      after(:create) do |post, evaluator|
        create_list(:comment, evaluator.number_of_comments, post: post)
        post.reload
      end
    end
  end
end
