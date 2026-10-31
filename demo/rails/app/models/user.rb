class User < ApplicationRecord
  ROLES = %w[member admin].freeze

  has_many :posts, dependent: :destroy
  has_many :comments, dependent: :destroy

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :name, presence: true, length: { maximum: 80 }
  validates :email, presence: true, uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :role, inclusion: { in: ROLES }

  def admin? = role == "admin"

  def display_name = admin? ? "#{name} (admin)" : name
end
