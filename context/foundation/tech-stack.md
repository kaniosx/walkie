---
starter_id: rails
package_manager: bundle
project_name: walkie
hints:
  language_family: ruby
  team_size: solo
  deployment_target: fly
  ci_provider: github-actions
  ci_default_flow: auto-deploy-on-merge
  bootstrapper_confidence: verified
  path_taken: standard
  quality_override: false
  self_check_answers: null
  has_auth: true
  has_payments: false
  has_realtime: false
  has_ai: false
  has_background_jobs: false
---

## Why this stack

Solo learner shipping a two-sided dog-walking marketplace MVP in 3 weeks of
after-hours work. Rails is the recommended default for `(web, ruby)` and fits
the PRD priors tightly: ActiveRecord + migrations cover the dog / walk / user
models, the linear walk state machine (REQUESTED → ACCEPTED → IN_PROGRESS →
COMPLETED) drops cleanly into a Rails model with validations plus a
transactional guard for the single-Walker-acceptance race, the built-in
`bin/rails generate authentication` covers FR-001 to FR-005, and role
separation is enforced via scoped queries and controller filters. Fly is the
starter's verified deployment default; CI on GitHub Actions with auto-deploy
on merge matches a solo / short-timeline build. One heads-up: Rails carries
`typed: false` in the agent-friendly registry — Ruby's discipline leans on
conventions + tests rather than static types — so the agent compensation
(documenting Rails conventions in `CLAUDE.md` / `AGENTS.md` after bootstrap)
matters more here than on a TypeScript stack.
