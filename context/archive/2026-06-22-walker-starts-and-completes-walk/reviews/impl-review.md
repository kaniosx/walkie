<!-- IMPL-REVIEW-REPORT -->
# Implementation Review: Walker Starts + Completes a Walk

- **Plan**: `context/changes/walker-starts-and-completes-walk/plan.md`
- **Scope**: Full plan (Phase 1 + Phase 2 of 2)
- **Date**: 2026-06-22
- **Verdict**: NEEDS ATTENTION
- **Findings**: 0 critical, 2 warnings, 2 observations

## Verdicts

| Dimension            | Verdict |
|----------------------|---------|
| Plan Adherence       | PASS    |
| Scope Discipline     | WARNING |
| Safety & Quality     | PASS    |
| Architecture         | PASS    |
| Pattern Consistency  | WARNING |
| Success Criteria     | PASS    |

## Findings

### F1 — Missing unauthenticated access test

- **Severity**: ⚠️ WARNING
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Pattern Consistency
- **Location**: `test/integration/walker_walks_test.rb` (missing)
- **Detail**: `open_requests_test.rb` has an explicit unauthenticated-access test covering GET and POST (lines 82–88). `walker_walks_test.rb` has no equivalent. The `require_authentication` before_action in `ApplicationController` covers this at runtime, but a future regression (e.g., accidental `allow_unauthenticated_access`) would go undetected.
- **Fix**: Add one test block covering unauthenticated GET /walker_walks, POST start, and POST complete — all should redirect to `new_session_path`.
- **Decision**: FIXED — unauthenticated test block added to walker_walks_test.rb

### F2 — Missing complete foreign-walker 404 test

- **Severity**: ⚠️ WARNING
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Pattern Consistency / Safety & Quality
- **Location**: `test/integration/walker_walks_test.rb` (missing)
- **Detail**: Test 5 verifies that walker2 cannot `start` another walker's walk (→ 404). There is no symmetric test that walker2 cannot `complete` an in-progress walk belonging to walker. The `complete` action's scoped find has the same guard, but the coverage is asymmetric.
- **Fix**: Add one test: set `@walk` to in_progress, sign in as walker2, POST complete → assert_response :not_found.
- **Decision**: FIXED — walker cannot complete another walker's in_progress walk test added

### F3 — View renders dog.breed not in plan contract

- **Severity**: 👁️ OBSERVATION
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Scope Discipline
- **Location**: `app/views/walker_walks/index.html.erb:6`
- **Detail**: The plan contract specified dog name and humanized state. The implementation also renders `@walk.dog.breed`. The breed is already eagerly loaded (no N+1) and the content is harmless, but it is extra scope not in the plan.
- **Fix**: Accept as-is (breed display is reasonable for context) or remove it to stay strictly on contract.
- **Decision**: ACCEPTED — breed display is useful Walker context; kept as-is

### F4 — No DB uniqueness guard for one-active-walk-per-walker

- **Severity**: 👁️ OBSERVATION
- **Impact**: 🔎 MEDIUM — real tradeoff; pause to reason through it
- **Dimension**: Safety & Quality
- **Location**: `app/controllers/walker_walks_controller.rb:5`
- **Detail**: The index action uses `.first` on `Walk.where(accepted_by_walker_id: current_user.id, state: %w[accepted in_progress])`, silently discarding any second matching row. The single-active-walk invariant is enforced at accept time (a walk in `requested` state can only be accepted once, and a walker can't create new requests), but there is no DB-level partial unique index on `(accepted_by_walker_id) WHERE state IN ('accepted','in_progress')`. A data anomaly would silently show only one walk.
- **Fix A ⭐ Recommended**: Accept current behavior with a comment in the controller noting the single-active-walk invariant and where it's enforced (accept! + no-active-per-dog guard at creation). No code change — this is a defensive note, not a bug.
  - Strength: Zero code change; the invariant is already maintained by two other mechanisms.
  - Tradeoff: A data anomaly (from a test fixture or migration error) would be invisible to the Walker.
  - Confidence: HIGH — the invariant is real; the risk of a data anomaly is theoretical.
  - Blind spot: We haven't audited whether any existing migration could produce the anomaly.
- **Fix B**: Add a partial unique index `CREATE UNIQUE INDEX … ON walks (accepted_by_walker_id) WHERE state IN ('accepted', 'in_progress')` in a new migration.
  - Strength: Makes the invariant DB-binding, not just application-level.
  - Tradeoff: New migration; slight schema complexity.
  - Confidence: MED — requires verifying no existing data violates the constraint before adding.
  - Blind spot: Could conflict with future multi-walk-per-walker feature (though PRD explicitly defers this).
- **Decision**: FIXED via Fix A — comment added to walker_walks_controller.rb#index documenting the invariant and its enforcement points
