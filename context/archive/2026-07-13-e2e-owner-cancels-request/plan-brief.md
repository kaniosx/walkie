# Owner Cancels a Requested Walk — Plan Brief

> Full plan: `context/changes/e2e-owner-cancels-request/plan.md`

## What & Why

Add a third real-flow browser-level system test (roadmap **T-03**) proving an Owner can sign in, create a walk request, and cancel it while still REQUESTED — driving S-06's cancellation flow through an actual rendered page instead of only integration-test coverage. Extends the pattern T-01/T-02 established.

## Starting Point

T-01 wired Rails System Tests into Docker/CI with a smoke test and one real flow. T-02 added a Walker-accepts-request test and extracted the shared `sign_in_via_form` helper (already wired into `ApplicationSystemTestCase` — no further infra work needed). The cancellation flow itself (S-06) is fully built and covered at the model/integration layer.

## Desired End State

A new `test/system/owner_cancels_request_test.rb` signs in as an Owner through the real login form, creates a walk request via the real "Walk my dog" button, clicks "Cancel", and sees the walk move from the Active table to the Past table with a "Cancelled" badge on the same `walks_path` page — proven (via a deliberate-break check) to actually fail if the cancel action breaks.

## Key Decisions Made

| Decision | Choice | Why (1 sentence) | Source |
| --- | --- | --- | --- |
| Assertion depth | Full round-trip: flash, Cancel button gone, "Cancelled" badge in Past section | Directly proves the roadmap outcome ("sees it reflected in history") on the one page that serves both roles | Plan |
| Deliberate-break target | Hardcode `Walk#cancel!` to return false | Mirrors T-02's pattern of breaking the model-level guard the controller depends on | Plan |
| Post-accept edge case | Out of scope — happy path only | Matches T-03's roadmap risk note ("no concurrency angle at browser layer"); already proven at the model layer by S-06 | Plan |
| Fixture shape | Reuse T-02's exact convention (Kraków/30-001), Owner-only, no Walker | Single-persona flow needs no Walker fixture; consistent literals across the e2e suite | Plan |
| Flakiness check | Yes, 2-3 consecutive local runs | Consistent bar across all e2e slices (T-02 through T-05) | Plan |
| Phasing | Single phase (no infra extraction) | Sign-in helper already exists from T-02 — nothing to isolate | Plan |

## Scope

**In scope:**
- `test/system/owner_cancels_request_test.rb` (new)

**Out of scope:**
- The post-accept ("Cancel button absent once ACCEPTED") restriction — already proven at the model layer
- Any changes to `test/support/system_sign_in_helper.rb` or `test/application_system_test_case.rb` — already done by T-02
- Any CI, Gemfile, or Dockerfile changes — already in place from T-01

## Architecture / Approach

One test, one phase: reuses the existing creation flow (`dogs_path` → "Walk my dog") from `owner_creates_walk_request_test.rb`, then chains the new cancel step and assertions on the same `walks_path` page load.

## Phases at a Glance

| Phase | What it delivers | Key risk |
| --- | --- | --- |
| 1. Add the owner-cancels-request test | New system test, deliberate-break verified | Flakiness (Selenium/Capybara timing, or the `turbo_confirm` dialog not auto-accepting) if waits aren't state-based |

**Prerequisites:** T-01 infra (done), T-02 sign-in helper (done), S-06 feature (done) — all already in place.
**Estimated effort:** ~1 session, single phase.

## Open Risks & Assumptions

- Assumes Selenium's default behavior of auto-accepting `confirm()` dialogs holds for the Cancel button's `turbo_confirm` — if not, the click would hang and the test would need explicit dialog-handling added.
- Assumes the Active→Past table move and badge text remain stable in `walks/index.html.erb` — a future redesign of that view would need this test updated alongside it.

## Success Criteria (Summary)

- `bin/rails test:system` passes locally and in CI, including the new test.
- The new test is confirmed to fail when `Walk#cancel!` is deliberately broken, then pass again once reverted.
- The Owner's cancelled walk is provably visible (correct badge) on the same history page the Cancel action redirects to.
