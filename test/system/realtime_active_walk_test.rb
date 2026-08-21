require "application_system_test_case"

class RealtimeActiveWalkTest < ApplicationSystemTestCase
  test "an owner watching their walks page sees the walker's start and complete reflected live" do
    owner = User.create!(email_address: "owner@example.com", password: "secret123",
                         role: "owner", city: "Kraków", postcode: "30-001")
    walker = User.create!(email_address: "walker@example.com", password: "secret123",
                          role: "walker", city: "Kraków", postcode: "30-001")
    dog = owner.dogs.create!(name: "Rex", breed: "Labrador")
    walk = dog.walks.create!(owner: owner, city: "Kraków", postcode: "30-001")
    walk.accept!(walker)

    using_session("owner") do
      sign_in_via_form(owner)
      visit walks_path
      assert_text "Accepted"
    end

    using_session("walker") do
      sign_in_via_form(walker)
      visit walker_walks_path
      click_on "Start walk"
      assert_text "Walk started — you're on your way!"
    end

    using_session("owner") do
      assert_text "In progress"
    end

    using_session("walker") do
      accept_confirm { click_on "End walk" }
      assert_text "Walk completed. Well done!"
    end

    using_session("owner") do
      assert_no_text "Rex"
      assert_text "No active walk requests."
    end
  end
end
