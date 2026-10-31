class CommentsController < ApplicationController
  def create
    @post = Post.find(params[:post_id].to_i)
    @comment = @post.comments.build(params.require(:comment).permit(:body, :user_id))
    if @comment.save
      redirect_to @post, notice: "Comment added."
    else
      redirect_to @post, alert: @comment.errors.full_messages.to_sentence
    end
  end
end
