ada = User.find_or_create_by!(email: "ada@example.com") { |u| u.name = "Ada Lovelace"; u.role = "admin"; u.city = "London" }
grace = User.find_or_create_by!(email: "grace@example.com") { |u| u.name = "Grace Hopper"; u.city = "New York" }
post = Post.find_or_create_by!(title: "Hello, world") { |p| p.user = ada; p.body = "First post."; p.published_at = Time.current }
post.comments.find_or_create_by!(user: grace, body: "Welcome!")
