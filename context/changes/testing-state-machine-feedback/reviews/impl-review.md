<!-- IMPL-REVIEW-REPORT -->
# Implementation Review: State Machine Feedback

- **Plan**: context/changes/testing-state-machine-feedback/plan.md
- **Scope**: Full plan (Phase 1 of 2, Phase 2 of 2)
- **Date**: 2026-07-08
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

## Evidence

- **Plan Adherence**: both review sub-agents independently confirmed all 5 planned changes (2 integration tests in `test/integration/walker_walks_test.rb`, 2 concurrency tests in `test/models/walk_concurrency_test.rb`, the §6.2/§6.4 cookbook update in `context/foundation/test-plan.md`) MATCH the plan's intent exactly.
- **Scope Discipline**: no production code touched (`app/controllers/walker_walks_controller.rb`, `app/models/walk.rb` untouched); none of the plan's excluded scenarios (start-after-complete, double-complete, new sequential model tests, HTTP-level concurrency, test-plan.md §1/§2/§3 edits) were added.
- **Safety & Quality**: no vacuous assertions — both new integration tests genuinely set up the wrong state before asserting 404; both new concurrency tests have correct barrier/thread counts (`WALKER_COUNT` parties = `WALKER_COUNT` threads) and sequential setup happens strictly before the barrier, so the race genuinely contends.
- **Success Criteria**: independently re-ran all 4 automated checks post-implementation — `bin/rails test` (108 runs, 0 failures), `bundle exec rubocop` (65 files, 0 offenses), `bundle exec brakeman --no-pager` (0 warnings). All 3 manual Progress checks have real evidence in the implementation conversation (mutation-test failure output for 1.4, 5x flakiness run for 2.5, cookbook re-read for 2.6) — not rubber-stamped.

## Findings

### F1 — config/database.yml uses a non-standard pool key

- **Severity**: ⚪ OBSERVATION
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Safety & Quality
- **Location**: config/database.yml:20
- **Detail**: `max_connections:` isn't a real ActiveRecord connection-pool key (it's `pool:`), so the effective pool size silently falls back to the AR default instead of being sized for the 10-thread concurrency tests. Pre-existing — equally affects the existing `accept!` race test, not introduced or worsened by this change.
- **Fix**: Rename `max_connections:` to `pool:` in config/database.yml if/when someone touches that file next — not part of this change's scope.
- **Decision**: FIXED — commit ac1dd9c

### F2 — "call" vs. "walker" naming in new race test titles

- **Severity**: ⚪ OBSERVATION
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Pattern Consistency
- **Location**: test/models/walk_concurrency_test.rb:61,90
- **Detail**: New tests say "exactly one call wins..." vs. the existing "exactly one walker wins...". Intentional, not drift — the new tests race one walker against their own concurrent requests, not N walkers against each other, so "call" is the more accurate noun. Justified by the tests' own comments and by test-plan.md §6.4.
- **Fix**: No action needed — naming is intentional and accurate.
- **Decision**: SKIPPED
