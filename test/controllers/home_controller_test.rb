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
    dog.walks.create!(owner: @owner, city: @owner.city, latitude: 50.0647, longitude: 19.9450)

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

  test "owner dashboard shows the distance to the accepted walker when the walker's location is cached" do
    dog = @owner.dogs.create!(name: "Rex", breed: "Labrador")
    walk = dog.walks.create!(owner: @owner, city: @owner.city, latitude: 50.0647, longitude: 19.9450)
    walk.accept!(@walker)
    WalkerLocationCache.write(@walker, latitude: 50.08, longitude: 19.95)

    sign_in_as "owner@example.com"
    get root_path

    assert_response :success
    assert_includes response.body, "km away"
  end

  test "owner dashboard shows no distance line when the walker's cached location is absent" do
    dog = @owner.dogs.create!(name: "Rex", breed: "Labrador")
    walk = dog.walks.create!(owner: @owner, city: @owner.city, latitude: 50.0647, longitude: 19.9450)
    walk.accept!(@walker)

    sign_in_as "owner@example.com"
    get root_path

    assert_response :success
    assert_not_includes response.body, "km away"
  end

  test "owner dashboard's active_walks eager-loads accepted_by_walker so per-row distance lookups don't N+1" do
    other_walker = User.create!(email_address: "walker2@example.com", password: "secret123",
                                role: "walker", city: "Kraków")
    dog1 = @owner.dogs.create!(name: "Rex", breed: "Labrador")
    dog2 = @owner.dogs.create!(name: "Fido", breed: "Beagle")
    walk1 = dog1.walks.create!(owner: @owner, city: @owner.city, latitude: 50.0647, longitude: 19.9450)
    walk2 = dog2.walks.create!(owner: @owner, city: @owner.city, latitude: 50.0647, longitude: 19.9450)
    walk1.accept!(@walker)
    walk2.accept!(other_walker)

    walks = @owner.owned_walks.active.includes(:dog, :accepted_by_walker).order(created_at: :desc).to_a

    assert_no_queries do
      walks.each(&:accepted_by_walker)
    end
  end

  test "walker dashboard renders their current walk when one is accepted" do
    other_owner = User.create!(email_address: "owner2@example.com", password: "secret123",
                               role: "owner", city: "Kraków")
    dog = other_owner.dogs.create!(name: "Fido", breed: "Beagle")
    walk = dog.walks.create!(owner: other_owner, city: "Kraków", latitude: 50.0647, longitude: 19.9450)
    walk.accept!(@walker)

    sign_in_as "walker@example.com"
    get root_path

    assert_response :success
    assert_includes response.body, "Fido"
    assert_includes response.body, "Accepted"
  end

  test "walker dashboard renders the open-requests count when they have no current walk" do
    dog = @owner.dogs.create!(name: "Rex", breed: "Labrador")
    dog.walks.create!(owner: @owner, city: @owner.city, latitude: 50.0647, longitude: 19.9450)

    sign_in_as "walker@example.com"
    get root_path, params: { lat: 50.0647, lng: 19.9450 }

    assert_response :success
    assert_includes response.body, "1 open walk request near you right now."
  end

  test "walker dashboard shows the getting-your-location placeholder without coordinates" do
    sign_in_as "walker@example.com"
    get root_path

    assert_response :success
    assert_includes response.body, "Getting your location"
  end

  test "walker dashboard shows the getting-your-location placeholder with malformed coordinates" do
    sign_in_as "walker@example.com"
    get root_path, params: { lat: "abc", lng: "19.9450" }

    assert_response :success
    assert_includes response.body, "Getting your location"
  end
end
