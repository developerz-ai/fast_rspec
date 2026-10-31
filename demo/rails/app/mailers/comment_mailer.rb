class CommentMailer < ApplicationMailer
  def new_comment(comment)
    @comment = comment
    @post = comment.post
    mail to: @post.user.email, reply_to: comment.user.email, subject: "New comment on \"#{@post.title}\""
  end
end
