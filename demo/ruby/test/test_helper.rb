# frozen_string_literal: true

if ENV['COVERAGE']
  require 'simplecov'
  SimpleCov.start do
    command_name 'minitest'
    enable_coverage :branch
    add_filter %r{\A/(spec|test)/}
    add_group 'Library', 'lib'
  end
end

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'shop'

require 'minitest/autorun'
require 'minitest/mock'
require 'webmock/minitest'
require 'vcr'
require 'factory_bot'
require 'faker'
require 'fileutils'
require 'json'
require 'tmpdir'

WebMock.disable_net_connect!(allow_localhost: true)

VCR.configure do |c|
  c.cassette_library_dir = File.expand_path('cassettes', __dir__)
  c.hook_into :webmock
  c.default_cassette_options = { record: :none, match_requests_on: %i[method uri] }
  c.filter_sensitive_data('<RATES_API_KEY>') { ENV.fetch('RATES_API_KEY', 'test-key') }
end

FactoryBot.definition_file_paths = [File.expand_path('factories', __dir__)]
FactoryBot.find_definitions

Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |f| require f }

module Minitest
  class Test
    include FactoryBot::Syntax::Methods
    include ShopAssertions
    include TmpHelpers
    include FakerReset
  end
end
