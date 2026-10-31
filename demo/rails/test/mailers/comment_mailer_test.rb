require "test_helper"

class CommentMailerTest < ActionMailer::TestCase
  setup do
    @comment = create(:comment, body: "Lovely post")
    @mail = CommentMailer.new_comment(@comment)
  end

  test "goes to the post author with reply-to the commenter" do
    assert_equal [ @comment.post.user.email ], @mail.to
    assert_equal [ @comment.user.email ], @mail.reply_to
  end

  test "quotes the comment" do
    assert_includes @mail.body.encoded, "Lovely post"
    assert_includes @mail.body.encoded, @comment.user.name
  end

  test "can be enqueued" do
    assert_enqueued_email_with(CommentMailer, :new_comment, args: [ @comment ]) do
      CommentMailer.new_comment(@comment).deliver_later
    end
  end
end
