require "test_helper"

class WalkerLocationCacheTest < ActiveSupport::TestCase
  setup do
    @walker = User.create!(email_address: "walker@example.com", password: "secret123",
                           role: "walker", city: "Kraków")
  end

  test "write then read round-trips the coordinates as floats" do
    WalkerLocationCache.write(@walker, latitude: "50.0647", longitude: "19.9450")

    assert_equal({ latitude: 50.0647, longitude: 19.9450 }, WalkerLocationCache.read(@walker))
  end

  test "read returns nil for a walker with no cached location" do
    assert_nil WalkerLocationCache.read(@walker)
  end

  test "the cache entry expires after its TTL" do
    WalkerLocationCache.write(@walker, latitude: 50.0647, longitude: 19.9450)

    travel(WalkerLocationCache::TTL + 1.second) do
      assert_nil WalkerLocationCache.read(@walker)
    end
  end
end
