require "application_system_test_case"

class AuthTest < ApplicationSystemTestCase
  test "login page is displayed" do
    visit new_session_path
    assert_selector "h1", text: "Sign in"
    assert_field "email_address"
    assert_field "password"
    assert_button "Sign in"
  end

  test "failed login shows error" do
    visit new_session_path
    fill_in "email_address", with: "nobody@example.com"
    fill_in "password", with: "wrongpassword"
    click_button "Sign in"
    assert_text "Try another email address or password"
  end

  test "can sign out after logging in" do
    sign_in_as users(:one)
    click_button "Sign out"
    assert_current_path new_session_path
    assert_no_text "New Post"
    assert_no_text "Sign out"
  end

  test "unauthenticated user redirected to login when accessing admin pages" do
    visit new_post_path
    assert_current_path new_session_path
  end

  test "edit link visible on posts when logged in" do
    sign_in_as users(:one)
    visit root_path
    assert_link "Edit"
  end

  test "edit link hidden on posts when logged out" do
    visit root_path
    assert_no_link "Edit"
  end
end
