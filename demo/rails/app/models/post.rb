class Post < ApplicationRecord
  belongs_to :user
  has_many :comments, dependent: :destroy

  validates :title, presence: true, length: { maximum: 120 }
  validates :body, presence: true, length: { maximum: 5_000 }
  validates :slug, presence: true, uniqueness: true, if: -> { title.present? }

  before_validation :assign_slug, on: :create

  scope :published, -> { where(published_at: ..Time.current) }
  scope :drafts, -> { where(published_at: nil) }
  scope :recent, -> { order(published_at: :desc, id: :desc) }
  scope :published_since, ->(time) { published.where(published_at: time..) }

  def published? = published_at.present? && published_at <= Time.current

  def publish!(at: Time.current)
    update!(published_at: at)
  end

  def reading_time_minutes = [ (body.to_s.split.size / 200.0).ceil, 1 ].max

  def to_param = "#{id}-#{slug}"

  private

  def assign_slug
    return if slug.present? || title.blank?

    base = title.parameterize.presence || "post"
    candidate = base
    candidate = "#{base}-#{SecureRandom.hex(3)}" while Post.exists?(slug: candidate)
    self.slug = candidate
  end
end
