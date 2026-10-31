require "capybara/rspec"
require "capybara/cuprite"

# Headless Chrome via CDP. JS specs skip cleanly when Chrome is missing or DEMO_JS=0.
module DemoJS
  BROWSERS = %w[google-chrome google-chrome-stable chromium chromium-browser].freeze

  def self.browser_path
    ENV["BROWSER_PATH"].presence ||
      BROWSERS.lazy.filter_map { |b| ENV["PATH"].split(":").map { |d| File.join(d, b) }.find { |p| File.executable?(p) } }.first
  end

  def self.available?
    ENV["DEMO_JS"] != "0" && browser_path.present?
  end
end

Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(app, window_size: [ 1200, 800 ], headless: true, process_timeout: 20,
                                     browser_path: DemoJS.browser_path,
                                     browser_options: { "no-sandbox" => nil })
end

Capybara.default_max_wait_time = 3

RSpec.configure do |config|
  config.before(:each, type: :system) do
    driven_by :rack_test
  end

  config.before(:each, type: :system, js: true) do
    skip "Chrome not available (or DEMO_JS=0)" unless DemoJS.available?
    driven_by :cuprite
  end
end
