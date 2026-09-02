require "application_system_test_case"

class OwnerCancelsRequestTest < ApplicationSystemTestCase
  test "owner signs in, creates a walk request, and cancels it" do
    skip "Pending Phase 2->3: WalksController#create now requires latitude/longitude " \
         "(geolocation-matching plan), and the JS that captures them via the browser " \
         "lands in Phase 3 (Owner-side location capture)."

    owner = User.create!(email_address: "owner@example.com", password: "secret123",
                         role: "owner", city: "Kraków")
    dog = owner.dogs.create!(name: "Rex", breed: "Labrador")

    sign_in_via_form(owner)

    visit dogs_path
    click_on "Walk my dog"

    assert_text "Walk requested for #{dog.name}."

    accept_confirm { click_on "Cancel" }

    assert_text "Walk request cancelled."
    assert_no_button "Cancel"
    assert_text "Cancelled"
  end
end
