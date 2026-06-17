require "test_helper"

class WalkTest < ActiveSupport::TestCase
  def setup
    @owner = User.create!(email_address: "owner@example.com", password: "secret123",
                          password_confirmation: "secret123", role: "owner", city: "Kraków", postcode: "30-001")
    @walker = User.create!(email_address: "walker@example.com", password: "secret123",
                           password_confirmation: "secret123", role: "walker", city: "Kraków", postcode: "30-001")
    @other_walker = User.create!(email_address: "walker2@example.com", password: "secret123",
                                 password_confirmation: "secret123", role: "walker", city: "Kraków", postcode: "30-001")
    @dog = Dog.create!(name: "Rex", breed: "Labrador", user: @owner)
    @walk = Walk.create!(dog: @dog, owner: @owner, city: "Kraków", postcode: "30-001")
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
                            password_confirmation: "secret123", role: "owner", city: "Kraków", postcode: "30-001")
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

  test "postcode is required" do
    walk = Walk.new(dog: @dog, owner: @owner, city: "Kraków")
    assert_not walk.valid?
    assert_includes walk.errors[:postcode], "can't be blank"
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
    fresh = Walk.new(dog: @dog, owner: @owner, city: "Kraków", postcode: "30-001")
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

  # --- Open-in-locality scope (walker's open list) -------------------------

  test "open_in_locality returns only requested walks matching city and postcode" do
    # Distinct dogs so each walk dodges the one-active-per-dog guard.
    match     = make_walk("Match",   city: "Kraków", postcode: "30-001")
    other_pc  = make_walk("OtherPC", city: "Kraków", postcode: "30-999")
    other_ct  = make_walk("OtherCt", city: "Gdańsk", postcode: "30-001")
    accepted  = make_walk("Taken",   city: "Kraków", postcode: "30-001")
    accepted.update_columns(state: "accepted", accepted_by_walker_id: @walker.id, accepted_at: Time.current)

    result = Walk.open_in_locality("Kraków", "30-001")
    assert_includes result, match
    assert_not_includes result, other_pc,  "different postcode must be excluded"
    assert_not_includes result, other_ct,  "different city must be excluded"
    assert_not_includes result, accepted,  "non-requested walk must be excluded"
  end

  private
    def make_walk(dog_name, city:, postcode:)
      dog = @owner.dogs.create!(name: dog_name, breed: "Labrador")
      dog.walks.create!(owner: @owner, city: city, postcode: postcode)
    end
end
