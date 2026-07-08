# State Machine Feedback Implementation Plan

## Overview

Close rollout Phase 2 of `context/foundation/test-plan.md` (Risk #2): prove that a
Walker attempting an out-of-sequence state transition on their *own* walk gets a
clear HTTP error, not a silent or misleading response, and add symmetric
concurrency coverage for `start!`/`complete!` alongside the existing `accept!`
race test.

## Current State Analysis

`WalkerWalksController#start`/`#complete` (`app/controllers/walker_walks_controller.rb:21-42`)
scope their lookup by both owner and required state in a single
`Walk.where(accepted_by_walker_id: ..., state: ...).find(params[:id])` call. A
same-walker call on a walk in the wrong state never reaches the controller's
`if/else` flash branch — the scoped `find` raises `ActiveRecord::RecordNotFound`,
which `ApplicationController` rescues to a plain 404
(`app/controllers/application_controller.rb:4,13-15`). The `else` branch
("This walk can no longer be updated.") is reachable only via a genuine race
between the controller's `find` and the model's `swap_state` compare-and-swap
(`app/models/walk.rb:77-84`).

No existing test exercises this. `test/integration/walker_walks_test.rb:63-67,76-81`
prove the 404 path only for a *different* walker (the IDOR/authorization
dimension of the scope); they never vary state for the correct walker.
`test/models/walk_test.rb:43-52` prove the model's illegal-transition guard
directly on the AR object, bypassing the controller entirely. Neither proves
what HTTP response a real request produces when the correct walker's own walk
is simply in the wrong state. `test/models/walk_concurrency_test.rb` proves
exactly one thread wins a simultaneous `accept!` race, but covers `accept!`
only — `start!`/`complete!` have no analogous race coverage.

Full grounding: `context/changes/testing-state-machine-feedback/research.md`.

## Desired End State

Two new integration tests prove that a Walker calling `start`/`complete` on
their own walk, when it is in the wrong state, gets HTTP 404 — the same
mechanism as the existing IDOR case, for a different reason. Two new
model-level concurrency tests prove `start!`/`complete!` resolve to exactly one
winner under real thread contention, symmetric with the existing `accept!`
race test. No production code changes — the behavior is already correct;
this closes a test-coverage gap only.

Verification: `docker compose exec web bin/rails test test/integration/walker_walks_test.rb test/models/walk_concurrency_test.rb` passes, and the four new tests fail if their corresponding guard (the state-scoped `find`, or `swap_state`'s atomic `WHERE`) is temporarily weakened — proving they pin real behavior rather than passing vacuously.

### Key Discoveries:

- `app/controllers/walker_walks_controller.rb:24,35` — the state-scoped `find` is the actual guard; the `if/else` on `start!`/`complete!`'s return value only fires on a race, not on sequential misuse.
- `test/integration/walks_cancel_test.rb:31-42` is a same-actor/wrong-state precedent, but for `cancel`, whose controller query (`current_user.owned_walks.find(params[:id])`) is *not* state-scoped — so it legitimately reaches an alert, not a 404. That assertion shape does not transfer to `start`/`complete`.
- `test/models/walk_concurrency_test.rb:8-73` is the exact pattern to extend for the new race tests: `self.use_transactional_tests = false`, a `Concurrent::CyclicBarrier`, per-thread `ActiveRecord::Base.connection_pool.with_connection`, and hand-rolled `purge_fixtures` teardown (Minitest's default transactional wrapping would serialize thread writes and hide any race).

## What We're NOT Doing

- No production code changes to `WalkerWalksController` or `Walk` — the 404 behavior is already correct.
- No integration tests for "start after complete" or "double-complete" — the complete-before-start and double-start tests already exercise the identical scoped-find→404 mechanism; PRD's "skip, repeat, or reverse" wording is covered by the "skip" and "repeat" cases without redundant coverage of the same code path.
- No new sequential model-level illegal-transition tests (e.g. a plain `start!`-twice assertion) — `test/models/walk_test.rb:43-52` already proves `swap_state`'s guard generically; a 3rd/4th near-duplicate assertion adds no new signal.
- The new concurrency tests do not exercise the controller or the HTTP-rendered flash message — they prove the model-level race resolves correctly, at the same layer and to the same depth as the existing `accept!` race test. Testing the controller's flash text under genuine concurrent HTTP requests would need infrastructure this codebase doesn't have and no other test uses; not pursued here.
- No edits to `context/foundation/test-plan.md` §1/§2 (risk map) — research confirmed the existing Risk #2 wording and response guidance accurate; no correction needed. §3 status is owned by `/10x-test-plan`'s reconciliation, not this plan.
- Not addressing rollout Phase 3 (coverage gate wiring) — separate change.

## Implementation Approach

Phase 1 delivers the risk-map's core ask (Risk #2) with two integration tests
following the exact existing pattern in `walker_walks_test.rb` (`sign_in_as` +
`assert_response :not_found`). Phase 2 is a deliberate scope extension — not
sourced from test-plan.md's risk map, but chosen during planning for symmetry
with the existing `accept!` race test — adding the equivalent race coverage
for `start!`/`complete!` at the model layer, and closes out the rollout phase
by filling in test-plan.md's §6 cookbook.

## Critical Implementation Details

### Phase 1 — sign in as the correct walker, not the IDOR walker

The two new tests must sign in as `@walker` (the walker who legitimately holds
the walk via the outer `setup` block's `@walk.accept!(@walker)`), never
`@walker2`. The two existing 404 tests immediately above the insertion point
(`walker_walks_test.rb:63-67,76-81`) use `@walker2` for the IDOR case — copying
that pattern verbatim would silently retest the already-covered wrong-actor
case instead of the wrong-state case this phase targets.

### Phase 2 — one walker racing itself, not N walkers racing for one slot

The existing `accept!` race test has 10 *distinct* walkers all racing to
accept the *same* walk — only one can win because the walk can only be bound
to one walker. The `start!`/`complete!` races are structurally different: the
walk is already bound to a *single* walker (`@walkers.first`), and the race is
that same walker's own concurrent requests (e.g. a double-tap or duplicate
client retry) contending on the same `swap_state` compare-and-swap. Reuse
`WALKER_COUNT` as the concurrent-attempt count for that one walker, not as a
count of distinct racing walkers — do not spread the concurrent calls across
`@walkers`.

## Phase 1: HTTP integration tests — same-walker wrong-state 404

### Overview

Add two integration tests to `test/integration/walker_walks_test.rb` proving
Risk #2's core claim: a Walker's own walk in the wrong state 404s on
`start`/`complete`, exactly like the existing IDOR case.

### Changes Required:

#### 1. Same-walker "complete before start" test

**File**: `test/integration/walker_walks_test.rb`

**Intent**: Prove that calling `complete` on the walker's own walk while it is
still `accepted` (never started) 404s — the "skip a state" case from the
PRD's "skip, repeat, or reverse" wording.

**Contract**: New `test` block, placed near the existing 404 tests
(`walker_walks_test.rb:63-81`). Sign in as `@walker` (not `@walker2`); do not
call `@walk.start!` first (the outer `setup` already leaves `@walk` in
`accepted` state via `@walk.accept!(@walker)`). `post complete_walker_walk_path(@walk)`;
`assert_response :not_found`.

#### 2. Same-walker "double start" test

**File**: `test/integration/walker_walks_test.rb`

**Intent**: Prove that calling `start` a second time on the walker's own walk,
once it is already `in_progress`, 404s — the "repeat a transition" case.

**Contract**: New `test` block, same file, near the tests above. Sign in as
`@walker`; call `@walk.start!(@walker)` once first to reach `in_progress`;
then `post start_walker_walk_path(@walk)` again; `assert_response :not_found`.

### Success Criteria:

#### Automated Verification:

- [ ] Full test file passes: `docker compose exec web bin/rails test test/integration/walker_walks_test.rb`
- [ ] Full suite passes: `docker compose exec web bin/rails test`
- [ ] Lint passes: `docker compose exec web bundle exec rubocop`

#### Manual Verification:

- [ ] Temporarily remove the `state:` clause from `walker_walks_controller.rb`'s `start`/`complete` scoped finds (or otherwise weaken the guard) and re-run the two new tests — confirm both fail. Revert the temporary change. This proves the tests pin real behavior rather than passing vacuously.

---

## Phase 2: Model-level concurrency tests — start!/complete! races

### Overview

Add two race tests to `test/models/walk_concurrency_test.rb`, mirroring the
existing `accept!` race test, for symmetric coverage of `start!`/`complete!`
under real thread contention. Close out the rollout phase by updating
`context/foundation/test-plan.md` §6 with the shipped cookbook patterns.

### Changes Required:

#### 1. Concurrent `start!` race test

**File**: `test/models/walk_concurrency_test.rb`

**Intent**: Prove exactly one of several concurrent `start!` calls by the same
bound walker succeeds, symmetric with the existing `accept!` race test.

**Contract**: New `test` block in the existing `WalkConcurrencyTest` class
(reuses `setup`/`teardown`/`purge_fixtures`, no new fixtures). Sequentially
call `@walk.accept!(@walkers.first)` to reach `accepted` state (not part of
the race). Then, using the same `Concurrent::CyclicBarrier` +
per-thread-connection pattern as the existing test (`walk_concurrency_test.rb:36-49`),
spin `WALKER_COUNT` threads that all reload the walk and call
`walk.start!(@walkers.first)` — the *same* walker in every thread. Assert
exactly one `true` among the results; assert the walk ends `in_progress?`
with `started_at` set.

#### 2. Concurrent `complete!` race test

**File**: `test/models/walk_concurrency_test.rb`

**Intent**: Prove exactly one of several concurrent `complete!` calls by the
same bound walker succeeds.

**Contract**: Same shape as #1. Sequentially call `@walk.accept!(@walkers.first)`
then `@walk.start!(@walkers.first)` to reach `in_progress` (not part of the
race). Race `WALKER_COUNT` concurrent `complete!(@walkers.first)` calls;
assert exactly one `true`; assert the walk ends `completed?` with
`completed_at` set.

#### 3. Update the test-plan cookbook

**File**: `context/foundation/test-plan.md`

**Intent**: Replace the §6.2 placeholder with the actual model-test pattern
shipped, and add a §6.4 note documenting the race-test scope decision for
future readers.

**Contract**: §6.2 ("Adding a model test") currently reads "TBD — see §3 Phase 2
for the state machine false-return pattern." Replace with: the class-level
`self.use_transactional_tests = false` + `Concurrent::CyclicBarrier` +
per-thread-connection pattern from `walk_concurrency_test.rb`, and the
rule that a same-actor/wrong-state HTTP test belongs in an integration test
against the controller's scoped `find` (see §6.1), while a same-actor
*concurrent* race belongs in a model-level `WalkConcurrencyTest`-style test —
these are two different failure modes needing two different test layers, not
interchangeable. Add one line to §6.4 ("Per-rollout-phase notes"): the
`start!`/`complete!` race tests were a planning-time scope extension beyond
Risk #2 as sourced in §2 — added for symmetry with the existing `accept!`
race test, not because a new risk was scored.

### Success Criteria:

#### Automated Verification:

- [ ] Full test file passes: `docker compose exec web bin/rails test test/models/walk_concurrency_test.rb`
- [ ] Full suite passes: `docker compose exec web bin/rails test`
- [ ] Lint passes: `docker compose exec web bundle exec rubocop`
- [ ] Security scan passes: `docker compose exec web bundle exec brakeman --no-pager`

#### Manual Verification:

- [ ] Run `docker compose exec web bin/rails test test/models/walk_concurrency_test.rb` five times in a row to confirm the two new race tests are not flaky (real-thread tests can be nondeterministic; a single green run is not sufficient confidence).
- [ ] Read the updated `context/foundation/test-plan.md` §6.2/§6.4 to confirm the cookbook text is accurate and reads well in context.

---

## Testing Strategy

### Unit Tests:

- None — no production code changes; `test/models/walk_test.rb`'s existing illegal-transition tests already cover the model guard sequentially.

### Integration Tests:

- Phase 1's two new `walker_walks_test.rb` tests are the primary deliverable for Risk #2.

### Manual Testing Steps:

1. Phase 1: weaken the controller's state scoping temporarily, confirm the new tests fail, then revert.
2. Phase 2: run the concurrency test file 5x to check for flakiness.
3. Phase 2: re-read the updated test-plan.md §6 sections for accuracy.

## Performance Considerations

None — test-only change. The concurrency tests spin `WALKER_COUNT` (10)
threads each, consistent with the existing `accept!` race test's footprint;
no new load on CI beyond what that test already costs.

## Migration Notes

Not applicable — no schema or data changes.

## References

- Research: `context/changes/testing-state-machine-feedback/research.md`
- Existing pattern (integration 404): `test/integration/walker_walks_test.rb:63-67,76-81`
- Existing pattern (model concurrency): `test/models/walk_concurrency_test.rb:1-73`
- Existing pattern (same-actor/wrong-state, different mechanism): `test/integration/walks_cancel_test.rb:31-42`

## Progress

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles. See `references/progress-format.md`.

### Phase 1: HTTP integration tests — same-walker wrong-state 404

#### Automated

- [x] 1.1 Full test file passes: `docker compose exec web bin/rails test test/integration/walker_walks_test.rb` — a982068
- [x] 1.2 Full suite passes: `docker compose exec web bin/rails test` — a982068
- [x] 1.3 Lint passes: `docker compose exec web bundle exec rubocop` — a982068

#### Manual

- [x] 1.4 Weaken the state-scoped find, confirm both new tests fail, then revert — a982068

### Phase 2: Model-level concurrency tests — start!/complete! races

#### Automated

- [x] 2.1 Full test file passes: `docker compose exec web bin/rails test test/models/walk_concurrency_test.rb`
- [x] 2.2 Full suite passes: `docker compose exec web bin/rails test`
- [x] 2.3 Lint passes: `docker compose exec web bundle exec rubocop`
- [x] 2.4 Security scan passes: `docker compose exec web bundle exec brakeman --no-pager`

#### Manual

- [x] 2.5 Run the concurrency test file 5x to confirm no flakiness
- [x] 2.6 Re-read updated test-plan.md §6.2/§6.4 for accuracy
