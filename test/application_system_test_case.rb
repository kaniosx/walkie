require "test_helper"
require "support/system_sign_in_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  include SystemSignInHelper

  # --no-sandbox and --disable-dev-shm-usage are required, not optional
  # hardening: the web container runs as root (no USER directive in
  # Dockerfile.dev) and Chrome refuses its sandbox as root, while Docker's
  # small default /dev/shm can crash Chrome without the second flag.
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ] do |driver_option|
    driver_option.add_argument("--no-sandbox")
    driver_option.add_argument("--disable-dev-shm-usage")
  end
end
