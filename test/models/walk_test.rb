require "test_helper"

class WalkTest < ActiveSupport::TestCase
  def setup
    @owner = User.create!(email_address: "owner@example.com", password: "secret123",
                          password_confirmation: "secret123", role: "owner")
    @walker = User.create!(email_address: "walker@example.com", password: "secret123",
                           password_confirmation: "secret123", role: "walker")
    @other_walker = User.create!(email_address: "walker2@example.com", password: "secret123",
                                 password_confirmation: "secret123", role: "walker")
    @dog = Dog.create!(name: "Rex", user: @owner)
    @walk = Walk.create!(dog: @dog, owner: @owner, city: "Kraków")
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
                            password_confirmation: "secret123", role: "owner")
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
end
