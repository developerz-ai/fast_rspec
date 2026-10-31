class PostsController < ApplicationController
  before_action :set_post, only: %i[show publish]

  def index
    @posts = Post.published.recent.includes(:user)
    respond_to do |format|
      format.html
      format.json { render json: @posts.as_json(only: %i[id title slug published_at]) }
    end
  end

  def show
    @comment = @post.comments.build
  end

  def new
    @post = Post.new
  end

  def create
    @post = Post.new(post_params)
    if @post.save
      redirect_to @post, notice: "Post created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def publish
    PublishPostJob.perform_later(@post)
    redirect_to @post, notice: "Publishing…"
  end

  def stats
    render json: PostStats.new.call
  end

  private

  def set_post
    @post = Post.find(params[:id].to_i)
  end

  def post_params
    params.require(:post).permit(:title, :body, :user_id)
  end
end
