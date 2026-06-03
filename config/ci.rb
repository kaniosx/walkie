# Run using bin/ci

CI.run do
  step "Setup", "bin/setup --skip-server"

  # Run tests early so failures (and the SimpleCov coverage gate, once COVERAGE_MIN
  # is raised in S-04/S-05/S-07) surface before the slower style/security steps.
  step "Tests", "bin/rails test"

  step "Style: Ruby", "bin/rubocop"

  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Importmap vulnerability audit", "bin/importmap audit"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"


  # Optional: set a green GitHub commit status to unblock PR merge.
  # Requires the `gh` CLI and `gh extension install basecamp/gh-signoff`.
  # if success?
  #   step "Signoff: All systems go. Ready for merge and deploy.", "gh signoff"
  # else
  #   failure "Signoff: CI failed. Do not merge or deploy.", "Fix the issues and try again."
  # end
end
