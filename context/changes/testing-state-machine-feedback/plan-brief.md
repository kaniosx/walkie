# State Machine Feedback — Plan Brief

> Full plan: `context/changes/testing-state-machine-feedback/plan.md`
> Research: `context/changes/testing-state-machine-feedback/research.md`

## What & Why

Rollout Phase 2 of `context/foundation/test-plan.md` (Risk #2): prove that a
Walker attempting an out-of-sequence transition on their *own* walk gets a
clear HTTP error, not a silent or misleading one. Research confirmed the
behavior is already correct (404, via the controller's state-scoped `find`)
— this closes a test-coverage gap, not a bug.

## Starting Point

`WalkerWalksController#start`/`#complete` scope their lookup by both owner
and required state in one query. A same-walker wrong-state call raises
`RecordNotFound` → 404; the controller's `if/else` flash branch is reachable
only via a real race, not by sequential misuse. No existing test varies
*state* for the correct walker — existing 404 tests vary only the *actor*
(IDOR), and existing model tests bypass the controller entirely.

## Desired End State

Four new tests: two integration tests proving the same-walker wrong-state
404 for `start`/`complete`, and two model-level concurrency tests proving
`start!`/`complete!` resolve to exactly one winner under real thread
contention (symmetric with the existing `accept!` race test). No production
code changes.

## Key Decisions Made

| Decision | Choice | Why | Source |
|---|---|---|---|
| Which wrong-state scenarios to test | 2 scenarios: complete-before-start ("skip"), double-start ("repeat") | Maps to PRD's "skip, repeat, or reverse" wording without redundant coverage of the identical 404 code path | Plan (user-confirmed) |
| Race test for the `else` branch | Add it — model-level, mirroring `accept!`'s race test | Symmetry with existing coverage; proves `swap_state` resolves correctly under contention for all three transition methods, not just `accept!` | Plan (user-confirmed) |
| New sequential model-level tests | None — integration-only for the sequential case | `walk_test.rb:43-52` already proves the guard generically; a 3rd/4th near-duplicate adds no signal | Plan (user-confirmed) |
| Does the race test cover the controller's flash text? | No — model layer only, same depth as the existing `accept!` test | No existing infra for genuinely concurrent HTTP requests in this codebase; not pursued for this phase | Plan |

## Scope

**In scope:**
- 2 integration tests in `test/integration/walker_walks_test.rb` (Phase 1)
- 2 model-level concurrency tests in `test/models/walk_concurrency_test.rb` (Phase 2)
- Updating `context/foundation/test-plan.md` §6 cookbook with the shipped patterns (Phase 2)

**Out of scope:**
- Any production code change (behavior already correct)
- "Start after complete" / "double-complete" integration tests
- New sequential model-level illegal-transition tests
- HTTP-level (controller) concurrency/race testing
- test-plan.md §1/§2 risk map edits (confirmed accurate) or §3 status (owned by `/10x-test-plan`)
- Rollout Phase 3 (coverage gate wiring)

## Architecture / Approach

Phase 1 follows the exact existing integration-test pattern (`sign_in_as` +
`assert_response :not_found`) already used for the IDOR case, just varying
state instead of actor. Phase 2 extends the existing `WalkConcurrencyTest`
class (same `use_transactional_tests = false` + `CyclicBarrier` +
per-thread-connection scaffolding) with two new race tests — one bound
walker racing itself, rather than N walkers racing each other as in the
existing `accept!` test.

## Phases at a Glance

| Phase | What it delivers | Key risk |
|---|---|---|
| 1. HTTP integration tests | 2 tests proving same-walker wrong-state → 404 | Copying the adjacent IDOR test's `@walker2` by habit instead of `@walker` — would silently retest the wrong scenario |
| 2. Model-level concurrency tests | 2 race tests for `start!`/`complete!` + test-plan.md §6 update | Real-thread tests can be flaky; needs a multi-run manual check before trusting a single green run |

**Prerequisites:** None — both phases are additive, no dependency on each other.
**Estimated effort:** ~1 session, both phases (test-only, no production code).

## Open Risks & Assumptions

- The concurrency tests assume the existing `Concurrent::CyclicBarrier` + real-thread pattern remains reliable in CI; if CI's DB connection pool is constrained, `WALKER_COUNT` (10) concurrent connections could need tuning (unlikely given the existing `accept!` test already does this).
- The race-test addition (Phase 2) is a planning-time scope extension beyond Risk #2 as sourced in test-plan.md §2 — documented in the plan and in test-plan.md §6.4, not silently added.

## Success Criteria (Summary)

- `docker compose exec web bin/rails test` passes, including all 4 new tests
- The 2 new integration tests fail when the controller's state scoping is temporarily weakened (proves they're not vacuous)
- The 2 new concurrency tests pass consistently across 5 repeated runs (not flaky)
