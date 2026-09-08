require "test_helper"

class SentryConfigurationTest < ActiveSupport::TestCase
  test "DSN comes from ENV, never a literal baked into the initializer" do
    assert_nil Sentry.configuration.dsn, "SENTRY_DSN is unset in test — a non-nil dsn means it was hard-coded"
  end

  test "PII capture is disabled" do
    assert_equal false, Sentry.configuration.send_default_pii
  end

  test "sample rates match the free-tier-conscious values" do
    assert_equal 0.2, Sentry.configuration.traces_sample_rate
    assert_equal 0.0, Sentry.configuration.profiles_sample_rate
  end

  test "environment tag tracks Rails.env" do
    assert_equal Rails.env, Sentry.configuration.environment
  end
end
