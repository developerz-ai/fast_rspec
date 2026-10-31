require "rails_helper"

RSpec.describe CommentMailer do
  let!(:comment) { create(:comment, body: "Lovely post") }
  let(:mail) { described_class.new_comment(comment) }

  it "goes to the post author with reply-to the commenter" do
    expect(mail.to).to eq([ comment.post.user.email ])
    expect(mail.reply_to).to eq([ comment.user.email ])
  end

  it "quotes the comment" do
    expect(mail.body.encoded).to include("Lovely post", comment.user.name)
  end

  it "can be enqueued" do
    expect { described_class.new_comment(comment).deliver_later }.to have_enqueued_mail(described_class, :new_comment)
  end
end
