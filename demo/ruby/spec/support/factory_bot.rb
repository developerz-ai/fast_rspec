# frozen_string_literal: true

require 'factory_bot'

FactoryBot.definition_file_paths = [File.expand_path('../factories', __dir__)]

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
  config.before(:suite) { FactoryBot.find_definitions }
end
