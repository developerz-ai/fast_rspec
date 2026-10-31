require "rails_helper"

RSpec.describe User do
  subject(:user) { build(:user) }

  describe "associations" do
    it { is_expected.to have_many(:posts).dependent(:destroy) }
    it { is_expected.to have_many(:comments).dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(80) }
    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_inclusion_of(:role).in_array(User::ROLES) }
    it { is_expected.to allow_value("someone@example.com").for(:email) }
    it { is_expected.not_to allow_value("not-an-email").for(:email) }

    context "with an existing user" do
      subject { create(:user) }

      it { is_expected.to validate_uniqueness_of(:email).case_insensitive }
    end
  end

  it "normalizes the email" do
    expect(described_class.new(email: "  Ada@Example.COM ").email).to eq("ada@example.com")
  end

  it "has a unique index on email even when validations are skipped" do
    create(:user, email: "dup@example.com")
    dup = build(:user, email: "dup@example.com")
    expect { dup.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "uses factory sequences for unique emails" do
    expect(create_list(:user, 3).map(&:email).uniq.size).to eq(3)
  end

  describe "#display_name" do
    it "marks admins" do
      admin = build(:admin, name: "Ada")
      expect(admin.display_name).to eq("Ada (admin)")
      expect(admin).to be_admin
    end

    it "is just the name for members" do
      expect(build(:user, name: "Grace").display_name).to eq("Grace")
    end
  end

  it "destroys dependent posts" do
    user = create(:user)
    create_list(:post, 2, user: user)
    expect { user.destroy }.to change(Post, :count).by(-2)
  end
end
