require "test_helper"

class PostStatsTest < ActiveSupport::TestCase
  # Slow on purpose (stand-in for a heavy reporting query) so parallel speedup is visible.
  setup do
    ada = create(:user, name: "Ada")
    create_list(:post, 2, :published, user: ada)
    create(:post, :with_comments, number_of_comments: 2)
    @stats = PostStats.new(delay: 0.2).call
  end

  test("counts all posts") { assert_equal 3, @stats[:total] }
  test("counts published posts") { assert_equal 2, @stats[:published] }
  test("counts drafts") { assert_equal 1, @stats[:drafts] }
  test("sums comments from the counter cache") { assert_equal 2, @stats[:comments] }
  test("finds the top author") { assert_equal "Ada", @stats[:top_author] }

  test "can be scoped" do
    stats = PostStats.new(Post.published).call
    assert_equal [ 2, 0 ], stats.values_at(:total, :drafts)
  end
end
