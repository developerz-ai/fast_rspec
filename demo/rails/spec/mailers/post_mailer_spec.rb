require "rails_helper"

RSpec.describe PostMailer do
  describe ".published" do
    let(:post) { create(:post, :published, title: "Ship it") }
    let(:mail) { described_class.published(post) }

    it "addresses the author" do
      expect(mail.to).to eq([ post.user.email ])
      expect(mail.from).to eq([ "blog@example.com" ])
      expect(mail.subject).to eq('Your post "Ship it" is live')
    end

    it "is multipart with a link" do
      expect(mail.parts.map(&:mime_type)).to contain_exactly("text/plain", "text/html")
      expect(mail.text_part.body.to_s).to include("http://example.com/posts/#{post.to_param}")
    end

    it "is delivered" do
      expect { mail.deliver_now }.to change(ActionMailer::Base.deliveries, :size).by(1)
    end
  end
end
