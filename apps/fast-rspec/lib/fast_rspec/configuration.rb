# frozen_string_literal: true

module FastRspec
  # User-facing knobs. Defaults are the zero-config path; every field is optional.
  class Configuration
    attr_accessor :workers, :pool

    def initialize
      @workers = Integer(ENV.fetch('FAST_RSPEC_WORKERS', Etc.nprocessors))
      @pool = (ENV['FAST_RSPEC_POOL'] || default_pool).to_sym
      @disabled = []
    end

    def batteries = self

    def disable(*names) = @disabled.concat(names.map(&:to_sym))

    def disabled?(name) = @disabled.include?(name.to_sym)

    private

    # fork where it's cheap and real (CRuby); threads where there is no GVL.
    def default_pool
      RUBY_ENGINE == 'ruby' && Process.respond_to?(:fork) ? :fork : :thread
    end
  end
end

require 'etc'
