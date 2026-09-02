require "application_system_test_case"

class WalkerAcceptsRequestTest < ApplicationSystemTestCase
  test "walker signs in, sees an open request, and accepts it" do
    owner = User.create!(email_address: "owner@example.com", password: "secret123",
                         role: "owner", city: "Kraków")
    walker = User.create!(email_address: "walker@example.com", password: "secret123",
                          role: "walker", city: "Kraków")
    dog = owner.dogs.create!(name: "Rex", breed: "Labrador")
    dog.walks.create!(owner: owner, city: "Kraków", latitude: 50.0647, longitude: 19.9450)

    sign_in_via_form(walker)

    visit open_requests_path
    assert_text dog.name

    click_button "Accept"

    assert_text "You accepted the walk for #{dog.name}."
    assert_text "No open walk requests in Kraków right now."
  end
end
