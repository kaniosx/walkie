require "application_system_test_case"

class WalkHistoryTest < ApplicationSystemTestCase
  test "owner sees a completed walk in their walk history" do
    owner = User.create!(email_address: "owner@example.com", password: "secret123",
                         role: "owner", city: "Kraków")
    walker = User.create!(email_address: "walker@example.com", password: "secret123",
                          role: "walker", city: "Kraków")
    dog = owner.dogs.create!(name: "Rex", breed: "Labrador")
    walk = dog.walks.create!(owner: owner, city: owner.city)
    walk.accept!(walker)
    walk.start!(walker)
    walk.complete!(walker)

    sign_in_via_form(owner)

    visit walks_path

    assert_text "Rex"
    assert_text "Completed"
    assert_text walker.display_label
    assert_no_text "No past walks yet."

    click_on "Sign out"

    other_owner = User.create!(email_address: "other_owner@example.com", password: "secret123",
                               role: "owner", city: "Kraków")
    sign_in_via_form(other_owner)

    visit walks_path

    assert_text "No past walks yet."
  end

  test "walker sees a completed walk in their walk history" do
    owner = User.create!(email_address: "owner@example.com", password: "secret123",
                         role: "owner", city: "Kraków")
    walker = User.create!(email_address: "walker@example.com", password: "secret123",
                          role: "walker", city: "Kraków")
    dog = owner.dogs.create!(name: "Rex", breed: "Labrador")
    walk = dog.walks.create!(owner: owner, city: owner.city)
    walk.accept!(walker)
    walk.start!(walker)
    walk.complete!(walker)

    sign_in_via_form(walker)

    visit walker_walks_path

    assert_text "Rex"
    assert_text "Completed"
    assert_text owner.display_label
    assert_no_text "No past walks yet."

    click_on "Sign out"

    other_walker = User.create!(email_address: "other_walker@example.com", password: "secret123",
                                role: "walker", city: "Kraków")
    sign_in_via_form(other_walker)

    visit walker_walks_path

    assert_text "No past walks yet."
  end
end
