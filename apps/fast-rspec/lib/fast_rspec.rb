# frozen_string_literal: true

require_relative 'fast_rspec/version'

# One gem line replaces the whole test stack. See AGENTS.md and docs/idea/.
module FastRspec
  class Error < StandardError; end

  autoload :Configuration, 'fast_rspec/configuration'
  autoload :Detect,        'fast_rspec/detect'
  autoload :Render,        'fast_rspec/render'

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
    end
  end
end

require_relative 'fast_rspec/rails/railtie' if defined?(Rails::Railtie)
