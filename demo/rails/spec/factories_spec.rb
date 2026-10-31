require "rails_helper"

RSpec.describe "Factories" do
  it "are all valid (FactoryBot.lint, with traits)" do
    FactoryBot.lint traits: true
  end
end
