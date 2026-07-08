require "test_helper"

class WalkerWalksTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(email_address: "owner@example.com", password: "secret123",
                          role: "owner", city: "Kraków", postcode: "30-001")
    @walker = User.create!(email_address: "walker@example.com", password: "secret123",
                           role: "walker", city: "Kraków", postcode: "30-001")
    @walker2 = User.create!(email_address: "walker2@example.com", password: "secret123",
                            role: "walker", city: "Kraków", postcode: "30-001")
    @dog = @owner.dogs.create!(name: "Rex", breed: "Labrador")
    @walk = @dog.walks.create!(owner: @owner, city: @owner.city, postcode: @owner.postcode)
    @walk.accept!(@walker)
  end

  def sign_in_as(email)
    post session_path, params: { email_address: email, password: "secret123" }
  end

  test "walker with accepted walk sees dog name and Start walk button" do
    sign_in_as "walker@example.com"
    get walker_walks_path
    assert_response :success
    assert_includes response.body, "Rex"
    assert_includes response.body, "Start walk"
  end

  test "walker with no active walk sees empty state" do
    @walk.start!(@walker)
    @walk.complete!(@walker)

    sign_in_as "walker@example.com"
    get walker_walks_path
    assert_response :success
    assert_includes response.body, "You have no active walk right now."
  end

  test "walker starts accepted walk: redirects with notice and walk is in_progress" do
    sign_in_as "walker@example.com"

    post start_walker_walk_path(@walk)

    assert_redirected_to walker_walks_path
    follow_redirect!
    assert_includes response.body, "Walk started"
    @walk.reload
    assert @walk.in_progress?
  end

  test "walker completes in_progress walk: redirects to open_requests with notice and walk is completed" do
    @walk.start!(@walker)

    sign_in_as "walker@example.com"
    post complete_walker_walk_path(@walk)

    assert_redirected_to open_requests_path
    follow_redirect!
    assert_includes response.body, "Walk completed. Well done!"
    @walk.reload
    assert @walk.completed?
  end

  test "walker cannot start another walker's accepted walk: responds 404" do
    sign_in_as "walker2@example.com"
    post start_walker_walk_path(@walk)
    assert_response :not_found
  end

  test "owner cannot reach walker_walks controller: redirected by WalkerOnly" do
    sign_in_as "owner@example.com"
    get walker_walks_path
    assert_redirected_to root_path
    assert_equal "Only Walkers can do that.", flash[:alert]
  end

  test "walker cannot complete another walker's in_progress walk: responds 404" do
    @walk.start!(@walker)
    sign_in_as "walker2@example.com"
    post complete_walker_walk_path(@walk)
    assert_response :not_found
  end

  test "walker cannot complete their own walk before starting it: responds 404" do
    # @walk is accepted (not started) per the outer setup — completing it now
    # would skip the in_progress state.
    sign_in_as "walker@example.com"
    post complete_walker_walk_path(@walk)
    assert_response :not_found
  end

  test "walker cannot start their own walk that is already in progress: responds 404" do
    @walk.start!(@walker)
    sign_in_as "walker@example.com"
    post start_walker_walk_path(@walk)
    assert_response :not_found
  end

  test "completed walk appears in walker's past walk history" do
    @walk.start!(@walker)
    @walk.complete!(@walker)

    sign_in_as "walker@example.com"
    get walker_walks_path
    assert_response :success
    assert_includes response.body, "Rex"
    assert_includes response.body, "Completed"
    assert_not_includes response.body, "No past walks yet."
    assert_not_includes response.body, "Start walk"
    assert_not_includes response.body, "End walk"
  end

  test "walker with no completed walks sees past walks empty state" do
    # Walk stays in accepted state (not completed), so @past_walks is empty
    sign_in_as "walker@example.com"
    get walker_walks_path
    assert_response :success
    assert_includes response.body, "No past walks yet."
  end

  test "walker cannot see another walker's completed walk in history" do
    @walk.start!(@walker)
    @walk.complete!(@walker)

    sign_in_as "walker2@example.com"
    get walker_walks_path
    assert_response :success
    assert_not_includes response.body, "Rex"
  end

  test "walker cannot see another walker's accepted walk in active section" do
    # @walk is accepted (not completed) so Rex can only appear in the active
    # section — page-global absence is sufficient to close the isolation gap.
    sign_in_as "walker2@example.com"
    get walker_walks_path
    assert_response :success
    assert_not_includes response.body, "Rex"
  end

  test "unauthenticated access redirects to sign-in" do
    get walker_walks_path
    assert_redirected_to new_session_path

    post start_walker_walk_path(@walk)
    assert_redirected_to new_session_path

    post complete_walker_walk_path(@walk)
    assert_redirected_to new_session_path
  end
end
