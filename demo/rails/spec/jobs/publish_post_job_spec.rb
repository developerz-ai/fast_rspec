require "rails_helper"

RSpec.describe PublishPostJob do
  let(:post) { create(:post) }

  it "is enqueued on the default queue" do
    expect { described_class.perform_later(post) }.to have_enqueued_job.with(post).on_queue("default")
  end

  it "publishes the post and emails the author" do
    freeze_time do
      expect { described_class.perform_now(post) }.to have_enqueued_mail(PostMailer, :published).with(post)
      expect(post.reload.published_at).to eq(Time.current)
    end
  end

  it "is a no-op for already published posts" do
    post.publish!(at: 2.days.ago)
    expect { described_class.perform_now(post) }.not_to have_enqueued_mail
  end

  it "delivers the email when jobs are performed" do
    perform_enqueued_jobs do
      described_class.perform_later(post)
    end
    expect(ActionMailer::Base.deliveries.last.to).to eq([ post.user.email ])
  end
end
