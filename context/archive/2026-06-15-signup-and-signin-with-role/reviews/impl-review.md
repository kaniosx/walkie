<!-- IMPL-REVIEW-REPORT -->
# Implementation Review: S-01 Sign-up + Sign-in with Role Choice

- **Plan**: context/changes/signup-and-signin-with-role/plan.md
- **Scope**: All phases (1–3 of 3)
- **Date**: 2026-06-15
- **Verdict**: APPROVED
- **Findings**: 0 critical, 1 warning, 2 observations

## Verdicts

| Dimension | Verdict |
|-----------|---------|
| Plan Adherence | PASS |
| Scope Discipline | PASS |
| Safety & Quality | WARNING |
| Architecture | PASS |
| Pattern Consistency | PASS |
| Success Criteria | PASS |

## Findings

### F1 — Form text inputs rely on placeholders, no labels

- **Severity**: ⚠️ WARNING
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Safety & Quality (Accessibility)
- **Location**: sessions/new.html.erb:5-6, registrations/new.html.erb:14-16, passwords/new.html.erb:9
- **Detail**: Email/password inputs use `placeholder` but have no `<label>` or `aria-label`. Placeholders vanish on input and are inconsistently announced by screen readers. The role radio group is correctly labelled; only the text inputs are affected.
- **Fix**: Add `form.label :email_address` / `form.label :password` before each field, or `aria-label` at minimum.
- **Decision**: FIXED — added `form.label` to all text inputs in sessions/new, registrations/new, passwords/new

### F2 — Password-reset page renders a live form that does nothing

- **Severity**: ℹ️ OBSERVATION
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Scope Discipline
- **Location**: passwords/new.html.erb:3-11
- **Detail**: The page tells the user reset-by-email is unavailable in v1, yet still renders the "Email reset instructions" form (inert delivery from F-01). Submitting it appears to succeed but sends nothing. This was a deliberate plan decision (keep link + notice, form left in place).
- **Fix (optional)**: Hide the form body and keep only the notice + the "create a new account" link.
- **Decision**: FIXED — removed the inert form; page now shows the v1 notice + "create a new account" + "Back to sign in" links

### F3 — Test uses regex-coerced string matching vs suite's route-style

- **Severity**: ℹ️ OBSERVATION
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Pattern Consistency
- **Location**: test/integration/navigation_test.rb:16,22,28
- **Detail**: `assert_match`/`assert_no_match "Sign out", response.body` work correctly (string coerced to /Sign out/, no metacharacters), but the existing integration suite asserts on routes/status, not body content. For literal-substring checks, `assert_includes`/`assert_not_includes` is more robust (no regex coercion) and reads clearer.
- **Fix**: Swap to `assert_includes`/`assert_not_includes` for the literal "Sign out" / flash-message checks.
- **Decision**: FIXED — swapped all 3 assertions to assert_includes/assert_not_includes
