# frozen_string_literal: true

module FastRspec
  # Picks the C fast path on CRuby, the pure-Ruby twin elsewhere.
  # Both must produce byte-identical output (see test/unit/render_parity_test.rb).
  module Render
    begin
      raise LoadError if ENV['FAST_RSPEC_DISABLE_EXT'] == '1' || RUBY_ENGINE != 'ruby'

      require_relative 'fast_rspec'
      IMPL = FastRspec::Native
    rescue LoadError
      require_relative 'render/pure_ruby'
      IMPL = FastRspec::PureRuby
    end

    def self.native? = IMPL.name == 'FastRspec::Native'
  end
end
