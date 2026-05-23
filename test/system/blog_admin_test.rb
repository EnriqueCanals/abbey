require "application_system_test_case"

class BlogAdminTest < ApplicationSystemTestCase
  test "can create a new post" do
    sign_in_as users(:one)
    visit new_post_path

    fill_in "Title", with: "My Test Post"
    fill_in "Post tags", with: "test, rails"
    fill_in "Markdown excerpt", with: "This is the excerpt."
    fill_in "Markdown body", with: "This is the full post content."
    click_button "Create Post"

    assert_selector "h1", text: "My Test Post"
    assert_text "This is the full post content"
  end

  test "can edit an existing post" do
    sign_in_as users(:one)
    visit edit_post_path(posts(:hello_world))

    fill_in "Title", with: "Updated Hello World"
    click_button "Update Post"

    assert_selector "h1", text: "Updated Hello World"
  end

  test "can delete a post" do
    sign_in_as users(:one)
    visit edit_post_path(posts(:hello_world))

    accept_confirm do
      click_button "Delete"
    end

    assert_selector "h2", text: "About Rails"
    assert_no_selector "h2", text: "Hello World"
  end

  test "cannot create post with missing required fields" do
    sign_in_as users(:one)
    visit new_post_path

    fill_in "Title", with: ""
    fill_in "Markdown excerpt", with: "Excerpt"
    fill_in "Markdown body", with: "Body content"
    click_button "Create Post"

    assert_text "can't be blank"
  end

  test "draft post is not visible on public homepage" do
    sign_in_as users(:one)
    visit new_post_path

    fill_in "Title", with: "Secret Draft"
    check "Draft"
    fill_in "Markdown excerpt", with: "Hidden excerpt."
    fill_in "Markdown body", with: "Hidden body content."
    click_button "Create Post"

    click_button "Sign out"
    visit root_path

    assert_no_text "Secret Draft"
  end
end
