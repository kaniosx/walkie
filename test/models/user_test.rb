require "test_helper"

class UserTest < ActiveSupport::TestCase
  def build_user(attrs = {})
    User.new({
      email_address: "owner@example.com",
      password: "secret123",
      password_confirmation: "secret123",
      role: "owner",
      city: "Kraków",
      postcode: "30-001"
    }.merge(attrs))
  end

  test "valid user with a role saves" do
    user = build_user
    assert user.save, user.errors.full_messages.to_sentence
  end

  test "role is required" do
    user = build_user(role: nil)
    assert_not user.valid?
    assert_includes user.errors[:role], "can't be blank"
  end

  test "role enum exposes predicates and scopes" do
    owner = build_user(email_address: "o@example.com", role: "owner")
    walker = build_user(email_address: "w@example.com", role: "walker")
    owner.save!
    walker.save!

    assert owner.owner?
    assert_not owner.walker?
    assert walker.walker?

    assert_includes User.owner, owner
    assert_not_includes User.owner, walker
    assert_includes User.walker, walker
  end

  test "role cannot change after registration" do
    user = build_user(role: "owner")
    user.save!

    user.role = "walker"
    assert_not user.valid?
    assert_includes user.errors[:role], "cannot be changed after registration"
    assert_not user.save
  end

  test "has_secure_password authenticates correct credentials and rejects wrong ones" do
    user = build_user
    user.save!

    assert user.authenticate("secret123")
    assert_not user.authenticate("wrong-password")
  end

  test "email_address is normalized to stripped lowercase" do
    user = build_user(email_address: "  Owner@Example.COM  ")
    user.save!
    assert_equal "owner@example.com", user.email_address
  end

  test "city is required" do
    user = build_user(city: nil)
    assert_not user.valid?
    assert_includes user.errors[:city], "can't be blank"
  end

  test "postcode is required" do
    user = build_user(postcode: nil)
    assert_not user.valid?
    assert_includes user.errors[:postcode], "can't be blank"
  end

  test "city and postcode reject overlong values" do
    user = build_user(city: "a" * 101, postcode: "b" * 101)
    assert_not user.valid?
    assert_includes user.errors[:city], "is too long (maximum is 100 characters)"
    assert_includes user.errors[:postcode], "is too long (maximum is 100 characters)"
  end

  test "city and postcode are stripped of surrounding whitespace" do
    user = build_user(city: "  Kraków  ", postcode: "  30-001 ")
    user.save!
    assert_equal "Kraków", user.city
    assert_equal "30-001", user.postcode
  end

  test "display_name is optional" do
    user = build_user(display_name: nil)
    assert user.valid?, user.errors.full_messages.to_sentence
  end

  test "display_label returns display_name when present, email when blank" do
    named = build_user(display_name: "Ada")
    assert_equal "Ada", named.display_label

    unnamed = build_user(display_name: nil)
    assert_equal unnamed.email_address, unnamed.display_label
  end
end
