require "webmock/minitest"
require "vcr"

WebMock.disable_net_connect!(allow_localhost: true)

VCR.configure do |config|
  config.cassette_library_dir = Rails.root.join("test/cassettes").to_s
  config.hook_into :webmock
  config.ignore_localhost = true
  config.default_cassette_options = { record: :none, match_requests_on: %i[method host path query] }
  config.filter_sensitive_data("<WEATHER_API_KEY>") { ENV.fetch("WEATHER_API_KEY", "demo-key") }
end
