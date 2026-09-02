require "test_helper"

class RegistrationTest < ActionDispatch::IntegrationTest
  test "sign-up persists the chosen role plus city and authenticates the user" do
    assert_difference -> { User.count }, 1 do
      post registration_path, params: {
        email_address: "newwalker@example.com",
        password: "secret123",
        password_confirmation: "secret123",
        role: "walker",
        city: "Kraków"
      }
    end

    user = User.find_by(email_address: "newwalker@example.com")
    assert user, "user should have been created"
    assert_equal "walker", user.role
    assert_equal "Kraków", user.city

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
        password_confirmation: "secret123",
        city: "Kraków"
      }
    end

    assert_response :unprocessable_entity
  end

  test "sign-up without a city re-renders the form and creates no user" do
    assert_no_difference -> { User.count } do
      post registration_path, params: {
        email_address: "nocity@example.com",
        password: "secret123",
        password_confirmation: "secret123",
        role: "owner"
      }
    end

    assert_response :unprocessable_entity
  end

  test "registration page is reachable while unauthenticated" do
    get new_registration_path
    assert_response :success
  end
end
