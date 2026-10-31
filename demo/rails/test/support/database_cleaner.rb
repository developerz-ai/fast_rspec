require "database_cleaner/active_record"

# Plain tests use Rails' transactional tests. JS system tests run the app in a server thread
# and a real browser, so they opt out and truncate instead.
module TruncationCleaning
  extend ActiveSupport::Concern

  included do
    self.use_transactional_tests = false

    setup do
      DatabaseCleaner.strategy = :truncation
      DatabaseCleaner.start
    end

    teardown do
      DatabaseCleaner.clean
    end
  end
end

ActiveSupport.on_load(:active_support_test_case) do
  # Each parallel worker gets a fresh DB from Rails; serial runs start from a clean main DB.
  parallelize_setup { |_worker| DatabaseCleaner.clean_with(:deletion) }
end

DatabaseCleaner.clean_with(:deletion)
