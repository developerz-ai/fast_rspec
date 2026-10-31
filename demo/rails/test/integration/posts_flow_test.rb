require "test_helper"

class PostsFlowTest < ActionDispatch::IntegrationTest
  setup { @author = create(:user, name: "Ada Lovelace") }

  test "index lists published posts only" do
    create(:post, :published, title: "Visible")
    create(:post, title: "Hidden draft")

    get posts_path

    assert_response :success
    assert_select "#posts li", count: 1
    assert_includes response.body, "Visible"
    assert_not_includes response.body, "Hidden draft"
  end

  test "index renders an empty state" do
    get root_path
    assert_select "p", "No posts yet."
  end

  test "index serves JSON" do
    post = create(:post, :published, title: "JSON post")
    get posts_path(format: :json)
    assert_equal [ [ post.id, "JSON post" ] ], response.parsed_body.map { |p| p.values_at("id", "title") }
  end

  test "show renders the post and its comments" do
    post = create(:post, :published, :with_comments, user: @author)
    get post_path(post)
    assert_select "h1", post.title
    assert_select "h2", "2 comments"
    assert_select ".comment", 2
  end

  test "show 404s for unknown posts" do
    get post_path(id: 0)
    assert_response :not_found
  end

  test "create a post" do
    assert_difference -> { Post.count }, 1 do
      post posts_path, params: { post: attributes_for(:post, title: "Fresh").merge(user_id: @author.id) }
    end
    assert_redirected_to Post.last
    follow_redirect!
    assert_select "#notice", "Post created."
  end

  test "create re-renders the form on invalid input" do
    assert_no_difference -> { Post.count } do
      post posts_path, params: { post: { title: "", body: "", user_id: @author.id } }
    end
    assert_response :unprocessable_content
    assert_select "#errors li", "Title can't be blank"
  end

  test "publish enqueues the job" do
    post = create(:post, user: @author)
    assert_enqueued_with(job: PublishPostJob, args: [ post ], queue: "default") do
      patch publish_post_path(post)
    end
    assert_redirected_to post_path(post)
  end

  test "commenting adds a comment and emails the author" do
    post = create(:post, :published, user: @author)
    reader = create(:user)
    assert_difference -> { Comment.count }, 1 do
      assert_enqueued_emails 1 do
        post post_comments_path(post), params: { comment: { body: "Great read!", user_id: reader.id } }
      end
    end
    assert_redirected_to post_path(post)
  end

  test "commenting flashes validation errors" do
    post = create(:post, :published, user: @author)
    post post_comments_path(post), params: { comment: { body: "x", user_id: create(:user).id } }
    follow_redirect!
    assert_select "#alert", /Body is too short/
  end

  test "stats returns aggregates" do
    create(:post, :published, user: @author)
    get stats_path
    assert_equal({ "total" => 1, "published" => 1, "top_author" => "Ada Lovelace" },
                 response.parsed_body.slice("total", "published", "top_author"))
  end
end
