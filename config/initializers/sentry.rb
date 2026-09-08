Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"]
  config.breadcrumbs_logger = [ :active_support_logger, :http_logger ]
  config.send_default_pii = false
  config.environment = Rails.env
  config.release = ENV["RENDER_GIT_COMMIT"]
  config.traces_sample_rate = 0.2
  config.profiles_sample_rate = 0.0
end
