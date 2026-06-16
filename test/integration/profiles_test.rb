require "test_helper"

class ProfilesTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email_address: "profile@example.com",
      password: "secret123",
      role: "owner",
      city: "Kraków",
      postcode: "30-001"
    )
  end

  def sign_in
    post session_path, params: { email_address: "profile@example.com", password: "secret123" }
  end

  test "signed-in user can view their profile" do
    sign_in
    get profile_path
    assert_response :success
    assert_includes response.body, "Kraków"
    assert_includes response.body, "30-001"
  end

  test "signed-in user can reach the edit form" do
    sign_in
    get edit_profile_path
    assert_response :success
  end

  test "updating display name, city and postcode persists and redirects to the profile" do
    sign_in
    patch profile_path, params: { display_name: "Ada", city: "Gdańsk", postcode: "80-001" }
    assert_redirected_to profile_path

    @user.reload
    assert_equal "Ada", @user.display_name
    assert_equal "Gdańsk", @user.city
    assert_equal "80-001", @user.postcode
  end

  test "updating with a blank city re-renders edit and does not change the record" do
    sign_in
    patch profile_path, params: { display_name: "Ada", city: "", postcode: "80-001" }
    assert_response :unprocessable_entity

    @user.reload
    assert_equal "Kraków", @user.city
    assert_nil @user.display_name
  end

  test "updating with a blank postcode re-renders edit and does not change the record" do
    sign_in
    patch profile_path, params: { display_name: "Ada", city: "Gdańsk", postcode: "" }
    assert_response :unprocessable_entity

    @user.reload
    assert_equal "30-001", @user.postcode
    assert_nil @user.display_name
  end

  test "unauthenticated access to the profile redirects to sign-in" do
    get profile_path
    assert_redirected_to new_session_path

    get edit_profile_path
    assert_redirected_to new_session_path
  end
end
