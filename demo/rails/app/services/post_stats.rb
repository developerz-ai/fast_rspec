# A deliberately "expensive" report (think: a slow aggregate query). Tests that use it are slow-ish
# on purpose, so parallel speedup is visible.
class PostStats
  def initialize(scope = Post.all, delay: 0)
    @scope = scope
    @delay = delay
  end

  def call
    sleep @delay if @delay.positive?
    {
      total: @scope.count,
      published: @scope.published.count,
      drafts: @scope.drafts.count,
      comments: @scope.sum(:comments_count),
      top_author: top_author&.name
    }
  end

  private

  def top_author
    User.joins(:posts).merge(@scope).group("users.id").order(Arel.sql("COUNT(posts.id) DESC"), "users.id").first
  end
end
