---
date: 2026-07-07T15:07:32+02:00
researcher: Claude
git_commit: 5efd398ef9299357c80b639973a67689b968edbd
branch: main
repository: walkie
topic: "Rollout Phase 2 — State machine feedback (Risk #2: HTTP response for out-of-sequence walk-state transitions)"
tags: [research, codebase, walker-walks-controller, walk-model, state-machine, integration-tests]
status: complete
last_updated: 2026-07-07
last_updated_by: Claude
---

# Research: Rollout Phase 2 — State machine feedback (Risk #2)

**Date**: 2026-07-07T15:07:32+02:00
**Researcher**: Claude
**Git Commit**: 5efd398ef9299357c80b639973a67689b968edbd
**Branch**: main
**Repository**: walkie

## Research Question

Ground rollout Phase 2 of `context/foundation/test-plan.md` (Risk #2: "A Walker attempts a state transition for which the walk is not in the required state, and the controller returns a misleading or silent HTTP response — user cannot tell the action failed"). Verify or correct the response guidance ("false-return means flash" is suspect — Phase 1 flagged it as race-only), locate existing tests, identify the cheapest useful test layer, and flag speculative risk or misleading hot-spot evidence.

## Summary

**The risk is real but the mechanism is not what a naive reading of the controller code suggests, and Phase 1's research already correctly diagnosed it.** `WalkerWalksController#start`/`#complete` scope their lookup by both owner *and* required state (`app/controllers/walker_walks_controller.rb:24,35`). This means:

- **The sequential wrong-state path (the one a real user can actually trigger) never reaches the `if/else` flash branch.** It raises `ActiveRecord::RecordNotFound` on the scoped `.find`, which `ApplicationController` rescues to a plain **404** (`app/controllers/application_controller.rb:4,13-15`) — the same status code and same rescue path used for the already-tested cross-account IDOR case.
- **The `else` flash branch ("This walk can no longer be updated.") is race-only** — reachable only if another request changes the walk's state between the controller's `.find` and the model's `swap_state` compare-and-swap. It is not reachable by a legitimate walker acting sequentially on their own walk.

**This is a genuinely distinct, currently uncovered scenario — not already proven by Phase 1.** Phase 1's 404 tests (`test/integration/walker_walks_test.rb:63-67`, `:76-81`) use **@walker2**, a different account, to prove the *authorization* dimension of the scope (`accepted_by_walker_id: current_user.id`). No existing test exercises the *state* dimension of the same scope (`state: :accepted` / `state: :in_progress`) with the correct, owning walker. The model-level tests (`test/models/walk_test.rb:43-46,48-52`) prove the state machine itself rejects illegal transitions, but they call `.start!`/`.complete!` directly on the AR object, bypassing the controller entirely — they say nothing about what HTTP response a real request produces.

**Conclusion for the risk response guidance**: the "must challenge" framing in test-plan.md §2 (Risk #2 row, and the Risk Response Guidance table) is confirmed correct as written — do not amend it. The likely-cheapest-layer recommendation (integration test asserting 404) is also confirmed. The one precedent that looks similar but does **not** transfer is `test/integration/walks_cancel_test.rb:31-42` ("owner cancels an already-accepted walk") — that passes through `WalksController#cancel`, which uses an **unscoped-by-state** find (`current_user.owned_walks.find(params[:id])`), so it legitimately reaches the graceful alert branch. `start`/`complete`'s state-scoped find means the analogous same-actor test for *those* actions gets 404, not an alert — a different assertion shape than the cancel precedent might suggest at a glance.

## Detailed Findings

### `WalkerWalksController#start` / `#complete` (the controller under test)

`app/controllers/walker_walks_controller.rb:21-42`:

```ruby
def start
  walk = Walk.where(accepted_by_walker_id: current_user.id, state: :accepted).find(params[:id])

  if walk.start!(current_user)
    redirect_to walker_walks_path, notice: "Walk started — you're on your way!"
  else
    redirect_to walker_walks_path, alert: "This walk can no longer be updated."
  end
end

def complete
  walk = Walk.where(accepted_by_walker_id: current_user.id, state: :in_progress).find(params[:id])

  if walk.complete!(current_user)
    redirect_to open_requests_path, notice: "Walk completed. Well done!"
  else
    redirect_to walker_walks_path, alert: "This walk can no longer be updated."
  end
end
```

Two layered guards:

1. **`.where(accepted_by_walker_id: ..., state: ...).find(id)`** (lines 24, 35) — a scoped `find`. If no row matches *both* the owner condition and the state condition, `find` raises `ActiveRecord::RecordNotFound`. This is a single DB query; there is no read-then-decide branch here — a wrong-state OR wrong-owner walk simply isn't found.
2. **`if walk.start!(current_user) / else`** (lines 26-30, 37-41) — only reached if step 1 succeeded (owner and state both matched at query time). It calls into the model's atomic compare-and-swap (`swap_state`); the `else` fires only if that swap loses a race that occurred strictly between step 1's query and this call.

### `Walk` model — transition methods and the compare-and-swap

`app/models/walk.rb:47-74` (`accept!`, `start!`, `complete!`, `cancel!`) all delegate to a private `swap_state`:

`app/models/walk.rb:77-84`:

```ruby
def swap_state(from:, to:, guard:, set:)
  attrs = set.merge(state: to, updated_at: Time.current)
  affected = self.class.where(id: id, state: from, **guard).update_all(attrs)
  return false unless affected == 1

  reload
  true
end
```

This is a single atomic `UPDATE ... WHERE id = ? AND state = ? AND <guard>`. It returns `false` — never raises — when the row didn't match at update time. This is the model-level guard that `test/models/walk_test.rb:43-46` ("start! before accept! returns falsy") and `:48-52` ("complete! before start! is rejected") already exercise directly, bypassing the controller.

DB-level backstop: `db/schema.rb:67-68` has two check constraints (`walks_state_valid`, `walks_walker_presence`) restricting the state column to the 5 known values and enforcing `accepted_by_walker_id` nullability in lockstep with state. No optimistic-locking column exists; atomicity for concurrent transitions comes entirely from the `update_all` compare-and-swap, not a DB lock.

### `ApplicationController` — how `RecordNotFound` becomes a 404

`app/controllers/application_controller.rb:4,13-15`:

```ruby
rescue_from ActiveRecord::RecordNotFound, with: :not_found
# ...
def not_found
  render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
end
```

This is the exact path both the IDOR case (Phase 1, already tested) and the same-walker wrong-state case (Phase 2, ungrounded) resolve to. They are the same HTTP status via the same rescue, for two semantically different reasons: wrong actor vs. wrong state on the walk. Both need their own test because the scoped `.where` clause has two independent conditions (`accepted_by_walker_id` and `state`), and existing tests only ever vary one of them (the actor).

### Routes

`config/routes.rb:6-17`:

```ruby
resources :walks, only: %i[ index create ] do
  member { post :cancel }
end
resources :open_requests, only: %i[ index ] do
  member { post :accept }
end
resources :walker_walks, only: %i[ index ] do
  member do
    post :start
    post :complete
  end
end
```

Relevant paths for Phase 2: `POST /walker_walks/:id/start` (`start_walker_walk_path`), `POST /walker_walks/:id/complete` (`complete_walker_walk_path`).

### `test/models/walk_concurrency_test.rb` — the only existing race test, and it doesn't cover this risk

`test/models/walk_concurrency_test.rb:3-53` proves exactly one thread wins a simultaneous `accept!` race (REQUESTED→ACCEPTED) via `Concurrent::CyclicBarrier` across 10 threads. It does not touch `start!`/`complete!`, and it operates at the model layer only (never through the controller). It is **not** a substitute for either the sequential-404 test Phase 2 needs, or for a hypothetical race test on `start!`/`complete!`'s `else` branch (which nothing currently exercises, and which test-plan.md's guidance explicitly tells Phase 2 to avoid building a sequential test for).

### Existing integration test coverage — full audit

`test/integration/walker_walks_test.rb` (12 tests) — relevant rows:

| Test (lines) | Actor vs. walk owner | Walk state at call time | Result |
|---|---|---|---|
| `walker starts accepted walk...` (38-48) | same walker | `accepted` (correct) | success |
| `walker completes in_progress walk...` (50-61) | same walker | `in_progress` (correct) | success |
| `walker cannot start another walker's accepted walk: responds 404` (63-67) | **different** walker (@walker2) | `accepted` (correct state, wrong actor) | 404 |
| `walker cannot complete another walker's in_progress walk: responds 404` (76-81) | **different** walker (@walker2) | `in_progress` (correct state, wrong actor) | 404 |

No test has the *same* walker call `start`/`complete` while the walk is in the *wrong* state. The two 404 tests above vary only the actor, never the state, for a matching actor.

`test/models/walk_test.rb` (model-level, bypasses controller):

- `start! before accept! returns falsy and leaves state unchanged` (43-46)
- `complete! before start! is rejected` (48-52)

These prove the model guard, not the HTTP response.

`test/integration/walks_cancel_test.rb:31-42` — the one existing same-actor/wrong-state **integration** test, but for a different controller/action:

```ruby
test "owner cancels an already-accepted walk: redirects with alert, walk remains accepted" do
  @walk.accept!(@walker)
  post cancel_walk_path(@walk), as: :turbo_stream # (headers per test setup)
  assert_redirected_to walks_path
  assert_equal "This walk can no longer be cancelled.", flash[:alert]
  @walk.reload
  assert @walk.accepted?
end
```

This works because `WalksController#cancel` looks up via `current_user.owned_walks.find(params[:id])` — **not** scoped by state — so a wrong-state walk is found, `cancel!` returns `false`, and the controller's else-branch alert fires. This is a legitimately different code shape from `start`/`complete`'s state-scoped find, so this test is not a template to copy verbatim; it is evidence that the pattern "same actor, wrong state" is a real category the team already tests elsewhere, just via a different mechanism (alert, not 404) because of a different controller design.

## Code References

- `app/controllers/walker_walks_controller.rb:21-42` — `start`/`complete` actions, the state-scoped find + swap-state guard
- `app/models/walk.rb:47-74` — `accept!`/`start!`/`complete!`/`cancel!`
- `app/models/walk.rb:77-84` — `swap_state` (atomic compare-and-swap, returns `false`, never raises)
- `app/controllers/application_controller.rb:4,13-15` — `rescue_from ActiveRecord::RecordNotFound, with: :not_found`
- `config/routes.rb:6-17` — routes for walks/open_requests/walker_walks member actions
- `test/integration/walker_walks_test.rb:63-67,76-81` — existing cross-account IDOR 404 tests (wrong actor, not wrong state)
- `test/models/walk_test.rb:43-46,48-52` — model-level illegal-transition guards (bypass controller)
- `test/integration/walks_cancel_test.rb:31-42` — same-actor/wrong-state precedent, different controller shape (unscoped find → alert, not 404)
- `test/models/walk_concurrency_test.rb:3-53` — only existing race test, covers `accept!` cross-walker race only

## Architecture Insights

- **Two independent dimensions are folded into one `.where(...).find(...)` scope** (`accepted_by_walker_id` and `state`). Existing tests vary only the first dimension. A test suite that only varies actor and never state will always look complete (same 404 assertion pattern) while leaving a real gap.
- **The `if/else` flash branch on `start!`/`complete!` is dead code from a sequential-request perspective.** It only fires under a genuine race (two concurrent requests hitting the compare-and-swap on either side of the controller's initial scoped find). Writing a sequential integration test that expects to hit this branch would be a false test — it can never fail for the right reason under normal `bin/rails test` execution, because Minitest's fixture/transaction model and the app's own scoped find make the branch unreachable outside real thread contention.
- **A precedent for the same-actor/wrong-state *shape* of test already exists** (`walks_cancel_test.rb:31-42`), but its assertion (alert, walk unchanged) does not transfer to `start`/`complete` because those controllers use a state-scoped find where `cancel` does not. The Phase 2 tests need their own assertion shape: `assert_response :not_found`, matching the existing IDOR-404 test pattern in `walker_walks_test.rb`, not the cancel pattern.

## Historical Context (from prior changes)

- `context/changes/testing-http-guardrails/research.md:411-418` (Phase 1, complete) explicitly deferred this exact question to Phase 2, and already concluded: *"The controller for start/complete has no sequential illegal-transition path reachable by a legitimate user (the scoped find would 404 first)."* This research confirms that conclusion against the current code and closes the open question — Phase 1's diagnosis was correct and remains accurate.
- `context/changes/testing-http-guardrails/research.md:372-378` (Architecture Insights) already flagged the else-branch as race-only. Confirmed.
- `context/changes/testing-http-guardrails/plan.md:53-55,63` explicitly scoped this out of Phase 1 ("Not addressing Phase 2... state machine feedback").
- `context/archive/2026-06-22-walker-starts-and-completes-walk/plan.md:78-79,90-93,129-137` — the original slice that built `start`/`complete` never tested the same-actor/wrong-state path; its manual-verification notes describe the `else` branch as if reachable sequentially, which Phase 1's later research corrected. No `research.md` exists in that archived slice.
- `context/foundation/roadmap.md` S-04–S-09 — no slice ties an explicit test requirement to out-of-sequence-transition HTTP behavior; S-06 (`roadmap.md:191-201`) raises a related but distinct concern (accept/cancel race, "second action receives 'already moved'"), not this risk.
- `context/foundation/prd.md` §Guardrails (`prd.md:40-43`) and §NFR (`prd.md:144`) — verbatim: *"There is no externally observable path that lets a walk skip, repeat, or reverse states."* US-03 (`prd.md:71-80`) acceptance criteria: *"Any attempt to skip, reverse, or re-enter a prior state is rejected beyond the UI layer."* A 404 response satisfies this NFR's letter (nothing is observably skipped/reversed — the resource simply "doesn't exist" for that action) provided it is actually asserted by a test; today it is not.

## Related Research

- `context/changes/testing-http-guardrails/research.md` — Phase 1 research (complete), covers Risks #1, #3, #4
- `context/archive/2026-06-22-walker-starts-and-completes-walk/plan.md` — original implementation plan for `start`/`complete`

## Open Questions

1. **Scope of Phase 2's test set.** The state-scoped find produces 404 for at least these same-walker wrong-state combinations on `start`/`complete`: (a) walk still `accepted` when `complete` is called (complete-before-start), (b) walk already `in_progress` when `start` is called again (double-start), (c) walk already `completed` when either is called. All resolve through the identical code path (`RecordNotFound` → 404), so they carry diminishing marginal signal past the first one or two. Recommend `/10x-plan` pick the 1-2 combinations that most directly map to the PRD's "skip, repeat, or reverse states" wording (complete-before-start = skip; double-start = repeat) rather than exhaustively enumerating all reachable combinations.
2. **Whether to add a race test for the `else` flash branch on `start!`/`complete!`.** This would mirror `walk_concurrency_test.rb`'s pattern (real threads, `Concurrent::CyclicBarrier`) but for `start!`/`complete!` instead of `accept!`. Test-plan.md's guidance explicitly says to avoid a *sequential* test assuming this branch is reachable, but is silent on whether a genuine concurrency test is in scope for Phase 2 or is a separate future risk. This research did not find that scenario named in any risk row (#1–#5) — it resembles Risk #1's already-solved pattern (`accept!`) applied to two more methods, not a new failure mode the product's risk map calls out. Recommend `/10x-plan` treat this as explicitly out of scope for Phase 2 unless the user surfaces it as a new concern; do not silently add it.
