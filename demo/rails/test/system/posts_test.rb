require "application_system_test_case"

class PostsTest < ApplicationSystemTestCase
  setup { @author = create(:user, name: "Ada Lovelace") }

  test "creating a post through the form" do
    visit new_post_path
    select "Ada Lovelace", from: "Author"
    fill_in "Title", with: "Analytical engines"
    fill_in "Body", with: Faker::Lorem.paragraph
    click_on "Create post"

    assert_selector "#notice", text: "Post created."
    assert_selector "h1", text: "Analytical engines"
  end

  test "validation errors" do
    visit new_post_path
    click_on "Create post"
    assert_text "2 errors prohibited this post from being saved"
  end

  test "publishing a draft via the job" do
    post = create(:post, user: @author, title: "Draft")
    visit post_path(post)
    perform_enqueued_jobs { click_on "Publish" }
    assert_text "Publishing…"
    assert_predicate post.reload, :published?
  end

  test "adding a comment" do
    post = create(:post, :published, user: @author)
    create(:user, name: "Grace Hopper")
    visit post_path(post)
    select "Grace Hopper", from: "Commenter"
    fill_in "Comment", with: "Nice one"
    click_on "Add comment"
    assert_selector ".comment", text: "Grace Hopper: Nice one"
  end

  test "navigating from the index" do
    create(:post, :published, title: "Linked post", user: @author)
    visit root_path
    click_on "Linked post"
    assert_current_path %r{/posts/\d+-linked-post}
  end
end
