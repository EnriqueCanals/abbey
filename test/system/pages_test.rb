require "application_system_test_case"

class PagesTest < ApplicationSystemTestCase
  test "can view a public page" do
    visit page_path(id: "about")
    assert_selector "h1", text: "About"
  end

  test "can create a new page" do
    sign_in_as users(:one)
    visit new_page_path
    fill_in "Title", with: "Contact"
    fill_in "Slug", with: "contact"
    fill_in "Markdown body", with: "Contact us here."
    click_button "Create Page"
    assert_selector "h1", text: "Contact"
    assert_text "Contact us here"
  end

  test "can edit an existing page" do
    sign_in_as users(:one)
    visit edit_page_path(id: "about")
    fill_in "Markdown body", with: "Updated about page content."
    click_button "Update Page"
    assert_text "Updated about page content"
  end
end
