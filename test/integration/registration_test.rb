require "test_helper"

class RegistrationTest < ActionDispatch::IntegrationTest
  test "sign-up persists the chosen role and authenticates the user" do
    assert_difference -> { User.count }, 1 do
      post registration_path, params: {
        email_address: "newwalker@example.com",
        password: "secret123",
        password_confirmation: "secret123",
        role: "walker"
      }
    end

    user = User.find_by(email_address: "newwalker@example.com")
    assert user, "user should have been created"
    assert_equal "walker", user.role

    # Session started → redirected to the post-auth landing, and following it
    # reaches the protected root without bouncing back to sign-in.
    assert_redirected_to root_url
    follow_redirect!
    assert_response :success
  end

  test "sign-up without a role re-renders the form and creates no user" do
    assert_no_difference -> { User.count } do
      post registration_path, params: {
        email_address: "norole@example.com",
        password: "secret123",
        password_confirmation: "secret123"
      }
    end

    assert_response :unprocessable_entity
  end

  test "registration page is reachable while unauthenticated" do
    get new_registration_path
    assert_response :success
  end
end
