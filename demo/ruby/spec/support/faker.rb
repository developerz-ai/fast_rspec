# frozen_string_literal: true

require 'faker'

RSpec.configure do |config|
  config.before(:suite) { Faker::Config.random = Random.new(config.seed) }
  config.after { Faker::UniqueGenerator.clear }
end
