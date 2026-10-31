# frozen_string_literal: true

require 'vcr'

VCR.configure do |c|
  c.cassette_library_dir = File.expand_path('../cassettes', __dir__)
  c.hook_into :webmock
  c.configure_rspec_metadata!
  c.default_cassette_options = { record: :none, match_requests_on: %i[method uri] }
  c.filter_sensitive_data('<RATES_API_KEY>') { ENV.fetch('RATES_API_KEY', 'test-key') }
end
