require "application_system_test_case"

class FullWalkLifecycleTest < ApplicationSystemTestCase
  test "owner creates a request, walker accepts, starts, and completes it" do
    skip "Pending Phase 2->3: WalksController#create now requires latitude/longitude " \
         "(geolocation-matching plan), and the JS that captures them via the browser " \
         "lands in Phase 3 (Owner-side location capture)."

    owner = User.create!(email_address: "owner@example.com", password: "secret123",
                         role: "owner", city: "Kraków")
    walker = User.create!(email_address: "walker@example.com", password: "secret123",
                          role: "walker", city: "Kraków")
    dog = owner.dogs.create!(name: "Rex", breed: "Labrador")

    sign_in_via_form(owner)

    visit dogs_path
    click_on "Walk my dog"

    assert_text "Walk requested for #{dog.name}."

    click_on "Sign out"
    sign_in_via_form(walker)

    visit open_requests_path
    assert_text dog.name

    click_button "Accept"

    assert_text "You accepted the walk for #{dog.name}."

    visit walker_walks_path
    assert_text "Accepted"

    click_on "Start walk"

    assert_text "Walk started — you're on your way!"
    assert_text "In progress"

    accept_confirm { click_on "End walk" }

    assert_text "Walk completed. Well done!"
  end
end
