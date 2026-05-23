require "test_helper"

class BlogControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get root_path
    assert_response :success
    assert_select "h2", text: "Hello World"
    assert_select "h2", text: "About Rails"
    # Draft posts are hidden from index
    assert_select "h2", text: "Draft Post", count: 0
  end

  test "should get post by slug" do
    post = posts(:hello_world)
    get dated_post_path(year: post.year, month: post.month, day: post.day, id: post)
    assert_response :success
    assert_select "h1", text: "Hello World"
  end

  test "should get blog feed" do
    get blog_feed_path
    assert_response :success
    assert_match(/application\/atom\+xml/, response.content_type)
    assert_includes response.body, "Hello World"
    assert_includes response.body, "About Rails"
    refute_includes response.body, "Draft Post"
  end

  test "unauthenticated user cannot access new post form" do
    get new_post_path
    assert_redirected_to new_session_path
  end

  test "authenticated user can access new post form" do
    post session_path, params: { email_address: users(:one).email_address, password: "password" }
    get new_post_path
    assert_response :success
  end
end
