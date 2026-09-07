require "test_helper"

class OpenRequestsTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(email_address: "owner@example.com", password: "secret123",
                          role: "owner", city: "Kraków")
    @walker = User.create!(email_address: "walker@example.com", password: "secret123",
                           role: "walker", city: "Kraków")
    @walker2 = User.create!(email_address: "walker2@example.com", password: "secret123",
                            role: "walker", city: "Kraków")

    @match = open_walk("Rex",  city: "Kraków")
    @other_city = open_walk("Fido", city: "Gdańsk")
  end

  def sign_in_as(email)
    post session_path, params: { email_address: email, password: "secret123" }
  end

  # Distinct dog per walk to dodge the one-active-per-dog guard.
  def open_walk(dog_name, city:)
    dog = @owner.dogs.create!(name: dog_name, breed: "Labrador")
    dog.walks.create!(owner: @owner, city: city, latitude: 50.0647, longitude: 19.9450)
  end

  test "walker sees only requested walks in their exact city" do
    accepted = open_walk("Taken", city: "Kraków")
    accepted.accept!(@walker2)

    sign_in_as "walker@example.com"
    get open_requests_path, params: { lat: 50.0647, lng: 19.9450 }
    assert_response :success
    assert_includes response.body, "Rex"
    assert_not_includes response.body, "Fido",  "different city must be hidden"
    assert_not_includes response.body, "Taken", "already-accepted walk must be hidden"
  end

  test "with coordinates: shows the distance to each request's owner" do
    sign_in_as "walker@example.com"
    get open_requests_path, params: { lat: 50.0700, lng: 19.9450 }
    assert_response :success
    assert_includes response.body, "km"
  end

  test "without coordinates: shows the getting-your-location placeholder, no list" do
    sign_in_as "walker@example.com"
    get open_requests_path
    assert_response :success
    assert_includes response.body, "Getting your location"
    assert_not_includes response.body, "Rex"
  end

  test "malformed coordinates: shows the getting-your-location placeholder instead of erroring" do
    sign_in_as "walker@example.com"
    get open_requests_path, params: { lat: "abc", lng: "19.9450" }
    assert_response :success
    assert_includes response.body, "Getting your location"
    assert_not_includes response.body, "Rex"
  end

  test "accepting binds the walk to the walker and removes it from the list" do
    sign_in_as "walker@example.com"

    post accept_open_request_path(@match)
    assert_redirected_to open_requests_path
    @match.reload
    assert @match.accepted?
    assert_equal @walker.id, @match.accepted_by_walker_id

    get open_requests_path, params: { lat: 50.0647, lng: 19.9450 }
    # The accepted walk is gone — list is empty (assert the empty state rather
    # than absence of "Rex", which the success flash also contains).
    assert_includes response.body, "No open walk requests in Kraków"
  end

  test "accepting an already-accepted walk shows 'already accepted' and does not change it" do
    @match.accept!(@walker2) # walker2 wins first

    sign_in_as "walker@example.com"
    post accept_open_request_path(@match)
    assert_redirected_to open_requests_path
    follow_redirect!
    assert_includes response.body, "just accepted by someone else"

    @match.reload
    assert @match.accepted?
    assert_equal @walker2.id, @match.accepted_by_walker_id, "original acceptance must stand"
  end

  test "an owner cannot reach the open-requests controller" do
    sign_in_as "owner@example.com"

    get open_requests_path
    assert_redirected_to root_path
    assert_equal "Only Walkers can do that.", flash[:alert]

    post accept_open_request_path(@match)
    assert_redirected_to root_path
    @match.reload
    assert @match.requested?, "owner's blocked accept must not change the walk"
  end

  test "unauthenticated access to open requests redirects to sign-in" do
    get open_requests_path
    assert_redirected_to new_session_path

    post accept_open_request_path(@match)
    assert_redirected_to new_session_path
  end
end
