require "test_helper"

class DogsTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(email_address: "owner@example.com", password: "secret123",
                          role: "owner", city: "Kraków")
    @other_owner = User.create!(email_address: "owner2@example.com", password: "secret123",
                                role: "owner", city: "Kraków")
    @walker = User.create!(email_address: "walker@example.com", password: "secret123",
                           role: "walker", city: "Kraków")
  end

  def sign_in_as(email)
    post session_path, params: { email_address: email, password: "secret123" }
  end

  test "owner can view index, new, and add a dog scoped to themselves" do
    sign_in_as "owner@example.com"

    get dogs_path
    assert_response :success
    get new_dog_path
    assert_response :success

    assert_difference -> { @owner.dogs.count }, 1 do
      post dogs_path, params: { dog: { name: "Rex", breed: "Labrador", weight: 12, notes: "Friendly" } }
    end
    assert_redirected_to dogs_path
    assert_equal "Rex", @owner.dogs.last.name
  end

  test "owner can edit their own dog" do
    sign_in_as "owner@example.com"
    dog = @owner.dogs.create!(name: "Rex", breed: "Labrador")

    get edit_dog_path(dog)
    assert_response :success

    patch dog_path(dog), params: { dog: { name: "Rexy", breed: "Lab", weight: 14 } }
    assert_redirected_to dogs_path
    dog.reload
    assert_equal "Rexy", dog.name
    assert_equal 14, dog.weight
  end

  test "adding a dog without a breed re-renders and creates nothing" do
    sign_in_as "owner@example.com"
    assert_no_difference -> { Dog.count } do
      post dogs_path, params: { dog: { name: "Rex", breed: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "index lists only the current owner's dogs" do
    mine = @owner.dogs.create!(name: "Rex", breed: "Labrador")
    theirs = @other_owner.dogs.create!(name: "Fido", breed: "Beagle")

    sign_in_as "owner@example.com"
    get dogs_path
    assert_response :success
    assert_includes response.body, "Rex"
    assert_not_includes response.body, "Fido"
  end

  # Scoped find on a foreign id yields a 404, so neither the edit form nor the
  # update can reach another owner's dog (RecordNotFound → not_found response).
  test "an owner cannot open the edit form for another owner's dog" do
    theirs = @other_owner.dogs.create!(name: "Fido", breed: "Beagle")
    sign_in_as "owner@example.com"
    get edit_dog_path(theirs)
    assert_response :not_found
  end

  test "an owner cannot update another owner's dog" do
    theirs = @other_owner.dogs.create!(name: "Fido", breed: "Beagle")
    sign_in_as "owner@example.com"
    patch dog_path(theirs), params: { dog: { name: "Hacked" } }
    assert_response :not_found
    assert_equal "Fido", theirs.reload.name
  end

  test "a walker is blocked from dog management" do
    sign_in_as "walker@example.com"

    get dogs_path
    assert_redirected_to root_path
    assert_equal "Only Owners can do that.", flash[:alert]

    assert_no_difference -> { Dog.count } do
      post dogs_path, params: { dog: { name: "Rex", breed: "Labrador" } }
    end
    assert_redirected_to root_path
  end

  test "unauthenticated access to dogs redirects to sign-in" do
    get dogs_path
    assert_redirected_to new_session_path
  end

  test "owner can deactivate dog with no active walks" do
    sign_in_as "owner@example.com"
    dog = @owner.dogs.create!(name: "Buddy", breed: "Labrador")

    assert_difference -> { Dog.active.count }, -1 do
      delete dog_path(dog)
    end
    assert_redirected_to dogs_path
    assert_match "Buddy", flash[:notice]
    assert_not dog.reload.active?
    get dogs_path
    assert_no_match edit_dog_path(dog), response.body
  end

  test "owner cannot deactivate dog with active walk" do
    sign_in_as "owner@example.com"
    dog = @owner.dogs.create!(name: "Buddy", breed: "Labrador")
    Walk.create!(dog: dog, owner: @owner, state: "requested", city: "Kraków")

    delete dog_path(dog)
    assert_redirected_to dogs_path
    assert_match "Buddy", flash[:alert]
    assert dog.reload.active?
  end

  test "owner cannot deactivate another owner's dog" do
    theirs = @other_owner.dogs.create!(name: "Fido", breed: "Beagle")
    sign_in_as "owner@example.com"
    delete dog_path(theirs)
    assert_response :not_found
    assert theirs.reload.active?
  end

  test "walker cannot deactivate a dog" do
    dog = @owner.dogs.create!(name: "Buddy", breed: "Labrador")
    sign_in_as "walker@example.com"
    delete dog_path(dog)
    assert_redirected_to root_path
    assert dog.reload.active?
  end

  test "unauthenticated cannot deactivate a dog" do
    dog = @owner.dogs.create!(name: "Buddy", breed: "Labrador")
    delete dog_path(dog)
    assert_redirected_to new_session_path
    assert dog.reload.active?
  end
end
