require "rails_helper"

RSpec.describe "Writing posts" do
  let!(:author) { create(:user, name: "Ada Lovelace") }

  it "creates a post through the form" do
    visit new_post_path
    select "Ada Lovelace", from: "Author"
    fill_in "Title", with: "Analytical engines"
    fill_in "Body", with: Faker::Lorem.paragraph
    click_on "Create post"

    expect(page).to have_css("#notice", text: "Post created.")
    expect(page).to have_css("h1", text: "Analytical engines")
  end

  it "shows validation errors" do
    visit new_post_path
    click_on "Create post"
    expect(page).to have_content("2 errors prohibited this post from being saved")
  end

  it "publishes a draft via the job" do
    post = create(:post, user: author, title: "Draft")
    visit post_path(post)
    perform_enqueued_jobs { click_on "Publish" }
    expect(page).to have_content("Publishing…")
    expect(post.reload).to be_published
  end

  it "adds a comment" do
    post = create(:post, :published, user: author)
    create(:user, name: "Grace Hopper")
    visit post_path(post)
    select "Grace Hopper", from: "Commenter"
    fill_in "Comment", with: "Nice one"
    click_on "Add comment"
    expect(page).to have_css(".comment", text: "Grace Hopper: Nice one")
  end

  it "navigates from the index" do
    create(:post, :published, title: "Linked post", user: author)
    visit root_path
    click_on "Linked post"
    expect(page).to have_current_path(%r{/posts/\d+-linked-post})
  end
end
