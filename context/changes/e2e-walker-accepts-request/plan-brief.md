# Walker Accepts an Open Request — Plan Brief

> Full plan: `context/changes/e2e-walker-accepts-request/plan.md`

## What & Why

Add a second real-flow browser-level system test (roadmap **T-02**) proving a Walker can sign in, see an open walk request, and accept it — driving the north-star flow (S-05) through an actual rendered page instead of only an HTTP integration test. This extends the pattern `e2e-system-tests` (T-01) established, which was deliberately capped at two tests to prove the pipeline works before sweeping the app.

## Starting Point

T-01 already wired Rails System Tests (Capybara + Selenium) into Docker and CI, with two tests: a smoke test and one real flow (`owner_creates_walk_request_test.rb`). The Walker-accepts-request flow itself (S-05) is fully built and already has integration-test coverage for its HTTP contract, concurrency race, and role gating — this plan adds only the browser-level layer on top.

## Desired End State

A new `test/system/walker_accepts_request_test.rb` signs in as a Walker through the real login form, sees an Owner's open request in the list, clicks "Accept", and sees the confirmation — and this test is proven (via a deliberate-break check) to actually fail if the accept action breaks. A shared `sign_in_via_form` helper now backs both system tests, so the sign-in sequence isn't duplicated a third time when T-03/T-04/T-05 land.

## Key Decisions Made

| Decision | Choice | Why (1 sentence) | Source |
| --- | --- | --- | --- |
| Race-case coverage | Happy path only | Already proven at model + integration layers (`test-plan.md` §2 Risk #1); e2e's value here is the click-path, not re-proving the state machine | Plan |
| Assertion depth | Stop at the open-requests list | Matches T-02's roadmap outcome exactly; avoids coupling this test to `walker_walks` view internals | Plan |
| Sign-in duplication | Extract `test/support/system_sign_in_helper.rb`, retrofit existing test | 4 planned e2e tests (T-02..T-05) would otherwise carry 4 copies of the same block | Plan |
| Fixture shape | One open request, assert the empty-state text after accept | Simplest fixture; empty-state text is an unambiguous "it's gone" signal | Plan |

## Scope

**In scope:**
- `test/support/system_sign_in_helper.rb` (new)
- `test/application_system_test_case.rb` (wire in the helper)
- `test/system/owner_creates_walk_request_test.rb` (retrofit to use the helper)
- `test/system/walker_accepts_request_test.rb` (new)

**Out of scope:**
- The concurrency-race UI path
- Post-accept assertions on `walker_walks_path`
- Any CI, Gemfile, or Dockerfile changes (already in place from T-01)

## Architecture / Approach

Phase 1 isolates the helper extraction (touches only the already-passing existing test) from Phase 2's new coverage, mirroring T-01's own phasing discipline of separating infra changes from flow-logic changes.

## Phases at a Glance

| Phase | What it delivers | Key risk |
| --- | --- | --- |
| 1. Extract shared sign-in helper | Reusable `sign_in_via_form`, existing test retrofitted, behavior unchanged | A silent regression in the existing test if the extraction isn't behavior-preserving |
| 2. Add the walker-accepts-request test | New system test, deliberate-break verified | Flakiness (Selenium/Capybara timing) if waits aren't state-based |

**Prerequisites:** T-01 infra (done), S-05 feature (done) — both already in place.
**Estimated effort:** ~1 session across 2 phases.

## Open Risks & Assumptions

- Assumes `Walk.open_in_locality`'s exact city/postcode string match holds — a fixture typo would make the request silently invisible rather than erroring.
- Assumes the Phase 1 retrofit doesn't need re-review by anyone who depended on the old inline pattern — it's a pure refactor with no behavior change.

## Success Criteria (Summary)

- `bin/rails test:system` passes locally and in CI, including the new test.
- The new test is confirmed to fail when the accept action is deliberately broken, then pass again once reverted.
- No new duplication: the sign-in sequence exists in exactly one place.
