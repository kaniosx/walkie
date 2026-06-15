<!-- IMPL-REVIEW-REPORT -->
# Implementation Review: F-03 Test Infrastructure Scaffold

- **Plan**: context/changes/test-infrastructure-scaffold/plan.md
- **Scope**: All 3 phases (complete)
- **Date**: 2026-06-03
- **Verdict**: APPROVED (1 minor warning)
- **Findings**: 0 critical, 1 warning, 2 observations
- **Triage**: F1 fixed via Fix A (follow-up queued); F2 queued for F-02; F3 recorded as lesson (code already conformant)

## Verdicts

| Dimension | Verdict |
|-----------|---------|
| Plan Adherence | PASS |
| Scope Discipline | PASS |
| Safety & Quality | PASS |
| Architecture | PASS |
| Pattern Consistency | PASS |
| Success Criteria | WARNING |

## Findings

### F1 — Criterion 2.1 marked complete but `bin/ci` exits non-zero

- **Severity**: ⚠️ WARNING
- **Impact**: 🔎 MEDIUM — real tradeoff; pause to reason through it
- **Dimension**: Success Criteria
- **Location**: context/changes/test-infrastructure-scaffold/plan.md (row 2.1)
- **Detail**: Progress row 2.1 ("Local CI pipeline passes end-to-end including tests: bin/ci") is `[x]`. Re-verified: `bin/ci` exits 1. The only failing step is the pre-existing `Security: Importmap vulnerability audit` (importmap-rails never installed — no config/importmap.rb / bin/importmap, exit 127). The F-03 Tests step passes. The checkbox's literal claim overstates, though accurate for the F-03-owned portion; documented in p2 commit + PR.
- **Fix A ⭐ Recommended**: Keep marked; capture importmap gap as a separate follow-up change.
  - Strength: F-03 deliverable works locally and is remote-verified green; blocker is pre-existing and explicitly out of scope.
  - Tradeoff: 2.1 checkbox stays slightly optimistic until importmap fixed elsewhere.
  - Confidence: HIGH — root cause confirmed (exit 127, no config/importmap.rb in history).
  - Blind spot: None significant — already documented in commit + PR.
- **Fix B**: Run importmap:install here to make bin/ci fully green.
  - Strength: bin/ci truly green; 2.1 literally holds.
  - Tradeoff: Scope expansion the plan excluded (layout, config/importmap.rb, app/javascript, scan_js domain).
  - Confidence: MED — mechanical but blast radius exceeds F-03's remit.
  - Blind spot: Whether the skeleton app uses importmap JS yet.
- **Decision**: FIXED via Fix A — 2.1 stays marked; importmap gap queued in follow-ups/review-fixes.md

### F2 — Latent: db:prepare against a schema-less skeleton

- **Severity**: ℹ️ OBSERVATION
- **Impact**: 🏃 LOW — no action needed on this change
- **Dimension**: Safety & Quality (Reliability)
- **Location**: .github/workflows/ci.yml:108 (`bin/rails db:prepare`)
- **Detail**: No migrations / no committed db/schema.rb yet. Today db:prepare + `fixtures :all` against an empty test DB is benign. Once F-02 lands the first migration without committing db/schema.rb, CI's db:prepare can create an empty DB and tests fail confusingly. No defect in this change — a forward note for the schema slice.
- **Fix**: When the first migration lands (F-02), ensure db/schema.rb is committed so CI's db:prepare loads the schema.
- **Decision**: FIXED via follow-up — queued in follow-ups/review-fixes.md for F-02

### F3 — Justified EXTRA: Minitest.after_run exit-status guard

- **Severity**: ℹ️ OBSERVATION
- **Impact**: 🏃 LOW — informational; no change needed
- **Dimension**: Scope Discipline / Plan Adherence
- **Location**: test/test_helper.rb:42-50
- **Detail**: A `Minitest.after_run` block (not in the plan's literal text) re-asserts SimpleCov's exit status. Both review agents judged it JUSTIFIED and NECESSARY: the plan's Critical Implementation Detail requires the gate to enforce under `bin/rails test`, but minitest's autorun installs a final at_exit (`exit exit_code`) that swallows SimpleCov's non-zero coverage exit. Without it, flipping COVERAGE_MIN=80 in S-04/S-05/S-07 would not fail CI. Verified correct: nil-safe via SimpleCov.result?, no-op in report-only mode, no double-exit. Documented inline.
- **Fix**: None. Candidate for /10x-lesson (recurring Rails gotcha: minitest autorun swallows SimpleCov's exit code under `bin/rails test`).
- **Decision**: ACCEPTED-AS-RULE (saved to context/foundation/lessons.md) — code already conformant (test_helper.rb:42-50), no fix needed.

### Note (not a finding)

Criterion 1.5 ("console coverage summary"): the plan asked for a formatter producing "HTML + console summary". No explicit formatter line exists, but SimpleCov core prints the Line/Branch summary anyway (verified). Requirement satisfied.
