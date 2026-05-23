require "application_system_test_case"

class FeedsTest < ApplicationSystemTestCase
  test "can view feeds index when logged in" do
    sign_in_as users(:one)
    visit feeds_path
    assert_text "Ruby Blog"
    assert_text "GitHub Blog"
  end

  test "can view feed posts (Read) when logged in" do
    sign_in_as users(:one)
    visit feed_posts_path
    assert_text "Ruby 3.4 Released"
    assert_text "GitHub Copilot Updates"
  end
end
