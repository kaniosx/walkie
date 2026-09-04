require "application_system_test_case"

class WalkerRadiusMatchingTest < ApplicationSystemTestCase
  # Kraków center; NEAR is ~2km away, FAR is ~50km away (same city) — same
  # fixture coordinates as test/models/walk_test.rb.
  KRAKOW_LAT = 50.0647
  KRAKOW_LNG = 19.9450
  NEAR_LAT = 50.0827
  FAR_LAT = 50.5147

  test "a walker within 10km sees an open request; a walker beyond 10km does not" do
    owner = User.create!(email_address: "owner@example.com", password: "secret123",
                         role: "owner", city: "Kraków")
    near_walker = User.create!(email_address: "near-walker@example.com", password: "secret123",
                               role: "walker", city: "Kraków")
    far_walker = User.create!(email_address: "far-walker@example.com", password: "secret123",
                              role: "walker", city: "Kraków")
    dog = owner.dogs.create!(name: "Rex", breed: "Labrador")
    dog.walks.create!(owner: owner, city: "Kraków", latitude: KRAKOW_LAT, longitude: KRAKOW_LNG)

    sign_in_via_form(near_walker)
    set_geolocation(latitude: NEAR_LAT, longitude: KRAKOW_LNG)
    visit open_requests_path
    assert_text dog.name

    click_on "Sign out"

    sign_in_via_form(far_walker)
    set_geolocation(latitude: FAR_LAT, longitude: KRAKOW_LNG)
    visit open_requests_path
    assert_no_text dog.name
    assert_text "No open walk requests in Kraków right now."
  end
end
