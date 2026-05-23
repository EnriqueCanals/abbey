require "application_system_test_case"

class LinksTest < ApplicationSystemTestCase
  test "can view links index publicly" do
    visit links_path
    assert_text "Links"
  end
end
