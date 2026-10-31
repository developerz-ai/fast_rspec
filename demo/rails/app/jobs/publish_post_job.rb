class PublishPostJob < ApplicationJob
  queue_as :default

  def perform(post)
    return if post.published?

    post.publish!
    PostMailer.published(post).deliver_later
  end
end
