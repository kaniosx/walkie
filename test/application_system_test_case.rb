require "test_helper"
require "support/system_sign_in_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  include SystemSignInHelper

  # --no-sandbox and --disable-dev-shm-usage are required, not optional
  # hardening: the web container runs as root (no USER directive in
  # Dockerfile.dev) and Chrome refuses its sandbox as root, while Docker's
  # small default /dev/shm can crash Chrome without the second flag.
  #
  # The geolocation preference auto-grants the permission prompt so tests
  # never block on a UI dialog headless Chrome can't render; no test in this
  # suite currently depends on the "permission denied" path being exercised
  # automatically (that's manual-only, per the geolocation-matching plan), so
  # granting it globally is safe.
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ] do |driver_option|
    driver_option.add_argument("--no-sandbox")
    driver_option.add_argument("--disable-dev-shm-usage")
    driver_option.add_preference("profile.default_content_setting_values.geolocation", 1)
  end

  # Overrides the browser's reported position via CDP so a test can put a
  # user at a specific, deterministic lat/lng instead of whatever (if
  # anything) the test-runner host's real location resolves to.
  def set_geolocation(latitude:, longitude:)
    page.driver.browser.execute_cdp("Emulation.setGeolocationOverride",
                                     latitude: latitude, longitude: longitude, accuracy: 1)
  end
end
