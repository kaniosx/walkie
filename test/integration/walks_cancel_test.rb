require "test_helper"

class WalksCancelTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(email_address: "owner@example.com", password: "secret123",
                          role: "owner", city: "Kraków", postcode: "30-001")
    @other_owner = User.create!(email_address: "owner2@example.com", password: "secret123",
                                role: "owner", city: "Kraków", postcode: "30-001")
    @walker = User.create!(email_address: "walker@example.com", password: "secret123",
                           role: "walker", city: "Kraków", postcode: "30-001")
    @dog = @owner.dogs.create!(name: "Rex", breed: "Labrador")
    @walk = @dog.walks.create!(owner: @owner, city: @owner.city, postcode: @owner.postcode)
  end

  def sign_in_as(email)
    post session_path, params: { email_address: email, password: "secret123" }
  end

  test "owner cancels own requested walk: redirects with notice and walk is cancelled" do
    sign_in_as "owner@example.com"

    post cancel_walk_path(@walk)

    assert_redirected_to walks_path
    follow_redirect!
    assert_includes response.body, "Walk request cancelled."
    @walk.reload
    assert @walk.cancelled?
  end

  test "owner cancels an already-accepted walk: redirects with alert, walk remains accepted" do
    @walk.accept!(@walker)

    sign_in_as "owner@example.com"
    post cancel_walk_path(@walk)

    assert_redirected_to walks_path
    follow_redirect!
    assert_includes response.body, "This request was already accepted by a walker."
    @walk.reload
    assert @walk.accepted?, "walk must remain accepted"
  end

  test "owner cannot cancel another owner's walk: responds 404" do
    other_dog = @other_owner.dogs.create!(name: "Fido", breed: "Beagle")
    other_walk = other_dog.walks.create!(owner: @other_owner, city: @other_owner.city, postcode: @other_owner.postcode)

    sign_in_as "owner@example.com"
    post cancel_walk_path(other_walk)

    assert_response :not_found
  end

  test "walker cannot reach cancel action: redirected by OwnerOnly" do
    sign_in_as "walker@example.com"
    post cancel_walk_path(@walk)

    assert_redirected_to root_path
    assert_equal "Only Owners can do that.", flash[:alert]
    @walk.reload
    assert @walk.requested?, "walker's blocked cancel must not change the walk"
  end

  test "unauthenticated cancel attempt redirects to sign-in" do
    post cancel_walk_path(@walk)

    assert_redirected_to new_session_path
    @walk.reload
    assert @walk.requested?
  end
end
