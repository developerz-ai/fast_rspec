# frozen_string_literal: true

module FakerReset
  def after_teardown
    Faker::UniqueGenerator.clear
    super
  end
end
