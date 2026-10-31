require "application_system_test_case"

class BodyCounterTest < JavaScriptSystemTestCase
  test "updates live and the post saves" do
    create(:user, name: "Ada Lovelace")
    visit new_post_path
    assert_selector "#body-counter", text: "0 / 5000"

    fill_in "Title", with: "Typed in Chrome"
    fill_in "Body", with: "Hello world"
    assert_selector "#body-counter", text: "11 / 5000"

    click_on "Create post"
    assert_selector "h1", text: "Typed in Chrome"
    assert_equal "Typed in Chrome", Post.last.title
  end
end
