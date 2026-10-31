require "rails_helper"

RSpec.describe "Body character counter", :js do
  it "updates live and the post saves" do
    create(:user, name: "Ada Lovelace")
    visit new_post_path
    expect(page).to have_css("#body-counter", text: "0 / 5000")

    fill_in "Title", with: "Typed in Chrome"
    fill_in "Body", with: "Hello world"
    expect(page).to have_css("#body-counter", text: "11 / 5000")

    click_on "Create post"
    expect(page).to have_css("h1", text: "Typed in Chrome")
    expect(Post.last.title).to eq("Typed in Chrome")
  end
end
