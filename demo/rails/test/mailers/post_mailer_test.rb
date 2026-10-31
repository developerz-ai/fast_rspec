require "test_helper"

class PostMailerTest < ActionMailer::TestCase
  setup do
    @post = create(:post, :published, title: "Ship it")
    @mail = PostMailer.published(@post)
  end

  test "addresses the author" do
    assert_equal [ @post.user.email ], @mail.to
    assert_equal [ "blog@example.com" ], @mail.from
    assert_equal 'Your post "Ship it" is live', @mail.subject
  end

  test "is multipart with a link" do
    assert_equal %w[text/html text/plain], @mail.parts.map(&:mime_type).sort
    assert_includes @mail.text_part.body.to_s, "http://example.com/posts/#{@post.to_param}"
  end

  test "is delivered" do
    assert_emails(1) { @mail.deliver_now }
  end
end
