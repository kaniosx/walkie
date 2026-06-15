# SimpleCov MUST start before the app boots — it only counts files loaded after
# SimpleCov.start, and most of app/ loads during the environment require below.
# Keep these the first executable lines of this file.
require "simplecov"
SimpleCov.start "rails" do
  enable_coverage :branch

  # Scope coverage to code we write. Drop generated framework boilerplate so the
  # percentage reflects the four core flows the PRD's ≥80% Guardrail targets, not
  # scaffolding. (The "rails" profile already filters config/, test/, db/, bin/, vendor/.)
  add_filter "app/channels/application_cable"
  add_filter "app/mailers/application_mailer"
  add_filter "app/jobs/application_job"
  add_filter "app/models/application_record"
  add_filter "app/controllers/application_controller"
  add_filter "app/helpers/application_helper"

  add_group "Models", "app/models"
  add_group "Controllers", "app/controllers"

  # Dormant-but-wired coverage gate. Report-only today (COVERAGE_MIN defaults to 0)
  # because the four core flows — create-request / accept / start / complete — don't
  # exist yet. The slice that completes the lifecycle (S-05, with S-04/S-07) raises
  # this to 80 (set COVERAGE_MIN=80 in CI, or change the default here) so the PRD's
  # ≥80% Guardrail becomes binding once the flows it scopes to exist. Flipping this
  # one knob enforces the gate across local runs and CI alike.
  coverage_min = ENV.fetch("COVERAGE_MIN", "0").to_f
  minimum_coverage(line: coverage_min, branch: coverage_min) if coverage_min.positive?
end

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# Make the coverage gate above actually fail `bin/rails test`. Minitest's autorun
# installs a final at_exit that calls `exit exit_code` (minitest.rb) *after*
# SimpleCov's own at_exit, swallowing SimpleCov's non-zero coverage exit — so the
# raw gate enforces under `ruby -Itest` but silently no-ops under `bin/rails test`
# (and thus bin/ci and GitHub Actions). `Minitest.after_run` runs inside that final
# handler, before `exit exit_code`, so exiting here is the last word. No-op in
# report-only mode (COVERAGE_MIN unset → no minimum → status 0).
Minitest.after_run do
  if SimpleCov.result?
    status = SimpleCov.result_exit_status(SimpleCov.result)
    Kernel.exit(status) if status.nonzero?
  end
end

module ActiveSupport
  class TestCase
    # Load fixtures from test/fixtures/*.yml (none yet — users are built inline
    # because has_secure_password needs a real password, not a digest in YAML).
    fixtures :all
  end
end
