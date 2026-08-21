require "application_system_test_case"

class RealtimeOpenRequestsTest < ApplicationSystemTestCase
  test "one walker accepting a request removes it live from another walker's open list, without a reload" do
    owner = User.create!(email_address: "owner@example.com", password: "secret123",
                         role: "owner", city: "Kraków", postcode: "30-001")
    walker_a = User.create!(email_address: "walker-a@example.com", password: "secret123",
                            role: "walker", city: "Kraków", postcode: "30-001")
    walker_b = User.create!(email_address: "walker-b@example.com", password: "secret123",
                            role: "walker", city: "Kraków", postcode: "30-001")
    dog = owner.dogs.create!(name: "Rex", breed: "Labrador")
    dog.walks.create!(owner: owner, city: "Kraków", postcode: "30-001")

    using_session("walker_a") do
      sign_in_via_form(walker_a)
      visit open_requests_path
      assert_text dog.name
    end

    using_session("walker_b") do
      sign_in_via_form(walker_b)
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
