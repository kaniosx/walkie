require "test_helper"

class DogTest < ActiveSupport::TestCase
  def build_owner(attrs = {})
    User.create!({
      email_address: "owner@example.com",
      password: "secret123",
      password_confirmation: "secret123",
      role: "owner",
      city: "Kraków",
      postcode: "30-001"
    }.merge(attrs))
  end

  def build_dog(attrs = {})
    owner = attrs.delete(:user) || build_owner
    Dog.new({ name: "Rex", breed: "Labrador", user: owner }.merge(attrs))
  end

  test "valid dog saves" do
    dog = build_dog
    assert dog.save, dog.errors.full_messages.to_sentence
  end

  test "name is required" do
    dog = build_dog(name: nil)
    assert_not dog.valid?
    assert_includes dog.errors[:name], "can't be blank"
  end

  test "belongs_to :user is required" do
    dog = Dog.new(name: "Rex")
    assert_not dog.valid?
    assert_includes dog.errors[:user], "must exist"
  end

  test "breed is required" do
    dog = build_dog(breed: nil)
    assert_not dog.valid?
    assert_includes dog.errors[:breed], "can't be blank"
  end

  test "weight is optional but must be a positive bounded integer when present" do
    owner = build_owner
    assert build_dog(user: owner, weight: nil).valid?, "nil weight should be allowed"
    assert build_dog(user: owner, weight: 12).valid?, "a sane integer weight should be allowed"

    assert_not build_dog(user: owner, weight: 0).valid?
    assert_not build_dog(user: owner, weight: -1).valid?
    assert_not build_dog(user: owner, weight: 151).valid?
    assert_not build_dog(user: owner, weight: 12.5).valid?, "non-integer weight should be rejected"
  end

  test "notes is optional" do
    owner = build_owner
    assert build_dog(user: owner, notes: nil).valid?
    assert build_dog(user: owner, notes: "Friendly, pulls on the leash.").valid?
  end

  test "scope :active excludes deactivated dogs" do
    owner = build_owner
    active = Dog.create!(name: "Rex", breed: "Labrador", user: owner)
    gone = Dog.create!(name: "Fido", breed: "Beagle", user: owner, deactivated_at: Time.current)

    assert_includes Dog.active, active
    assert_not_includes Dog.active, gone
  end

  test "deactivate! sets deactivated_at and flips active?" do
    dog = build_dog
    dog.save!

    assert dog.active?
    assert_includes Dog.active, dog

    dog.deactivate!

    assert_not dog.active?
    assert_not_nil dog.deactivated_at
    assert_not_includes Dog.active, dog
    # Row still exists — soft-delete preserves history.
    assert Dog.exists?(dog.id)
  end
end
