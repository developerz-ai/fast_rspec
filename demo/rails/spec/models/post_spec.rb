require "rails_helper"

RSpec.describe Post do
  describe "associations and validations" do
    subject { build(:post) }

    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:comments).dependent(:destroy) }
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_length_of(:title).is_at_most(120) }
    it { is_expected.to validate_presence_of(:body) }
  end

  describe "slug" do
    it "is derived from the title" do
      expect(create(:post, title: "Hello, World!").slug).to eq("hello-world")
    end

    it "stays unique when titles collide" do
      first = create(:post, title: "Same title")
      second = create(:post, title: "Same title")
      expect(second.slug).to start_with("same-title-")
      expect(second.slug).not_to eq(first.slug)
    end

    it "is backed by a unique index" do
      create(:post, slug: "taken")
      expect { build(:post, slug: "taken").save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "scopes" do
    let!(:published) { create(:post, :published) }
    let!(:draft) { create(:post) }
    let!(:scheduled) { create(:post, :scheduled) }

    it ".published excludes drafts and future posts" do
      expect(described_class.published).to contain_exactly(published)
    end

    it ".drafts" do
      expect(described_class.drafts).to contain_exactly(draft)
    end

    it ".recent orders newest first" do
      older = create(:post, published_at: 3.days.ago)
      expect(described_class.published.recent).to eq([ published, older ])
    end

    it "a scheduled post becomes published once its time comes" do
      travel_to 8.days.from_now do
        expect(described_class.published).to include(scheduled)
      end
    end

    it ".published_since" do
      travel_to Time.zone.local(2026, 10, 31, 12) do
        old = create(:post, published_at: 10.days.ago)
        fresh = create(:post, published_at: 1.hour.ago)
        expect(described_class.published_since(2.days.ago)).to include(fresh)
        expect(described_class.published_since(2.days.ago)).not_to include(old)
      end
    end
  end

  describe "#publish!" do
    it "stamps the current time" do
      freeze_time do
        post = create(:post)
        post.publish!
        expect(post.reload.published_at).to eq(Time.current)
        expect(post).to be_published
      end
    end

    it "accepts a future time without being published yet" do
      post = create(:post)
      post.publish!(at: 1.hour.from_now)
      expect(post).not_to be_published
    end
  end

  describe "#reading_time_minutes" do
    it("is at least one minute") { expect(build(:post, body: "short").reading_time_minutes).to eq(1) }
    it("scales with length") { expect(build(:post, :long).reading_time_minutes).to eq(4) }
  end

  it "builds stubbed records without touching the DB" do
    post = build_stubbed(:post, :published)
    expect(post).to be_persisted
    expect(post.user).to be_a(User)
  end

  it "uses the id and slug in URLs" do
    post = create(:post, title: "Param test")
    expect(post.to_param).to eq("#{post.id}-param-test")
  end
end
