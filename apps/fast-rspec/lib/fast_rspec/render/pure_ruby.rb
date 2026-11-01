# frozen_string_literal: true

module FastRspec
  # Pure-Ruby twin of FastRspec::Native (JRuby, TruffleRuby, failed ext build).
  module PureRuby
    module_function

    def engine = 'pure_ruby'
  end
end
