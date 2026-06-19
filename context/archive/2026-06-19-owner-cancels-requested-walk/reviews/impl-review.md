<!-- IMPL-REVIEW-REPORT -->
# Implementation Review: Owner Cancels a Requested Walk

- **Plan**: `context/changes/owner-cancels-requested-walk/plan.md`
- **Scope**: Full plan (Phase 1 + Phase 2 of 2)
- **Date**: 2026-06-19
- **Verdict**: APPROVED
- **Findings**: 0 critical, 1 warning, 2 observations

## Verdicts

| Dimension            | Verdict |
|----------------------|---------|
| Plan Adherence       | PASS    |
| Scope Discipline     | PASS    |
| Safety & Quality     | PASS    |
| Architecture         | PASS    |
| Pattern Consistency  | WARNING |
| Success Criteria     | PASS    |

## Findings

### F1 — Controller authz scope pattern inconsistent with accept! sibling

- **Severity**: ⚠️ WARNING
- **Impact**: 🔎 MEDIUM — real tradeoff; pause to reason through it
- **Dimension**: Pattern Consistency
- **Location**: `app/controllers/walks_controller.rb:9` vs `app/controllers/open_requests_controller.rb:11`
- **Detail**: `WalksController#cancel` scopes the lookup to `current_user.owned_walks.find(params[:id])` — authorization at the controller level. `OpenRequestsController#accept` does an unscoped `Walk.find(params[:id])` and delegates entirely to the model guard inside `accept!`. Both work correctly, but a future contributor may follow the unscoped pattern for a new owner action and inadvertently omit a controller-level guard, trusting only the model method — an invisible inconsistency that breaks under a future model refactor.
- **Fix A ⭐ Recommended**: Add a one-line comment in `WalksController#cancel` (above the `find`) explaining that the scope provides defense-in-depth on top of the model-layer guard, and that the divergence from `open_requests_controller.rb` is intentional (scoped = safer default for owner actions).
  - Strength: Preserves both patterns as documented choices rather than accidental divergence; zero behavior change.
  - Tradeoff: A comment isn't enforced — a future contributor can still miss it.
  - Confidence: HIGH — The two guard layers are genuinely different safety concerns (scope = ownership, model guard = state + ownership); explaining both is correct.
  - Blind spot: Doesn't prevent the pattern from spreading inconsistently to future controllers.
- **Fix B**: Apply the scoped-lookup pattern to `OpenRequestsController#accept` as well (scope to `Walk.where(state: :requested).find(params[:id])` before calling `accept!`).
  - Strength: Single consistent pattern project-wide; easier to audit.
  - Tradeoff: The `accept!` model method already handles wrong-state via `swap_state` returning false; adding a scope makes the controller pre-reject rather than model-reject, changing the error surface slightly.
  - Confidence: MEDIUM — The model guard in `accept!` is thorough; adding a controller scope is redundant but harmless.
  - Blind spot: `open_requests_controller.rb` belongs to the already-archived S-05 slice; touching it may be out of scope here.
- **Decision**: FIXED via Fix A — comment added to walks_controller.rb#cancel

### F2 — "Already accepted" alert misleading for in_progress / completed / cancelled states

- **Severity**: 👁️ OBSERVATION
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Safety & Quality
- **Location**: `app/controllers/walks_controller.rb:14`
- **Detail**: `cancel!` returns false for *any* non-REQUESTED state (via `swap_state`'s WHERE clause). The controller shows "This request was already accepted by a walker." for all false returns. For `accepted` this is accurate; for `in_progress`, `completed`, or `cancelled` it is misleading. A crafted POST to cancel a completed walk shows the wrong message. The walk's state is never changed, so there is no data-safety risk — only a UX inaccuracy reachable only by bypassing the UI (the cancel button is only rendered for `requested?` walks).
- **Fix**: Change the alert to `"This walk can no longer be cancelled."` — accurate for all non-requestable states.
- **Decision**: FIXED — alert changed to "This walk can no longer be cancelled." in walks_controller.rb and walks_cancel_test.rb

### F3 — RecordNotFound → 404 mapping relies on implicit Rails behavior

- **Severity**: 👁️ OBSERVATION
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Safety & Quality
- **Location**: `app/controllers/walks_controller.rb:9` / `test/integration/walks_cancel_test.rb:44`
- **Detail**: `current_user.owned_walks.find(params[:id])` raises `ActiveRecord::RecordNotFound` for a cross-owner access attempt. The integration test asserts `assert_response :not_found` (404). This assertion is only reliable if the test environment maps `RecordNotFound` to 404 — which is Rails' default in production mode but may not be active in development/test mode depending on `config.action_dispatch.show_exceptions`. The same gap exists in the existing `walks_test.rb` cross-owner dog test (line 73). No test failure was observed, so the mapping is active — but it is implicit.
- **Fix**: Confirm `config/environments/test.rb` has `config.action_dispatch.show_exceptions = :rescuable` (Rails 7.1+) or the equivalent, or add `rescue_from ActiveRecord::RecordNotFound, with: :record_not_found` to `ApplicationController` with a `render status: :not_found` body — making the behavior explicit and environment-independent.
- **Decision**: FIXED — rescue_from ActiveRecord::RecordNotFound added to ApplicationController with not_found handler
