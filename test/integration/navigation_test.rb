require "test_helper"

class NavigationTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email_address: "nav@example.com",
      password: "secret123",
      role: "owner"
    )
  end

  test "nav bar shows sign-out when authenticated" do
    post session_path, params: { email_address: "nav@example.com", password: "secret123" }
    get root_path
    assert_response :success
    assert_match "Sign out", response.body
  end

  test "nav bar does not show sign-out when unauthenticated" do
    get new_session_path
    assert_response :success
    assert_no_match "Sign out", response.body
  end

  test "flash alert is visible after a failed sign-in attempt" do
    post session_path, params: { email_address: "nav@example.com", password: "wrong-password" }
    follow_redirect!
    assert_match "Try another email address or password.", response.body
  end
end
