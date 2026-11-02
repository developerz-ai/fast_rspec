# frozen_string_literal: true

require 'test_helper'

class VersionTest < Bootstrap::Test
  def test_version
    refute_nil FastRspec::VERSION
  end
end
