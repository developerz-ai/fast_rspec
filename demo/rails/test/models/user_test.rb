require "test_helper"

class UserTest < ActiveSupport::TestCase
  context "associations" do
    subject { build(:user) }

    should have_many(:posts).dependent(:destroy)
    should have_many(:comments).dependent(:destroy)
  end

  context "validations" do
    subject { build(:user) }

    should validate_presence_of(:name)
    should validate_length_of(:name).is_at_most(80)
    should validate_presence_of(:email)
    should validate_inclusion_of(:role).in_array(User::ROLES)
    should allow_value("someone@example.com").for(:email)
    should_not allow_value("not-an-email").for(:email)
  end

  context "with an existing user" do
    subject { create(:user) }

    should validate_uniqueness_of(:email).case_insensitive
  end

  test "normalizes the email" do
    assert_equal "ada@example.com", User.new(email: "  Ada@Example.COM ").email
  end

  test "has a unique index on email even when validations are skipped" do
    create(:user, email: "dup@example.com")
    assert_raises(ActiveRecord::RecordNotUnique) { build(:user, email: "dup@example.com").save!(validate: false) }
  end

  test "factory sequences give unique emails" do
    assert_equal 3, create_list(:user, 3).map(&:email).uniq.size
  end

  context "#display_name" do
    should "mark admins" do
      admin = build(:admin, name: "Ada")
      assert_equal "Ada (admin)", admin.display_name
      assert_predicate admin, :admin?
    end

    should "be just the name for members" do
      assert_equal "Grace", build(:user, name: "Grace").display_name
    end
  end

  test "destroys dependent posts" do
    user = create(:user)
    create_list(:post, 2, user: user)
    assert_difference -> { Post.count }, -2 do
      user.destroy
    end
  end
end
