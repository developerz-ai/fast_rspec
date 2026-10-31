require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :rack_test
end

class JavaScriptSystemTestCase < ApplicationSystemTestCase
  include TruncationCleaning

  driven_by :cuprite

  setup do
    skip "Chrome not available (or DEMO_JS=0)" unless DemoJS.available?
  end
end
