require "application_system_test_case"

class RealtimeOpenRequestsTest < ApplicationSystemTestCase
  test "one walker accepting a request removes it live from another walker's open list, without a reload" do
    owner = User.create!(email_address: "owner@example.com", password: "secret123",
                         role: "owner", city: "Kraków")
    walker_a = User.create!(email_address: "walker-a@example.com", password: "secret123",
                            role: "walker", city: "Kraków")
    walker_b = User.create!(email_address: "walker-b@example.com", password: "secret123",
                            role: "walker", city: "Kraków")
    dog = owner.dogs.create!(name: "Rex", breed: "Labrador")
    dog.walks.create!(owner: owner, city: "Kraków", latitude: 50.0647, longitude: 19.9450)

    using_session("walker_a") do
      sign_in_via_form(walker_a)
      set_geolocation(latitude: 50.0647, longitude: 19.9450)
      visit open_requests_path
      assert_text dog.name
    end

    using_session("walker_b") do
      sign_in_via_form(walker_b)
      set_geolocation(latitude: 50.0647, longitude: 19.9450)
      visit open_requests_path
      assert_text dog.name
      click_button "Accept"
      assert_text "You accepted the walk for #{dog.name}."
    end

    using_session("walker_a") do
      assert_no_text dog.name
      assert_text "No open walk requests in Kraków right now."
    end
  end
end
