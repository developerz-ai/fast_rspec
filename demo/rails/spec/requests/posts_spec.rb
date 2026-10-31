require "rails_helper"

RSpec.describe "Posts" do
  let(:author) { create(:user, name: "Ada Lovelace") }

  describe "GET /posts" do
    it "lists published posts only" do
      create(:post, :published, title: "Visible")
      create(:post, title: "Hidden draft")

      get posts_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Visible")
      expect(response.body).not_to include("Hidden draft")
    end

    it "renders an empty state" do
      get root_path
      expect(response.body).to include("No posts yet.")
    end

    it "serves JSON" do
      post = create(:post, :published, title: "JSON post")
      get posts_path(format: :json)
      expect(response.parsed_body).to contain_exactly(a_hash_including("id" => post.id, "title" => "JSON post"))
    end
  end

  describe "GET /posts/:id" do
    it "shows the post and its comments" do
      post = create(:post, :published, :with_comments, user: author)
      get post_path(post)
      expect(response.body).to include(post.title, "Ada Lovelace", "2 comments")
    end

    it "404s for unknown posts" do
      get post_path(id: 0)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /posts" do
    it "creates a post" do
      params = { post: attributes_for(:post, title: "Fresh").merge(user_id: author.id) }
      expect { post posts_path, params: params }.to change(Post, :count).by(1)
      expect(response).to redirect_to(Post.last)
      follow_redirect!
      expect(response.body).to include("Post created.")
    end

    it "re-renders the form on invalid input" do
      expect { post posts_path, params: { post: { title: "", body: "", user_id: author.id } } }.not_to change(Post, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Title can&#39;t be blank")
    end
  end

  describe "PATCH /posts/:id/publish" do
    it "enqueues the publish job" do
      post = create(:post, user: author)
      expect { patch publish_post_path(post) }.to have_enqueued_job(PublishPostJob).with(post).on_queue("default")
      expect(response).to redirect_to(post_path(post))
    end
  end

  describe "POST /posts/:id/comments" do
    let(:post_record) { create(:post, :published, user: author) }
    let(:reader) { create(:user) }

    it "adds a comment and emails the author" do
      expect do
        post post_comments_path(post_record), params: { comment: { body: "Great read!", user_id: reader.id } }
      end.to change(Comment, :count).by(1).and have_enqueued_mail(CommentMailer, :new_comment)
      expect(response).to redirect_to(post_path(post_record))
    end

    it "flashes validation errors" do
      post post_comments_path(post_record), params: { comment: { body: "x", user_id: reader.id } }
      follow_redirect!
      expect(response.body).to include("Body is too short")
    end
  end

  describe "GET /stats" do
    it "returns aggregate stats" do
      create(:post, :published, user: author)
      get stats_path
      expect(response.parsed_body).to include("total" => 1, "published" => 1, "top_author" => "Ada Lovelace")
    end
  end
end
