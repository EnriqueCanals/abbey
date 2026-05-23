require "application_system_test_case"

class BlogPublicTest < ApplicationSystemTestCase
  test "homepage shows published posts" do
    visit root_path

    assert_selector "h2", text: "About Rails"
    assert_selector "h2", text: "Hello World"
    assert_no_selector "h2", text: "Draft Post"
  end

  test "can click through to a post detail page" do
    visit root_path

    click_link "About Rails"

    assert_selector "h1", text: "About Rails"
    assert_text "Ruby on Rails is a web application framework"
    assert_link "Back to posts"
  end

  test "homepage includes RSS feed link in navigation" do
    visit root_path
    # RSS button is in the nav with aria-label
    assert_selector 'a[aria-label="RSS Feed"]'
  end

  test "published post shows date" do
    post = posts(:hello_world)
    visit dated_post_path(
      year: post.year,
      month: post.month,
      day: post.day,
      id: post
    )

    assert_text post.created_at.strftime("%Y-%m-%d")
  end
end
