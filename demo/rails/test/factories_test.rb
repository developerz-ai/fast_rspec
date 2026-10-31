require "test_helper"

class FactoriesTest < ActiveSupport::TestCase
  test "all factories are valid (FactoryBot.lint, with traits)" do
    assert_nothing_raised { FactoryBot.lint traits: true }
  end
end
