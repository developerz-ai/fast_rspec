require "test_helper"

class CommentTest < ActiveSupport::TestCase
  subject { build(:comment) }

  should belong_to(:post).counter_cache(true)
  should belong_to(:user)
  should validate_presence_of(:body)
  should validate_length_of(:body).is_at_least(3).is_at_most(1_000)

  test "bumps the post's counter cache" do
    post = create(:post)
    assert_difference -> { post.reload.comments_count }, 1 do
      create(:comment, post: post)
    end
  end

  test "emails the post author about someone else's comment" do
    post = create(:post)
    assert_enqueued_email_with CommentMailer, :new_comment, args: ->(args) { args.first.is_a?(Comment) } do
      create(:comment, post: post)
    end
  end

  test "does not email authors about their own comments" do
    post = create(:post)
    assert_no_enqueued_emails do
      create(:comment, post: post, user: post.user)
    end
  end

  test "builds a post with comments via a trait" do
    post = create(:post, :with_comments, number_of_comments: 3)
    assert_equal 3, post.comments.count
    assert_equal 3, post.comments_count
  end
end
