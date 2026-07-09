<!-- IMPL-REVIEW-REPORT -->
# Implementation Review: E2E System Tests

- **Plan**: context/changes/e2e-system-tests/plan.md
- **Scope**: Full plan (Phase 1 of 2, Phase 2 of 2)
- **Date**: 2026-07-09
- **Verdict**: APPROVED
- **Findings**: 0 critical, 0 warnings, 1 observation

## Verdicts

| Dimension | Verdict |
|-----------|---------|
| Plan Adherence | PASS |
| Scope Discipline | WARNING (benign, justified) |
| Safety & Quality | PASS |
| Architecture | PASS |
| Pattern Consistency | PASS |
| Success Criteria | PASS |

## Evidence

- **Plan Adherence**: both review sub-agents independently confirmed all 6 planned changes across Phase 1 (Gemfile, Dockerfile.dev, application_system_test_case.rb, ci.yml system-test step, smoke_test.rb) and Phase 2 (owner_creates_walk_request_test.rb) MATCH the plan's intent exactly. One minor addition beyond the literal contract — `assert_text "Sign out"` in Phase 2's test — is a justified stabilization fixing a real Turbo-navigation race (documented in commit 86d6f54's message).
- **Scope Discipline**: two out-of-plan items landed — commit `8368e0d` (Build Tailwind CSS CI step) and a `context/foundation/roadmap.md` touch in `fdfd0cb`. Both confirmed benign and justified: the Tailwind step was necessary to verify the plan's own manual item 1.8 (CI's test job was already broken for unrelated pre-existing reasons since before this change), and the roadmap touch is change-tracking bookkeeping, not application code. WARNING rather than FAIL/PASS to keep this visible, not because either is a problem.
- **Safety & Quality**: no CRITICAL/WARNING findings. The `--no-sandbox`/`--disable-dev-shm-usage` Chrome flags are correctly scoped to the dev-only `Dockerfile.dev` (confirmed no `USER` directive there) and don't leak into the production `Dockerfile` (which runs non-root and never installs a browser). No hardcoded secrets beyond the pre-existing project-wide test password convention. The Tailwind CI fix is a genuine bug fix (traced: `tailwind.css` is gitignored, every layout pulls it, CI never built it) not a workaround.
- **Pattern Consistency**: both new system tests follow the existing integration-test suite's naming/structure/inline-fixture conventions exactly. `application_system_test_case.rb`'s location matches Rails' own generator convention.
- **Success Criteria**: independently re-ran all 4 automated checks post-implementation — `bin/rails test:system` (2 runs, 0 failures), `bin/rails test` (108 runs, 0 failures), `bundle exec rubocop` (68 files, 0 offenses), `bundle exec brakeman --no-pager` (0 warnings). Both manual checks have real evidence: the deliberate-break check's failure output is in the implementation conversation, and the actual green CI run (`gh run view` on the system-test step, 2 runs/6 assertions/0 failures) was fetched and confirmed live, not assumed.

## Findings

### F1 — CI's system-test step relies on an undocumented implicit browser install

- **Severity**: ⚪ OBSERVATION
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Safety & Quality
- **Location**: .github/workflows/ci.yml:113-117
- **Detail**: `Dockerfile.dev` explicitly installs `chromium chromium-driver`, but CI's `Run system tests` step has no browser-install step at all — it works only because `ubuntu-latest` ships Google Chrome pre-installed and Selenium Manager auto-detects it. Currently working (verified live), but an implicit, undocumented dependency on runner image contents, inconsistent with the local Docker path's explicit pin.
- **Fix**: Add a one-line comment above the "Run system tests" step noting that ubuntu-latest ships Chrome and Selenium Manager auto-detects it, so a future maintainer doesn't wonder why no install step exists there.
- **Decision**: FIXED
