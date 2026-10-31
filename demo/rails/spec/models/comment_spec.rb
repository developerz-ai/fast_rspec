require "rails_helper"

RSpec.describe Comment do
  subject { build(:comment) }

  it { is_expected.to belong_to(:post).counter_cache(true) }
  it { is_expected.to belong_to(:user) }
  it { is_expected.to validate_presence_of(:body) }
  it { is_expected.to validate_length_of(:body).is_at_least(3).is_at_most(1_000) }

  it "bumps the post's counter cache" do
    post = create(:post)
    expect { create(:comment, post: post) }.to change { post.reload.comments_count }.from(0).to(1)
  end

  it "emails the post author about someone else's comment" do
    post = create(:post)
    expect { create(:comment, post: post) }.to have_enqueued_mail(CommentMailer, :new_comment)
  end

  it "does not email authors about their own comments" do
    post = create(:post)
    expect { create(:comment, post: post, user: post.user) }.not_to have_enqueued_mail
  end

  it "builds a post with comments via a trait" do
    post = create(:post, :with_comments, number_of_comments: 3)
    expect(post.comments.count).to eq(3)
    expect(post.comments_count).to eq(3)
  end
end
