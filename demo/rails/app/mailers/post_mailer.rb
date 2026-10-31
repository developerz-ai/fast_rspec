class PostMailer < ApplicationMailer
  def published(post)
    @post = post
    mail to: post.user.email, subject: "Your post \"#{post.title}\" is live"
  end
end
