module SystemSignInHelper
  def sign_in_via_form(user, password: "secret123")
    visit new_session_path
    fill_in "Email address", with: user.email_address
    fill_in "Password", with: password
    click_button "Sign in"
    assert_text "Sign out" # wait for the authenticated redirect to land before navigating on
  end
end
