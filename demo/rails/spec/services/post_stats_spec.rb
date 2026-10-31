require "rails_helper"

RSpec.describe PostStats do
  # Slow on purpose (stand-in for a heavy reporting query) so parallel speedup is visible.
  subject(:stats) { described_class.new(delay: 0.2).call }

  let(:ada) { create(:user, name: "Ada") }

  before do
    create_list(:post, 2, :published, user: ada)
    create(:post, :with_comments, number_of_comments: 2)
  end

  it("counts all posts") { expect(stats[:total]).to eq(3) }
  it("counts published posts") { expect(stats[:published]).to eq(2) }
  it("counts drafts") { expect(stats[:drafts]).to eq(1) }
  it("sums comments from the counter cache") { expect(stats[:comments]).to eq(2) }
  it("finds the top author") { expect(stats[:top_author]).to eq("Ada") }

  it "can be scoped" do
    expect(described_class.new(Post.published).call).to include(total: 2, drafts: 0)
  end
end
