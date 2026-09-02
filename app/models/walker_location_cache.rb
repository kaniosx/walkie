# Short-TTL cache of a Walker's last browser-reported coordinates, keyed by
# user id. OpenRequestsController/HomeController write to it on every
# geolocation-aware request (see plan §Phase 5); Walk#broadcast_open_requests_locality
# reads it at broadcast time to decide which Walkers are currently in range.
# :memory_store-backed — see plan §Critical Implementation Details for the
# single-Puma-worker caveat this depends on.
module WalkerLocationCache
  TTL = 10.minutes

  module_function

  def write(user, latitude:, longitude:)
    Rails.cache.write(key_for(user), { latitude: latitude.to_f, longitude: longitude.to_f }, expires_in: TTL)
  end

  def read(user)
    Rails.cache.read(key_for(user))
  end

  def key_for(user)
    "walker_location:#{user.id}"
  end
end
