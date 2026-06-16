require "test_helper"

class SessionsTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email_address: "round@example.com",
      password: "secret123",
      role: "owner",
      city: "Kraków",
      postcode: "30-001"
    )
  end

  test "sign in, reach protected page, sign out, gated again" do
    # Signed out: the protected root bounces to sign-in.
    get root_path
    assert_redirected_to new_session_path

    # Sign in with correct credentials.
    post session_path, params: { email_address: "round@example.com", password: "secret123" }
    assert_redirected_to root_url
    follow_redirect!
    assert_response :success

    # Protected root is now reachable.
    get root_path
    assert_response :success

    # Sign out.
    delete session_path
    assert_redirected_to new_session_path

    # Gated again after sign-out.
    get root_path
    assert_redirected_to new_session_path
  end

  test "sign in with wrong password is rejected" do
    post session_path, params: { email_address: "round@example.com", password: "wrong-password" }
    assert_redirected_to new_session_path

    get root_path
    assert_redirected_to new_session_path
  end
end
