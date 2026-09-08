---
change_id: sentry-integration
title: Sentry error tracking + performance tracing (O-01)
status: implemented
created: 2026-09-08
updated: 2026-09-08
archived_at: null
---

## Notes

Roadmap O-01 (`context/foundation/roadmap.md`) — the only remaining non-parked,
non-blocked roadmap item. Independent of all feature slices.

Planned via `/10x-plan sentry-integration` with no upstream frame/research doc;
roadmap's O-01 entry already carried most of the outcome/risk decisions. Key
decisions made during planning (see plan-brief.md for full table):
- Sample rates lowered from roadmap's original 1.0/1.0 to 0.2/0.0, because the
  web service was downgraded to Render's free plan (`4219ffd`) after O-01 was
  written — that downgrade postdates and invalidates the original "1.0 is fine
  for early-MVP" reasoning.
- `send_default_pii = false` (roadmap said `true`) — L-01 added live-captured
  Owner/Walker geolocation after O-01 was written; sending IP/params/geo to a
  third party is a new consideration the roadmap didn't have in view.
- Backend only (no Sentry JS SDK) — matches roadmap's literal outcome.
- Add a light automated config test alongside the roadmap's manual smoke-test.
- Tag events with `environment` (Rails.env) + `release` (Render's built-in
  `RENDER_GIT_COMMIT`).

Phase 2 deviation (2026-09-08): the plan assumed Rails console access on
Render to trigger the smoke-test exception, but the free compute plan has no
shell/console. Decided to skip a temporary debug route and instead rely on a
naturally occurring unhandled exception in production — Sentry's Rack
middleware captures any unhandled request-cycle exception automatically, no
console needed. `SENTRY_DSN` is set and `walkie-web` redeployed (2.2/2.3
done).

Closed without live-event verification (2026-09-08): decided not to wait for
a naturally occurring exception. Progress 2.4-2.7 (event actually appears in
Sentry with correct `environment`/`release` tags and no PII in the payload)
are intentionally left unchecked/unverified — the plan is closed on the
strength of the code-level config test (`test/sentry_configuration_test.rb`,
Phase 1) plus the manual dashboard/deploy setup (2.1-2.3), not an observed
production event. If Sentry never shows an event, or shows one with wrong
tags or leaked PII, that would only surface later via manual inspection of
the Sentry dashboard — nothing in CI guards this end-to-end path.
