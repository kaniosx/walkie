require "application_system_test_case"

class OwnerCreatesWalkRequestTest < ApplicationSystemTestCase
  test "owner signs in through the real form and creates a walk request" do
    owner = User.create!(email_address: "owner@example.com", password: "secret123",
                         role: "owner", city: "Kraków", postcode: "30-001")
    dog = owner.dogs.create!(name: "Rex", breed: "Labrador")

    visit new_session_path
    fill_in "Email address", with: owner.email_address
    fill_in "Password", with: "secret123"
    click_button "Sign in"
    assert_text "Sign out" # wait for the authenticated redirect to land before navigating on

    visit dogs_path
    click_on "Walk my dog"

    assert_text "Walk requested for #{dog.name}."
    assert_text dog.name
  end
end
