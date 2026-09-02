require "test_helper"
require "turbo/broadcastable/test_helper"

# Proves the Walk broadcast triggers fire exactly the expected target(s) per
# transition, and stay silent where they should — see plan §Phase 2.
class WalkBroadcastTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  def setup
    @owner = User.create!(email_address: "owner@example.com", password: "secret123",
                          password_confirmation: "secret123", role: "owner", city: "Kraków")
    @walker = User.create!(email_address: "walker@example.com", password: "secret123",
                           password_confirmation: "secret123", role: "walker", city: "Kraków")
    @dog = Dog.create!(name: "Rex", breed: "Labrador", user: @owner)
    @walk = Walk.create!(dog: @dog, owner: @owner, city: "Kraków", latitude: 50.0647, longitude: 19.9450)
  end

  def locality_stream
    [ "open_requests", "Kraków" ]
  end

  def owner_stream
    [ @owner, :active_walks ]
  end

  def walker_stream
    [ @walker, :current_walk ]
  end

  test "creating a walk broadcasts to the locality and owner streams, not the walker stream" do
    dog = @owner.dogs.create!(name: "Fido", breed: "Beagle")

    assert_turbo_stream_broadcasts(locality_stream, count: 2) do
      assert_turbo_stream_broadcasts(owner_stream, count: 2) do
        Walk.create!(dog: dog, owner: @owner, city: "Kraków", latitude: 50.0647, longitude: 19.9450)
      end
    end
    assert_no_turbo_stream_broadcasts(walker_stream)
  end

  test "accept! broadcasts the locality, owner, and walker streams" do
    assert_turbo_stream_broadcasts(locality_stream, count: 2) do
      assert_turbo_stream_broadcasts(owner_stream, count: 2) do
        assert_turbo_stream_broadcasts(walker_stream, count: 1) do
          assert @walk.accept!(@walker)
        end
      end
    end
  end

  test "start! broadcasts the owner and walker streams, but not the locality stream" do
    @walk.accept!(@walker)

    assert_turbo_stream_broadcasts(locality_stream, count: 0) do
      assert_turbo_stream_broadcasts(owner_stream, count: 2) do
        assert_turbo_stream_broadcasts(walker_stream, count: 1) do
          assert @walk.start!(@walker)
        end
      end
    end
  end

  test "complete! broadcasts the owner and walker streams, but not the locality stream" do
    @walk.accept!(@walker)
    @walk.start!(@walker)

    assert_turbo_stream_broadcasts(locality_stream, count: 0) do
      assert_turbo_stream_broadcasts(owner_stream, count: 2) do
        assert_turbo_stream_broadcasts(walker_stream, count: 1) do
          assert @walk.complete!(@walker)
        end
      end
    end
  end

  test "cancel! broadcasts the locality and owner streams, but not the walker stream" do
    assert_turbo_stream_broadcasts(locality_stream, count: 2) do
      assert_turbo_stream_broadcasts(owner_stream, count: 2) do
        assert @walk.cancel!(@owner)
      end
    end
    assert_no_turbo_stream_broadcasts(walker_stream)
  end

  test "a failed transition (lost race / wrong state) broadcasts nothing" do
    @walk.accept!(@walker)

    assert_turbo_stream_broadcasts(locality_stream, count: 0) do
      assert_turbo_stream_broadcasts(owner_stream, count: 0) do
        assert_turbo_stream_broadcasts(walker_stream, count: 0) do
          assert_not @walk.accept!(@walker) # already accepted — CAS loses
        end
      end
    end
  end
end
