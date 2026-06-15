<!-- IMPL-REVIEW-REPORT -->
# Implementation Review: F-01 Rails 8 Auth + Role-Typed Accounts

- **Plan**: context/changes/auth-and-role-typing/plan.md
- **Scope**: All 4 phases (full plan)
- **Date**: 2026-06-01
- **Verdict**: APPROVED
- **Findings**: 0 critical, 1 warning, 2 observations

## Verdicts

| Dimension | Verdict |
|-----------|---------|
| Plan Adherence | PASS |
| Scope Discipline | PASS |
| Safety & Quality | PASS |
| Architecture | PASS |
| Pattern Consistency | WARNING |
| Success Criteria | PASS |

Success criteria independently re-run on 2026-06-01: full suite 13 runs/54 assertions/0 failures; rubocop 40 files no offenses; brakeman 0 warnings (1 justified ignore); bundler-audit no vulnerabilities.

## Findings

### F1 — Registration#create has no rate limit (siblings do)

- **Severity**: ⚠️ WARNING
- **Impact**: 🔎 MEDIUM — real tradeoff; pause to reason through it
- **Dimension**: Pattern Consistency
- **Location**: app/controllers/registrations_controller.rb:1-3
- **Detail**: Generated SessionsController#create and PasswordsController#create both carry `rate_limit`. The hand-written RegistrationsController#create has none — an asymmetry with its siblings and an open signup-spam vector. Not plan drift (the plan didn't specify it), but a deliberate triage call.
- **Fix A ⭐ Recommended**: Add a matching `rate_limit to: 10, within: 3.minutes, only: :create`.
  - Strength: Restores parity with generated controllers; same idiom already in repo.
  - Tradeoff: Throttled legitimate retry returns 429 — acceptable for signup.
  - Confidence: HIGH — identical pattern exists in this repo.
  - Blind spot: Exact threshold is a product call.
- **Fix B**: Accept as risk for the MVP and record the decision.
  - Strength: No code change; defensible pre-launch.
  - Tradeoff: Leaves the asymmetry; easy to forget at launch.
  - Confidence: MED.
  - Blind spot: None significant.
- **Decision**: FIXED via Fix A (rate_limit added at registrations_controller.rb:3, matching SessionsController idiom)

### F2 — change.md describes integer enum; code is string enum

- **Severity**: 📝 OBSERVATION
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Plan Adherence (documentation)
- **Location**: context/changes/auth-and-role-typing/change.md:14
- **Detail**: change.md says `enum role: { owner: 0, walker: 1 }` (integer). Implementation (user.rb:7) and column (schema.rb:30, `t.string "role"`) are string-backed, matching plan.md's authoritative contract. Code followed the right source; the change.md note is stale.
- **Fix**: Update change.md:14 to the string-backed enum to match the build.
- **Decision**: FIXED (change.md:14 updated to string-backed enum)

### F3 — Role immutability is enforced at the validation layer only

- **Severity**: 📝 OBSERVATION
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Safety & Quality
- **Location**: app/models/user.rb:12,16-18
- **Detail**: `role_is_immutable` (`on: :update`) is correct and tested, but guards only the validation layer — `update_column`/`update_attribute`/raw SQL bypass it. This is the approach the plan chose and is fine for an MVP with no role-edit path; flagged so single-layer enforcement is a conscious accepted state.
- **Fix**: Accept as-is for the MVP; revisit if an admin role-edit path appears.
- **Decision**: ACCEPTED (single-layer enforcement accepted for MVP; no role-edit path exists)

### Note (not a finding)

config/brakeman.ignore is an unplanned file but cleanly implements Phase 4's "security scan clean" criterion (suppresses the expected Mass-Assignment warning on the `role` permit, well-documented). Extra test coverage strengthens the suite. Both within the spirit of the plan — Scope Discipline PASS.
