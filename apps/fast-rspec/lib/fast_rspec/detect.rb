# frozen_string_literal: true

module FastRspec
  # What the host app has. Pure queries, no side effects — batteries decide what to do.
  module Detect
    module_function

    def rails? = defined?(::Rails::Railtie) ? true : false
    def active_record? = defined?(::ActiveRecord::Base) ? true : false
    def rspec? = File.exist?('.rspec') || Dir.exist?('spec')
    def minitest? = Dir.exist?('test')
    def gem?(name) = Gem.loaded_specs.key?(name)
  end
end
