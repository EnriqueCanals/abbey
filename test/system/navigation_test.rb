require "application_system_test_case"

class NavigationTest < ApplicationSystemTestCase
  test "site header displays blog title" do
    visit root_path
    assert_selector "header h1"
  end

  test "main navigation has expected links" do
    visit root_path

    assert_link "Home"
    assert_link "About"
    assert_link "Projects"
    assert_link "Presentations"
    assert_link "Links"
    assert_link "Papers"
  end

  test "footer is present on all pages" do
    visit root_path
    assert_selector "footer"

    page = pages(:about)
    visit page_path(id: page)
    assert_selector "footer"
  end

  test "can navigate to links page" do
    visit root_path
    click_link "Links"
    assert_current_path links_path
    assert_text "Links"
  end

  test "can navigate to papers page" do
    visit root_path
    click_link "Papers"
    assert_current_path papers_path
    assert_text "Papers"
  end

  test "admin bar hidden when logged out" do
    visit root_path
    assert_no_selector ".fixed.top-0"
  end

  test "admin bar visible when logged in" do
    sign_in_as users(:one)
    visit root_path
    assert_selector ".fixed.top-0"
    assert_text "New Post"
  end
end
