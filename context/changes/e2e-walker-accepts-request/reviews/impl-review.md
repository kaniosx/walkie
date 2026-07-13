<!-- IMPL-REVIEW-REPORT -->
# Implementation Review: Walker Accepts an Open Request — E2E System Test

- **Plan**: context/changes/e2e-walker-accepts-request/plan.md
- **Scope**: Full plan (Phase 1 + Phase 2)
- **Date**: 2026-07-13
- **Verdict**: APPROVED
- **Findings**: 0 critical, 0 warnings, 1 observation

## Verdicts

| Dimension | Verdict |
|-----------|---------|
| Plan Adherence | PASS |
| Scope Discipline | PASS |
| Safety & Quality | PASS |
| Architecture | PASS |
| Pattern Consistency | PASS |
| Success Criteria | PASS |

## Evidence

- Plan-drift sub-agent: all four planned changes (`test/support/system_sign_in_helper.rb`, `test/application_system_test_case.rb`, `test/system/owner_creates_walk_request_test.rb`, `test/system/walker_accepts_request_test.rb`) MATCH the plan's contracts exactly. No unplanned files in either commit (`8394e36`, `9036774`) beyond expected change-folder docs and the roadmap update. All "What We're NOT Doing" boundaries respected (no race-case coverage, no `walker_walks_path` assertions, single open-request fixture, no CI/Gemfile/Dockerfile changes).
- Safety/quality/pattern sub-agent: no brittle locators (role/label/text-based throughout), no hardcoded waits, no shared state between tests, no resource leaks. `SystemSignInHelper` correctly scoped to `ApplicationSystemTestCase` only (doesn't leak into integration/unit tests). Require path resolves unambiguously (no `app/support` or `lib/support` shadowing). Fixture style matches existing integration-test conventions exactly.
- Automated verification (re-run independently): `bin/rails test:system` — 3/3 green; `bundle exec rubocop` — clean on all 4 files; `git diff app/controllers/open_requests_controller.rb` — clean (no residual deliberate-break edit).
- Manual verification: all confirmed during implementation (Phase 1 misspell-and-revert check, Phase 2 deliberate-break check, 3x flakiness re-run) — see plan.md Progress section for SHAs.

## Findings

### F1 — Helper naming diverges from existing sign_in_as convention

- **Severity**: ℹ️ OBSERVATION
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Pattern Consistency
- **Location**: test/support/system_sign_in_helper.rb
- **Detail**: The new shared helper is named `sign_in_via_form`. Each integration test file (`open_requests_test.rb`, `walker_walks_test.rb`) already defines its own private `sign_in_as(email)` helper for the HTTP-bypass sign-in. The names diverge (`via_form` vs `as`), which is arguably correct — they're deliberately different mechanisms (real form vs. POST bypass) — but someone grepping for "sign_in" conventions will find two different naming schemes.
- **Fix**: No action needed. The divergent name is arguably a feature here (it signals "this drives the real form," distinct from the integration tests' shortcut) — noting only as observation.
- **Decision**: DISMISSED (no action needed, noted for awareness only)
