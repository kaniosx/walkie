require "application_system_test_case"

class SmokeTest < ApplicationSystemTestCase
  test "visiting the sign-in page renders the form" do
    visit new_session_path

    assert_selector "h1", text: "Sign in"
    assert_selector "input[type=email]"
    assert_selector "input[type=password]"
  end
end
