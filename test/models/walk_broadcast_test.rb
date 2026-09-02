require "test_helper"
require "turbo/broadcastable/test_helper"

# Proves the Walk broadcast triggers fire exactly the expected target(s) per
# transition, and stay silent where they should — see plan §Phase 2 and
# §Phase 5 (per-Walker radius-aware fan-out).
class WalkBroadcastTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  KRAKOW_LAT = 50.0647
  KRAKOW_LNG = 19.9450
  # ~260km from Kraków — well beyond Walk::MATCH_RADIUS_KM (10km).
  WARSAW_LAT = 52.2297
  WARSAW_LNG = 21.0122

  def setup
    @owner = User.create!(email_address: "owner@example.com", password: "secret123",
                          password_confirmation: "secret123", role: "owner", city: "Kraków")
    @walker = User.create!(email_address: "walker@example.com", password: "secret123",
                           password_confirmation: "secret123", role: "walker", city: "Kraków")
    @dog = Dog.create!(name: "Rex", breed: "Labrador", user: @owner)
    @walk = Walk.create!(dog: @dog, owner: @owner, city: "Kraków", latitude: KRAKOW_LAT, longitude: KRAKOW_LNG)

    # The walker fan-out only reaches Walkers with a live cached location
    # (see WalkerLocationCache) — @walker is "currently viewing" throughout
    # this suite unless a test overrides/omits it.
    WalkerLocationCache.write(@walker, latitude: KRAKOW_LAT, longitude: KRAKOW_LNG)
  end

  def nearby_stream
    [ @walker, :nearby_open_requests ]
  end

  def owner_stream
    [ @owner, :active_walks ]
  end

  def walker_stream
    [ @walker, :current_walk ]
  end

  test "creating a walk broadcasts to the in-radius walker and owner streams, not the walker's current-walk stream" do
    dog = @owner.dogs.create!(name: "Fido", breed: "Beagle")

    assert_turbo_stream_broadcasts(nearby_stream, count: 2) do
      assert_turbo_stream_broadcasts(owner_stream, count: 2) do
        Walk.create!(dog: dog, owner: @owner, city: "Kraków", latitude: KRAKOW_LAT, longitude: KRAKOW_LNG)
      end
    end
    assert_no_turbo_stream_broadcasts(walker_stream)
  end

  test "creating a walk does not broadcast to a same-city walker whose cached location is out of radius" do
    far_walker = User.create!(email_address: "walker-far@example.com", password: "secret123",
                              password_confirmation: "secret123", role: "walker", city: "Kraków")
    WalkerLocationCache.write(far_walker, latitude: WARSAW_LAT, longitude: WARSAW_LNG)
    dog = @owner.dogs.create!(name: "Fido", breed: "Beagle")

    assert_no_turbo_stream_broadcasts([ far_walker, :nearby_open_requests ]) do
      Walk.create!(dog: dog, owner: @owner, city: "Kraków", latitude: KRAKOW_LAT, longitude: KRAKOW_LNG)
    end
  end

  test "creating a walk does not broadcast to a walker with no cached location" do
    idle_walker = User.create!(email_address: "walker-idle@example.com", password: "secret123",
                               password_confirmation: "secret123", role: "walker", city: "Kraków")
    dog = @owner.dogs.create!(name: "Fido", breed: "Beagle")

    assert_no_turbo_stream_broadcasts([ idle_walker, :nearby_open_requests ]) do
      Walk.create!(dog: dog, owner: @owner, city: "Kraków", latitude: KRAKOW_LAT, longitude: KRAKOW_LNG)
    end
  end

  test "accept! broadcasts the nearby, owner, and walker streams" do
    assert_turbo_stream_broadcasts(nearby_stream, count: 2) do
      assert_turbo_stream_broadcasts(owner_stream, count: 2) do
        assert_turbo_stream_broadcasts(walker_stream, count: 1) do
          assert @walk.accept!(@walker)
        end
      end
    end
  end

  test "start! broadcasts the owner and walker streams, but not the nearby stream" do
    @walk.accept!(@walker)

    assert_turbo_stream_broadcasts(nearby_stream, count: 0) do
      assert_turbo_stream_broadcasts(owner_stream, count: 2) do
        assert_turbo_stream_broadcasts(walker_stream, count: 1) do
          assert @walk.start!(@walker)
        end
      end
    end
  end

  test "complete! broadcasts the owner and walker streams, but not the nearby stream" do
    @walk.accept!(@walker)
    @walk.start!(@walker)

    assert_turbo_stream_broadcasts(nearby_stream, count: 0) do
      assert_turbo_stream_broadcasts(owner_stream, count: 2) do
        assert_turbo_stream_broadcasts(walker_stream, count: 1) do
          assert @walk.complete!(@walker)
        end
      end
    end
  end

  test "cancel! broadcasts the nearby and owner streams, but not the walker's current-walk stream" do
    assert_turbo_stream_broadcasts(nearby_stream, count: 2) do
      assert_turbo_stream_broadcasts(owner_stream, count: 2) do
        assert @walk.cancel!(@owner)
      end
    end
    assert_no_turbo_stream_broadcasts(walker_stream)
  end

  test "a failed transition (lost race / wrong state) broadcasts nothing" do
    @walk.accept!(@walker)

    assert_turbo_stream_broadcasts(nearby_stream, count: 0) do
      assert_turbo_stream_broadcasts(owner_stream, count: 0) do
        assert_turbo_stream_broadcasts(walker_stream, count: 0) do
          assert_not @walk.accept!(@walker) # already accepted — CAS loses
        end
      end
    end
  end
end
