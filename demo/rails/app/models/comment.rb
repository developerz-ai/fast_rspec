class Comment < ApplicationRecord
  belongs_to :post, counter_cache: true
  belongs_to :user

  validates :body, presence: true, length: { minimum: 3, maximum: 1_000 }

  after_create_commit :notify_post_author

  private

  def notify_post_author
    return if user_id == post.user_id

    CommentMailer.new_comment(self).deliver_later
  end
end
