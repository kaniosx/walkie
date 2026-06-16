require "test_helper"

class NavigationTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email_address: "nav@example.com",
      password: "secret123",
      role: "owner",
      city: "Kraków",
      postcode: "30-001"
    )
  end

  test "nav bar shows sign-out when authenticated" do
    post session_path, params: { email_address: "nav@example.com", password: "secret123" }
    get root_path
    assert_response :success
    assert_includes response.body, "Sign out"
  end

  test "nav bar does not show sign-out when unauthenticated" do
    get new_session_path
    assert_response :success
    assert_not_includes response.body, "Sign out"
  end

  test "flash alert is visible after a failed sign-in attempt" do
    post session_path, params: { email_address: "nav@example.com", password: "wrong-password" }
    follow_redirect!
    assert_includes response.body, "Try another email address or password."
  end
end
