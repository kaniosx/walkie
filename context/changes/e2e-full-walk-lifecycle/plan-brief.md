# Full Walk Lifecycle — Plan Brief

> Full plan: `context/changes/e2e-full-walk-lifecycle/plan.md`

## What & Why

Add a fourth real-flow browser-level system test (roadmap **T-04**) proving the entire walk lifecycle end-to-end through the browser: Owner creates a request, Walker accepts/starts/completes it — asserting the flash and visible state badge after every transition. This is the one test in the e2e batch that chains all four transitions and both personas in a single scenario, by explicit roadmap design.

## Starting Point

T-01 wired system-test infra; T-02 added the shared sign-in helper; T-03 proved the two-persona + `turbo_confirm`-dialog patterns needed here. Every individual transition (create, accept, start, complete) already has a proven pattern from an existing system test or is fully covered at the integration layer (S-04/S-05/S-07) — this plan only chains them together at the browser layer for the first time.

## Desired End State

A new `test/system/full_walk_lifecycle_test.rb` signs in as an Owner, creates a walk request, signs out; signs in as a Walker, accepts the request (badge: "Accepted"), starts it (badge: "In progress"), and completes it — with the flash message and state badge checked after every step. Proven via a deliberate-break check on `Walk#start!` to actually fail if a transition breaks.

## Key Decisions Made

| Decision | Choice | Why (1 sentence) | Source |
| --- | --- | --- | --- |
| Persona switching | Sign out, sign back in as the other persona (single Capybara session) | Exercises the real session boundary; the flow is strictly sequential, not concurrent, so `using_session` adds complexity with no benefit | Plan |
| Assertion depth | Flash message + state badge after every transition | Directly matches the roadmap outcome ("asserting the visible state badge after each transition"); catches a broken step at the exact point it breaks | Plan |
| Fixture shape | Reuse Kraków/30-001 convention, Owner + Walker, one dog | Consistent literals across the e2e suite; the `Walk.open_in_locality` exact-match gotcha is already a known quantity | Plan |
| Scope boundary | Stop once the Walker completes the walk — no Owner-side history check | Matches the roadmap's stated scope; Owner-side rendering is T-05's job, not orphaned | Plan |
| Deliberate-break target | `Walk#start!` only (one representative transition) | Shares the identical `swap_state` guard already proven breakable by T-02/T-03's checks on `accept!`/`cancel!` — no need to re-verify the same pattern 4x | Plan |
| Intermediate badges | Assert "Accepted" after accept and "In progress" after start, before the next click | Confirms each transition lands on the right page in the right state before proceeding — consistent depth across the whole chain | Plan |
| Flakiness bar | 3 consecutive clean runs, same as T-02/T-03 | Consistent bar across the e2e suite; sufficient given T-02/T-03 already showed zero flakiness at this bar | Plan |
| Phasing | Single phase (no infra extraction) | Sign-in helper and confirm-dialog pattern both already exist from T-02/T-03 | Plan |

## Scope

**In scope:**
- `test/system/full_walk_lifecycle_test.rb` (new)

**Out of scope:**
- Owner-side history view assertions after completion (T-05's scope)
- Deliberate-break checks on `accept!`/`complete!`/`cancel!` (already proven breakable by T-02/T-03 on the same guard pattern)
- Any changes to sign-in helper, CI, Gemfile, or Dockerfile — already in place

## Architecture / Approach

One test, one phase: chains four already-proven transitions (create → accept → start → complete) across two personas in a single Capybara session, using `sign_in_via_form` + a plain sign-out click for persona switching, and `accept_confirm { click_on "End walk" }` for the one `turbo_confirm`-guarded button in the chain.

## Phases at a Glance

| Phase | What it delivers | Key risk |
| --- | --- | --- |
| 1. Add the full-walk-lifecycle test | New system test chaining all 4 transitions, deliberate-break verified | Flakiness — explicitly the longest/most flake-prone test in the batch per the roadmap's own risk note |

**Prerequisites:** T-01 infra (done), T-02/T-03 patterns (done), S-04/S-05/S-07 features (done) — all already in place.
**Estimated effort:** ~1 session, single phase.

## Open Risks & Assumptions

- Assumes the two-persona single-session sign-out/sign-in-again pattern doesn't leak any authenticated state between personas — consistent with how Rails sessions work, and no existing test suggests otherwise.
- This is the longest-running system test in the suite (4 transitions + 2 sign-ins); a slow CI runner could make the 3-consecutive-run flakiness bar take noticeably longer than T-02/T-03's checks did.

## Success Criteria (Summary)

- `bin/rails test:system` passes locally and in CI, including the new test.
- The new test is confirmed to fail when `Walk#start!` is deliberately broken, then pass again once reverted.
- Every one of the four transitions (create, accept, start, complete) has its flash message and resulting state badge verified in the browser.
