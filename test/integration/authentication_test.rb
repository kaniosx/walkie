require "test_helper"

class AuthenticationTest < ActionDispatch::IntegrationTest
  test "anonymous request to a protected route redirects to sign-in" do
    get root_path
    assert_redirected_to new_session_path
  end

  test "sign-up, sign-in, and password routes are reachable while unauthenticated" do
    get new_registration_path
    assert_response :success

    get new_session_path
    assert_response :success

    get new_password_path
    assert_response :success
  end
end
