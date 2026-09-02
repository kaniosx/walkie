require "application_system_test_case"

class OwnerCreatesWalkRequestTest < ApplicationSystemTestCase
  test "owner signs in through the real form and creates a walk request" do
    owner = User.create!(email_address: "owner@example.com", password: "secret123",
                         role: "owner", city: "Kraków")
    dog = owner.dogs.create!(name: "Rex", breed: "Labrador")

    sign_in_via_form(owner)
    set_geolocation(latitude: 50.0647, longitude: 19.9450)

    visit dogs_path
    assert_button "Walk my dog"
    click_on "Walk my dog"

    assert_text "Walk requested for #{dog.name}."
    assert_text dog.name
  end
end
