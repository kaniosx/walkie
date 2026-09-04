require "test_helper"

class WalksTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(email_address: "owner@example.com", password: "secret123",
                          role: "owner", city: "Kraków")
    @other_owner = User.create!(email_address: "owner2@example.com", password: "secret123",
                                role: "owner", city: "Gdańsk")
    @walker = User.create!(email_address: "walker@example.com", password: "secret123",
                           role: "walker", city: "Kraków")
    @dog = @owner.dogs.create!(name: "Rex", breed: "Labrador")
  end

  def sign_in_as(email)
    post session_path, params: { email_address: email, password: "secret123" }
  end

  test "owner creates a request: persists requested with locality copied, redirects with notice" do
    sign_in_as "owner@example.com"

    assert_difference -> { @owner.owned_walks.count }, 1 do
      post walks_path, params: { dog_id: @dog.id, latitude: 50.0647, longitude: 19.9450 }
    end
    walk = @owner.owned_walks.last
    assert walk.requested?
    assert_equal "Kraków", walk.city
    assert_redirected_to walks_path
    follow_redirect!
    assert_includes response.body, "Walk requested for Rex."
  end

  test "owner creates a request without coordinates: fails validation, redirects with alert" do
    sign_in_as "owner@example.com"

    assert_no_difference -> { @owner.owned_walks.count } do
      post walks_path, params: { dog_id: @dog.id }
    end
    assert_redirected_to walks_path
    follow_redirect!
    assert_includes response.body, "Latitude can't be blank"
    assert_includes response.body, "Longitude can't be blank"
  end

  test "index lists only the current owner's walks" do
    mine = @dog.walks.create!(owner: @owner, city: @owner.city, latitude: 50.0647, longitude: 19.9450)
    other_dog = @other_owner.dogs.create!(name: "Fido", breed: "Beagle")
    theirs = other_dog.walks.create!(owner: @other_owner, city: @other_owner.city, latitude: 50.0647, longitude: 19.9450)

    sign_in_as "owner@example.com"
    get walks_path
    assert_response :success
    assert_includes response.body, "Rex"
    assert_not_includes response.body, "Fido"
  end

  test "a second active request for the same dog is rejected" do
    @dog.walks.create!(owner: @owner, city: @owner.city, latitude: 50.0647, longitude: 19.9450)
    sign_in_as "owner@example.com"

    assert_no_difference -> { @dog.walks.count } do
      post walks_path, params: { dog_id: @dog.id, latitude: 50.0647, longitude: 19.9450 }
    end
    assert_redirected_to walks_path
    follow_redirect!
    assert_includes response.body, "already has an active walk request"
  end

  test "a walker cannot access the walk index: redirected by OwnerOnly" do
    sign_in_as "walker@example.com"
    get walks_path
    assert_redirected_to root_path
    assert_equal "Only Owners can do that.", flash[:alert]
  end

  test "a walker cannot create a walk request" do
    sign_in_as "walker@example.com"
    assert_no_difference -> { Walk.count } do
      post walks_path, params: { dog_id: @dog.id }
    end
    assert_redirected_to root_path
    assert_equal "Only Owners can do that.", flash[:alert]
  end

  test "an owner cannot request a walk for another owner's dog" do
    other_dog = @other_owner.dogs.create!(name: "Fido", breed: "Beagle")
    sign_in_as "owner@example.com"

    assert_no_difference -> { Walk.count } do
      post walks_path, params: { dog_id: other_dog.id }
    end
    assert_response :not_found
  end

  test "unauthenticated access to walks redirects to sign-in" do
    get walks_path
    assert_redirected_to new_session_path

    post walks_path, params: { dog_id: @dog.id }
    assert_redirected_to new_session_path
  end

  test "past walks section does not show another owner's completed walk" do
    other_dog = @other_owner.dogs.create!(name: "Fido", breed: "Beagle")
    other_walk = other_dog.walks.create!(owner: @other_owner, city: @other_owner.city, latitude: 50.0647, longitude: 19.9450)
    other_walk.accept!(@walker)
    other_walk.start!(@walker)
    other_walk.complete!(@walker)

    sign_in_as "owner@example.com"
    get walks_path
    assert_response :success
    assert_not_includes response.body, "Fido"
  end

  test "cancelled walk appears in the Past section of the walk index" do
    walk = @dog.walks.create!(owner: @owner, city: @owner.city, latitude: 50.0647, longitude: 19.9450)
    walk.cancel!(@owner)

    sign_in_as "owner@example.com"
    get walks_path
    assert_response :success
    assert_includes response.body, "Rex"
    assert_includes response.body, "Cancelled"
    assert_not_includes response.body, "No past walks yet."
    assert_includes response.body, "No active walk requests."
  end

  test "completed walk appears in the Past section of the walk index" do
    walk = @dog.walks.create!(owner: @owner, city: @owner.city, latitude: 50.0647, longitude: 19.9450)
    walk.accept!(@walker)
    walk.start!(@walker)
    walk.complete!(@walker)

    sign_in_as "owner@example.com"
    get walks_path
    assert_response :success
    assert_includes response.body, "Rex"
    assert_includes response.body, "Completed"
    assert_not_includes response.body, "No past walks yet."
    assert_includes response.body, "No active walk requests."
  end
end
