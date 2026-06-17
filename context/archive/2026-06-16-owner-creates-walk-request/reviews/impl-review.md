<!-- IMPL-REVIEW-REPORT -->
# Implementation Review: S-04 Owner Creates a Walk Request

- **Plan**: context/changes/owner-creates-walk-request/plan.md
- **Scope**: All phases (1–2 of 2)
- **Date**: 2026-06-16
- **Verdict**: APPROVED
- **Findings**: 0 critical, 0 warnings, 2 observations

## Verdicts

| Dimension | Verdict |
|-----------|---------|
| Plan Adherence | PASS |
| Scope Discipline | PASS |
| Safety & Quality | PASS |
| Architecture | PASS |
| Pattern Consistency | PASS |
| Success Criteria | PASS |

## Findings

### F1 — N+1 on walk.dog in the walks index

- **Severity**: ℹ️ OBSERVATION
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Safety & Quality (Performance)
- **Location**: app/controllers/walks_controller.rb:5 + app/views/walks/index.html.erb:8
- **Detail**: index renders `walk.dog.name` per row over `current_user.owned_walks` without `includes(:dog)` — a textbook N+1 (1 query + 1 per row). Negligible at v1 scale (a single owner's own requests), but the fix is trivial and pre-empts growth.
- **Fix**: Add `.includes(:dog)` to `current_user.owned_walks` in `WalksController#index`.
- **Decision**: FIXED — added `.includes(:dog)` to WalksController#index; walks tests green

### F2 — Dupe-guard is not race-safe / not DB-enforced

- **Severity**: ℹ️ OBSERVATION
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Safety & Quality (Reliability)
- **Location**: app/models/walk.rb:83 (no_active_walk_for_dog)
- **Detail**: The one-active-request-per-dog guard is a create-time `exists?` check; two concurrent POSTs for the same dog could both pass and create two active walks. Deliberate plan decision (documented in the model comment); NOT the PRD Singleness invariant (one walker per walk, DB-enforced in F-02). Flagged for the record.
- **Fix**: None — accepted by design. A partial unique index would be the DB-level option if it ever matters.
- **Decision**: SKIPPED — accepted by design (documented in plan + model comment); not the PRD Singleness invariant.
