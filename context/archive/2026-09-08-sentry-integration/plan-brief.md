# Sentry Integration (O-01) — Plan Brief

> Full plan: `context/changes/sentry-integration/plan.md`

## What & Why

Wire Sentry (`sentry-ruby` + `sentry-rails` + `stackprof`) into Walkie so unhandled exceptions and performance traces are captured automatically. This closes the last open item on the roadmap (O-01) — currently the app has no structured logging, error tracking, or metrics dashboard beyond STDOUT logs.

## Starting Point

No Sentry gem or initializer exists today. The app already has one precedent for secrets that must never be committed: `RAILS_MASTER_KEY` is declared in `render.yaml` with `sync: false` and set by hand in the Render dashboard — `SENTRY_DSN` will follow the same path. Two things changed *after* the roadmap wrote O-01's outcome, and both push this plan's decisions away from what the roadmap originally assumed: the web service was downgraded to Render's **free plan** (`4219ffd`), and L-01 added **live geolocation capture** (Owner/Walker lat/lng).

## Desired End State

In production, once `SENTRY_DSN` is set, unhandled exceptions and 20% of performance traces reach Sentry, tagged with `environment` and `release` (git SHA) so an incident can be traced to the deploy that caused it. No IP address, request params, or profiling data leaves the app. A regression that hard-codes a DSN or silently reverts the config is caught by an automated test, not just code review.

## Key Decisions Made

| Decision | Choice | Why (1 sentence) | Source |
| --- | --- | --- | --- |
| Sample rates | `traces_sample_rate = 0.2`, `profiles_sample_rate = 0.0` (roadmap said 1.0/1.0) | Web service moved to Render's free plan after O-01 was written; continuous profiling there is avoidable overhead | Plan |
| PII | `send_default_pii = false` (roadmap said `true`) | L-01's live geolocation capture postdates O-01's original PII reasoning — don't leak lat/lng/IP to a third party | Plan |
| Geolocation filtering | Add `lat`, `lng`, `latitude`, `longitude` to the existing `filter_parameters` list | Defense-in-depth alongside `send_default_pii = false` | Plan |
| Scope | Backend only (`sentry-ruby`/`sentry-rails`), no JS SDK | Matches roadmap O-01's literal outcome | Roadmap |
| Verification | Manual Render smoke-test **+** a light automated config-assertion test | Roadmap's manual-only smoke-test doesn't catch a silent regression (e.g. a future edit reverting `send_default_pii` or hard-coding a DSN) | Plan |
| Release attribution | Tag events with `environment: Rails.env` and `release: RENDER_GIT_COMMIT` | Render has no first-class rollback CLI (per `infrastructure.md`); release tags make it possible to trace an incident to its deploy | Plan |

## Scope

**In scope:** Gem install, one initializer, extending the existing PII filter list, one automated config test, `render.yaml` env var declaration, one manual production smoke test.

**Out of scope:** Sentry JS/browser SDK, per-environment sample-rate override via env var, any Sentry-side alerting/dashboard/ownership configuration, changes to existing logging setup.

## Architecture / Approach

Single path, no competing designs: three gems added outside any `group` block (so they ship in the production Docker image, which only excludes the `development` bundler group) → one initializer reading `SENTRY_DSN` from `ENV` (safe no-op when unset, so dev/test need no conditional guard) → `render.yaml` gets the same `sync: false` treatment as `RAILS_MASTER_KEY` → one manual Rails-console smoke test against the real Render deploy, since CI has no staging environment to verify actual event delivery.

## Phases at a Glance

| Phase | What it delivers | Key risk |
| --- | --- | --- |
| 1. Gems, initializer, automated config test | All code changes, fully verifiable locally/in CI without touching Render | A future edit silently hard-codes a DSN or flips `send_default_pii` back to `true` — mitigated by the new config test |
| 2. Render deploy wiring + production smoke test | `SENTRY_DSN` set in Render, one real captured exception confirmed in the Sentry dashboard | This is the only way to prove events actually arrive — no CI staging deploy exists to automate it |

**Prerequisites:** A Sentry account/project (Rails platform) must exist before Phase 2 — this is a one-time external setup step, not code.
**Estimated effort:** ~1 session, both phases — small, well-contained change.

## Open Risks & Assumptions

- Assumes Render auto-populates `RENDER_GIT_COMMIT` at runtime (documented Render behavior) — confirmed during Phase 2's manual verification, not assumed blindly.
- Sample rates (0.2/0.0) are a starting point tied to the current free-tier plan; revisit upward if the plan is upgraded (parallels roadmap Open Q #3 on the Postgres free tier).
- No automated way to verify actual Sentry event delivery — Phase 2's manual smoke test is the only check; a silent misconfiguration that passes Phase 1's tests but still fails to deliver (e.g. wrong DSN typo'd into the dashboard) would only surface at the next real production error if the one-time smoke test is skipped.

## Success Criteria (Summary)

- An exception raised in production reaches the Sentry dashboard, correctly tagged, without PII.
- `bin/rails test`, `rubocop`, `brakeman`, and `bundler-audit` all pass with the new gems in place.
- No `SENTRY_DSN` value ever appears in git history.
