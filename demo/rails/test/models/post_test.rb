require "test_helper"

class PostTest < ActiveSupport::TestCase
  context "associations and validations" do
    subject { build(:post) }

    should belong_to(:user)
    should have_many(:comments).dependent(:destroy)
    should validate_presence_of(:title)
    should validate_length_of(:title).is_at_most(120)
    should validate_presence_of(:body)
  end

  context "slug" do
    should "be derived from the title" do
      assert_equal "hello-world", create(:post, title: "Hello, World!").slug
    end

    should "stay unique when titles collide" do
      first = create(:post, title: "Same title")
      second = create(:post, title: "Same title")
      assert_match(/\Asame-title-/, second.slug)
      refute_equal first.slug, second.slug
    end

    should "be backed by a unique index" do
      create(:post, slug: "taken")
      assert_raises(ActiveRecord::RecordNotUnique) { build(:post, slug: "taken").save!(validate: false) }
    end
  end

  context "scopes" do
    setup do
      @published = create(:post, :published)
      @draft = create(:post)
      @scheduled = create(:post, :scheduled)
    end

    should "exclude drafts and future posts from .published" do
      assert_equal [ @published ], Post.published.to_a
    end

    should "find .drafts" do
      assert_equal [ @draft ], Post.drafts.to_a
    end

    should "order .recent newest first" do
      older = create(:post, published_at: 3.days.ago)
      assert_equal [ @published, older ], Post.published.recent.to_a
    end

    should "publish a scheduled post once its time comes" do
      travel_to 8.days.from_now do
        assert_includes Post.published, @scheduled
      end
    end

    should "filter .published_since" do
      travel_to Time.zone.local(2026, 10, 31, 12) do
        old = create(:post, published_at: 10.days.ago)
        fresh = create(:post, published_at: 1.hour.ago)
        assert_includes Post.published_since(2.days.ago), fresh
        refute_includes Post.published_since(2.days.ago), old
      end
    end
  end

  context "#publish!" do
    should "stamp the current time" do
      freeze_time do
        post = create(:post)
        post.publish!
        assert_equal Time.current, post.reload.published_at
        assert_predicate post, :published?
      end
    end

    should "accept a future time without being published yet" do
      post = create(:post)
      post.publish!(at: 1.hour.from_now)
      refute_predicate post, :published?
    end
  end

  test "reading time is at least one minute" do
    assert_equal 1, build(:post, body: "short").reading_time_minutes
  end

  test "reading time scales with length" do
    assert_equal 4, build(:post, :long).reading_time_minutes
  end

  test "build_stubbed records look persisted without touching the DB" do
    post = build_stubbed(:post, :published)
    assert_predicate post, :persisted?
    assert_kind_of User, post.user
  end

  test "uses the id and slug in URLs" do
    post = create(:post, title: "Param test")
    assert_equal "#{post.id}-param-test", post.to_param
  end
end
