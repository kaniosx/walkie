require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(email_address: "owner@example.com", password: "secret123",
                          role: "owner", city: "Kraków")
    @walker = User.create!(email_address: "walker@example.com", password: "secret123",
                           role: "walker", city: "Kraków")
  end

  def sign_in_as(email)
    post session_path, params: { email_address: email, password: "secret123" }
  end

  test "owner dashboard renders the active-requests partial with the owner's active walks" do
    dog = @owner.dogs.create!(name: "Rex", breed: "Labrador")
    dog.walks.create!(owner: @owner, city: @owner.city)

    sign_in_as "owner@example.com"
    get root_path

    assert_response :success
    assert_includes response.body, "Active requests"
    assert_includes response.body, "Rex"
    assert_includes response.body, "Requested"
  end

  test "owner dashboard renders the empty active-requests container when there are no active walks" do
    sign_in_as "owner@example.com"
    get root_path

    assert_response :success
    assert_not_includes response.body, "Active requests"
    assert_includes response.body, 'id="owner_active_walks_home"'
  end

  test "walker dashboard renders their current walk when one is accepted" do
    other_owner = User.create!(email_address: "owner2@example.com", password: "secret123",
                               role: "owner", city: "Kraków")
    dog = other_owner.dogs.create!(name: "Fido", breed: "Beagle")
    walk = dog.walks.create!(owner: other_owner, city: "Kraków")
    walk.accept!(@walker)

    sign_in_as "walker@example.com"
    get root_path

    assert_response :success
    assert_includes response.body, "Fido"
    assert_includes response.body, "Accepted"
  end

  test "walker dashboard renders the open-requests count when they have no current walk" do
    dog = @owner.dogs.create!(name: "Rex", breed: "Labrador")
    dog.walks.create!(owner: @owner, city: @owner.city)

    sign_in_as "walker@example.com"
    get root_path

    assert_response :success
    assert_includes response.body, "1 open walk request near you right now."
  end
end
