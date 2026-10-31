# Coverage must start before any application code is loaded.
if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start "rails" do
    command_name "minitest"
    add_group "Services", "app/services"
  end
end

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"

Rails.root.glob("test/support/**/*.rb").sort_by(&:to_s).each { |f| require f }

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Each forked worker writes its own coverage result; SimpleCov merges them.
    parallelize_setup do |worker|
      SimpleCov.command_name "minitest-#{worker}" if ENV["COVERAGE"]
    end

    parallelize_teardown do
      SimpleCov.result if ENV["COVERAGE"]
    end

    include FactoryBot::Syntax::Methods
    include ActionMailer::TestHelper
    include ActiveJob::TestHelper
  end
end
