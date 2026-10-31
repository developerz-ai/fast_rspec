require "test_helper"

class PublishPostJobTest < ActiveJob::TestCase
  setup { @post = create(:post) }

  test "is enqueued on the default queue" do
    assert_enqueued_with(job: PublishPostJob, args: [ @post ], queue: "default") do
      PublishPostJob.perform_later(@post)
    end
  end

  test "publishes the post and emails the author" do
    freeze_time do
      assert_enqueued_email_with PostMailer, :published, args: [ @post ] do
        PublishPostJob.perform_now(@post)
      end
      assert_equal Time.current, @post.reload.published_at
    end
  end

  test "is a no-op for already published posts" do
    @post.publish!(at: 2.days.ago)
    assert_no_enqueued_emails { PublishPostJob.perform_now(@post) }
  end

  test "delivers the email when jobs are performed" do
    perform_enqueued_jobs { PublishPostJob.perform_later(@post) }
    assert_equal [ @post.user.email ], ActionMailer::Base.deliveries.last.to
  end
end
