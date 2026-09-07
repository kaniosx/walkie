require "test_helper"

class WalkTest < ActiveSupport::TestCase
  # Kraków center; NEAR is ~2km away, FAR is ~50km away (same city).
  KRAKOW_LAT = 50.0647
  KRAKOW_LNG = 19.9450
  NEAR_LAT = 50.0827
  FAR_LAT = 50.5147

  def setup
    @owner = User.create!(email_address: "owner@example.com", password: "secret123",
                          password_confirmation: "secret123", role: "owner", city: "Kraków")
    @walker = User.create!(email_address: "walker@example.com", password: "secret123",
                           password_confirmation: "secret123", role: "walker", city: "Kraków")
    @other_walker = User.create!(email_address: "walker2@example.com", password: "secret123",
                                 password_confirmation: "secret123", role: "walker", city: "Kraków")
    @dog = Dog.create!(name: "Rex", breed: "Labrador", user: @owner)
    @walk = Walk.create!(dog: @dog, owner: @owner, city: "Kraków",
                         latitude: KRAKOW_LAT, longitude: KRAKOW_LNG)
  end

  # --- Happy path ----------------------------------------------------------

  test "full accept! -> start! -> complete! lifecycle sets state and timestamps" do
    assert @walk.requested?

    assert @walk.accept!(@walker)
    assert @walk.accepted?
    assert_equal @walker.id, @walk.accepted_by_walker_id
    assert_not_nil @walk.accepted_at

    assert @walk.start!(@walker)
    assert @walk.in_progress?
    assert_not_nil @walk.started_at

    assert @walk.complete!(@walker)
    assert @walk.completed?
    assert_not_nil @walk.completed_at
  end

  test "cancel! from requested works and stamps cancelled_at" do
    assert @walk.cancel!(@owner)
    assert @walk.cancelled?
    assert_not_nil @walk.cancelled_at
    assert_nil @walk.accepted_by_walker_id
  end

  # --- Illegal transitions -------------------------------------------------

  test "start! before accept! returns falsy and leaves state unchanged" do
    assert_not @walk.start!(@walker)
    assert @walk.requested?
  end

  test "complete! before start! is rejected" do
    @walk.accept!(@walker)
    assert_not @walk.complete!(@walker)
    assert @walk.accepted?
  end

  test "accept! on a non-requested walk is rejected" do
    assert @walk.accept!(@walker)
    assert_not @walk.accept!(@other_walker)
    assert_equal @walker.id, @walk.accepted_by_walker_id
  end

  test "start! by a walker who isn't the bound walker is rejected" do
    @walk.accept!(@walker)
    assert_not @walk.start!(@other_walker)
    assert @walk.accepted?
  end

  test "complete! by a walker who isn't the bound walker is rejected" do
    @walk.accept!(@walker)
    @walk.start!(@walker)
    assert_not @walk.complete!(@other_walker)
    assert @walk.in_progress?
  end

  test "cancel! after accept! is rejected" do
    @walk.accept!(@walker)
    assert_not @walk.cancel!(@owner)
    assert @walk.accepted?
  end

  test "accept! refuses a non-walker and refuses the owner self-accepting" do
    # accept! goes through update_all, which skips the role / owner!=walker
    # validations — so the guard must live in the method itself.
    assert_not @walk.accept!(@owner)
    assert @walk.requested?
    assert_nil @walk.accepted_by_walker_id
  end

  # --- Validations ---------------------------------------------------------

  test "owner_matches_dog_owner rejects a mismatched owner_id" do
    stranger = User.create!(email_address: "stranger@example.com", password: "secret123",
                            password_confirmation: "secret123", role: "owner", city: "Kraków")
    walk = Walk.new(dog: @dog, owner: stranger, city: "Kraków")
    assert_not walk.valid?
    assert_includes walk.errors[:owner_id], "must match the dog's owner"
  end

  test "an Owner cannot be the accepted_by_walker" do
    walk = Walk.new(dog: @dog, owner: @owner, city: "Kraków",
                    state: "accepted", accepted_by_walker: @owner)
    assert_not walk.valid?
    assert_includes walk.errors[:accepted_by_walker], "cannot be the owner"
  end

  test "city is required" do
    walk = Walk.new(dog: @dog, owner: @owner)
    assert_not walk.valid?
    assert_includes walk.errors[:city], "can't be blank"
  end

  test "latitude and longitude are required" do
    walk = Walk.new(dog: @dog, owner: @owner, city: "Kraków")
    assert_not walk.valid?
    assert_includes walk.errors[:latitude], "can't be blank"
    assert_includes walk.errors[:longitude], "can't be blank"
  end

  # --- One active request per dog ------------------------------------------

  test "a dog cannot have a second active walk request" do
    # @dog already has @walk (requested/active) from setup.
    dupe = Walk.new(dog: @dog, owner: @owner, city: "Kraków")
    assert_not dupe.valid?
    assert_includes dupe.errors[:base], "This dog already has an active walk request"
  end

  test "a new request is allowed once the dog's prior walk is finished" do
    @walk.cancel!(@owner) # requested -> cancelled (no longer active)
    fresh = Walk.new(dog: @dog, owner: @owner, city: "Kraków",
                     latitude: KRAKOW_LAT, longitude: KRAKOW_LNG)
    assert fresh.valid?, fresh.errors.full_messages.to_sentence
  end

  test "active scope covers requested/accepted/in_progress and excludes finished states" do
    assert_includes Walk.active, @walk # requested
    @walk.accept!(@walker)
    assert_includes Walk.active, @walk # accepted
    @walk.start!(@walker)
    assert_includes Walk.active, @walk # in_progress
    @walk.complete!(@walker)
    assert_not_includes Walk.active, @walk # completed
  end

  # --- Open-nearby scope (radius-based walker's open list) -----------------

  test "open_nearby includes walks within the radius and excludes walks beyond it" do
    near = make_walk("Near", city: "Kraków", latitude: NEAR_LAT, longitude: KRAKOW_LNG)
    far  = make_walk("Far",  city: "Kraków", latitude: FAR_LAT,  longitude: KRAKOW_LNG)

    result = Walk.open_nearby(city: "Kraków", latitude: KRAKOW_LAT, longitude: KRAKOW_LNG)
    assert_includes result, @walk # exact same point, from setup
    assert_includes result, near
    assert_not_includes result, far, "walk beyond MATCH_RADIUS_KM must be excluded"
  end

  test "open_nearby excludes a different city even within radius" do
    other_ct = make_walk("OtherCt", city: "Gdańsk", latitude: KRAKOW_LAT, longitude: KRAKOW_LNG)

    result = Walk.open_nearby(city: "Kraków", latitude: KRAKOW_LAT, longitude: KRAKOW_LNG)
    assert_not_includes result, other_ct
  end

  test "open_nearby excludes non-requested walks" do
    accepted = make_walk("Taken", city: "Kraków", latitude: KRAKOW_LAT, longitude: KRAKOW_LNG)
    accepted.update_columns(state: "accepted", accepted_by_walker_id: @walker.id, accepted_at: Time.current)

    result = Walk.open_nearby(city: "Kraków", latitude: KRAKOW_LAT, longitude: KRAKOW_LNG)
    assert_not_includes result, accepted
  end

  test "open_nearby excludes rows with nil coordinates" do
    nil_coords = make_walk("NilCoords", city: "Kraków", latitude: KRAKOW_LAT, longitude: KRAKOW_LNG)
    nil_coords.update_columns(latitude: nil, longitude: nil)

    result = Walk.open_nearby(city: "Kraków", latitude: KRAKOW_LAT, longitude: KRAKOW_LNG)
    assert_not_includes result, nil_coords
  end

  # --- distance_km_to (public, nil-safe Haversine) --------------------------

  test "distance_km_to is callable from outside the model" do
    assert_nothing_raised do
      @walk.distance_km_to(NEAR_LAT, KRAKOW_LNG)
    end
  end

  test "distance_km_to returns the correct known-good Haversine value" do
    # @walk sits at KRAKOW_LAT/LNG; NEAR_LAT is ~2km north at the same longitude.
    distance = @walk.distance_km_to(NEAR_LAT, KRAKOW_LNG)
    assert_in_delta 2.0, distance, 0.2
  end

  test "distance_km_to returns nil when this walk's own latitude is missing" do
    @walk.latitude = nil
    assert_nil @walk.distance_km_to(NEAR_LAT, KRAKOW_LNG)
  end

  test "distance_km_to returns nil when this walk's own longitude is missing" do
    @walk.longitude = nil
    assert_nil @walk.distance_km_to(NEAR_LAT, KRAKOW_LNG)
  end

  test "distance_km_to returns nil when the other point's latitude is missing" do
    assert_nil @walk.distance_km_to(nil, KRAKOW_LNG)
  end

  test "distance_km_to returns nil when the other point's longitude is missing" do
    assert_nil @walk.distance_km_to(NEAR_LAT, nil)
  end

  private
    def make_walk(dog_name, city:, latitude: KRAKOW_LAT, longitude: KRAKOW_LNG)
      dog = @owner.dogs.create!(name: dog_name, breed: "Labrador")
      dog.walks.create!(owner: @owner, city: city, latitude: latitude, longitude: longitude)
    end
end
