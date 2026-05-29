ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Load fixtures from test/fixtures/*.yml (none yet — users are built inline
    # because has_secure_password needs a real password, not a digest in YAML).
    fixtures :all
  end
end
