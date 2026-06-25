# HTTP Guardrails — Plan Brief

> Full plan: `context/changes/testing-http-guardrails/plan.md`
> Research: `context/changes/testing-http-guardrails/research.md`

## What & Why

Close the one remaining coverage gap from the Phase 1 HTTP guardrails audit and document
the integration-test conventions in the rollout cookbook. The gap: no test proves Walker2's
`/walker_walks` active section is empty while Walker1 has an accepted walk. Risks #1 and #4
are already fully covered by existing tests and need no duplication.

## Starting Point

`WalkerWalksTest` already has a two-walker setup with `@walk` accepted by `@walker`. The
"walker cannot see another walker's completed walk in history" test (line 105) closes the
past-section isolation. The active-section equivalent was never written.

## Desired End State

One new test in `walker_walks_test.rb` asserts `assert_not_includes response.body, "Rex"`
from Walker2's session while Walker1 has an active walk. The full suite passes. §6.1 of the
rollout cookbook replaces its TBD placeholder with a pattern note covering the three core
integration-test assertion patterns. §3 Phase 1 is marked `complete`.

## Key Decisions Made

| Decision | Choice | Why (1 sentence) | Source |
|---|---|---|---|
| Test scope | One new test only | Risks #1 and #4 are already fully covered by existing tests | Research |
| Phase structure | Two phases | Separates the runnable verification step (suite passes) from the documentation update | Plan |
| Cookbook detail | Pattern-focused (8–15 lines) | Enough for a future agent to write a correct integration test without reading existing tests | Plan |
| State assertions after 404 | Omit | RecordNotFound raises before any mutation can execute — the assertion is vacuous | Research |

## Scope

**In scope:**
- One new test case in `test/integration/walker_walks_test.rb`
- §6.1 cookbook entry in `context/foundation/test-plan.md`
- §3 Phase 1 status update to `complete`
- `change.md` status advance to `complete`

**Out of scope:**
- Redundant tests for Risk #1 or Risk #4 (already covered)
- Controller, model, route, or migration changes
- Phase 2 (state machine feedback) or Phase 3 (coverage gate)

## Architecture / Approach

Pure test-and-docs change. The new test uses the existing `WalkerWalksTest` setup verbatim:
sign in as `@walker2`, GET `/walker_walks`, assert `"Rex"` is absent. No new fixtures, no
new users, no infrastructure. The cookbook update replaces the §6.1 TBD placeholder in-place.

## Phases at a Glance

| Phase | What it delivers | Key risk |
|---|---|---|
| 1. Add isolation test | New test case green; walker active-section gap closed | Wrong assertion string if view renders something other than "Rex" |
| 2. Update cookbook & close | §6.1 filled; §3 Phase 1 marked complete | Cookbook too sparse to be actionable |

**Prerequisites:** Test suite runs (`docker compose exec web bin/rails test`)
**Estimated effort:** ~10 minutes total across 2 phases

## Open Risks & Assumptions

- Assertion string `"Rex"` is the dog name used in `walker_walks_test.rb` setup — confirmed
  by the existing test at line 24 (`assert_includes response.body, "Rex"`). If setup is ever
  changed to a different dog name, this assertion needs updating.
- The `WalkerWalksController` `start`/`complete` false-return (`else`) branch is a race path
  (not a sequential illegal-transition path) — this is a finding for Phase 2 research, not a
  risk for this plan.

## Success Criteria (Summary)

- `docker compose exec web bin/rails test test/integration/walker_walks_test.rb` — all tests
  pass including the new "walker cannot see another walker's accepted walk in active section"
- §6.1 cookbook gives a future agent enough to write a new integration test without opening
  any existing test file
- §3 Phase 1 row reads `complete`
