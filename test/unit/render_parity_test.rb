# frozen_string_literal: true

require 'test_helper'
require 'fast_rspec/render/pure_ruby'

# Every C fast path has a pure-Ruby twin; this is where they are held equal.
class RenderParityTest < Bootstrap::Test
  def test_selects_an_implementation
    assert_includes %w[native pure_ruby], FastRspec::Render::IMPL.engine
  end
end
