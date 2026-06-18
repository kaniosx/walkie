<!-- IMPL-REVIEW-REPORT -->
# Implementation Review: S-05 Walker Accepts an Open Request (north star)

- **Plan**: context/changes/walker-accepts-request/plan.md
- **Scope**: All phases (1–2 of 2)
- **Date**: 2026-06-17
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

### F1 — Walk.postcode is nullable with no presence validation

- **Severity**: ℹ️ OBSERVATION
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Safety & Quality (Reliability)
- **Location**: app/models/walk.rb:21 (only city validated) + db/schema.rb (postcode nullable)
- **Detail**: `open_in_locality` matches on exact postcode, but Walk validates only city presence and the column is nullable. In practice every walk copies postcode from the owner's profile (User requires it), so open walks always carry one; a nil-postcode walk would simply never match the filter (safe-fail: hidden, never leaked). Latent edge only if a walk is created outside the owner-create path. Inherited from F-02's schema, not introduced by S-05.
- **Fix (optional)**: Add `validates :postcode, presence: true` to Walk (and/or a NOT NULL migration). Out of scope for S-05; note for a future hardening slice.
- **Decision**: FIXED — added `validates :postcode, presence: true` to Walk + postcode-presence test; updated walk_test/walk_concurrency_test fixtures to supply postcode (model-level; no migration)

### F2 — Test files use slightly different User.create! arg lists

- **Severity**: ℹ️ OBSERVATION
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Pattern Consistency
- **Location**: test/integration/open_requests_test.rb:5
- **Detail**: The integration test omits `password_confirmation` while walk_test.rb includes it. Both valid (has_secure_password doesn't require confirmation unless assigned). Cosmetic.
- **Fix**: None needed — both forms are correct.
- **Decision**: SKIPPED — both forms valid; purely cosmetic.
