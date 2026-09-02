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

  test "a new request appears live only in the tab of the walker within radius" do
    owner = User.create!(email_address: "owner@example.com", password: "secret123",
                         role: "owner", city: "Kraków")
    walker_in_radius = User.create!(email_address: "walker-in@example.com", password: "secret123",
                                    role: "walker", city: "Kraków")
    walker_out_of_radius = User.create!(email_address: "walker-out@example.com", password: "secret123",
                                        role: "walker", city: "Kraków")
    dog = owner.dogs.create!(name: "Rex", breed: "Labrador")

    using_session("walker_in") do
      sign_in_via_form(walker_in_radius)
      set_geolocation(latitude: 50.0647, longitude: 19.9450) # Kraków centre
      visit open_requests_path
      assert_text "No open walk requests"
    end

    using_session("walker_out") do
      sign_in_via_form(walker_out_of_radius)
      set_geolocation(latitude: 52.2297, longitude: 21.0122) # Warsaw, ~260km away
      visit open_requests_path
      assert_text "No open walk requests"
    end

    using_session("owner") do
      sign_in_via_form(owner)
      dog.walks.create!(owner: owner, city: "Kraków", latitude: 50.0647, longitude: 19.9450)
    end

    using_session("walker_in") do
      assert_text dog.name
    end

    using_session("walker_out") do
      assert_no_text dog.name
    end
  end
end
