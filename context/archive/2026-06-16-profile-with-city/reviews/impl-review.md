<!-- IMPL-REVIEW-REPORT -->
# Implementation Review: S-02 User Profile with City/Postcode

- **Plan**: context/changes/profile-with-city/plan.md
- **Scope**: All phases (1–2 of 2)
- **Date**: 2026-06-16
- **Verdict**: APPROVED
- **Findings**: 0 critical, 0 warnings, 3 observations

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

### F1 — Profile edit test covers blank city but not blank postcode

- **Severity**: ℹ️ OBSERVATION
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Success Criteria
- **Location**: test/integration/profiles_test.rb:46
- **Detail**: The plan's manual criterion says "blank city OR postcode" is rejected; the integration test exercises only blank city. Both flow through the same presence validation, so risk is low — a blank-postcode case would make coverage match the stated contract symmetrically.
- **Fix**: Add a sibling test asserting a blank postcode → 422 and the record unchanged.
- **Decision**: FIXED — added blank-postcode integration test (profiles_test.rb), 6 runs green

### F2 — Migration backfill references the application User model

- **Severity**: ℹ️ OBSERVATION
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Safety & Quality (Migration)
- **Location**: db/migrate/20260616061738_add_profile_fields_to_users.rb:12
- **Detail**: Backfill uses `User.where(...).update_all(...)`. `update_all` skips validations/callbacks and `reset_column_information` is correctly ordered. Residual concern is the textbook foot-gun of referencing the app model in a migration. Immaterial here — zero real users, migration already applied.
- **Fix (optional)**: Use `execute "UPDATE users SET ..."` to decouple from the model. Not worth rewriting an applied migration.
- **Decision**: SKIPPED — migration already applied; rewriting gains nothing and risks divergence

### F3 — Duplicated sign-in helper across integration tests

- **Severity**: ℹ️ OBSERVATION
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Pattern Consistency
- **Location**: test/integration/profiles_test.rb:14
- **Detail**: profiles_test defines a local `sign_in` helper; sessions/navigation tests inline the same `post session_path`. No shared helper exists in test_helper.rb. Reasonable improvement, but the sign-in pattern is now duplicated across files.
- **Fix (optional)**: Extract a shared sign-in helper into test_helper.rb in a later cleanup. Out of scope for this change.
- **Decision**: SKIPPED — cross-suite test refactor is its own change; out of scope for S-02
