# F-03: Test Infrastructure Scaffold — Plan Brief

> Full plan: `context/changes/test-infrastructure-scaffold/plan.md`

## What & Why

Make the PRD's ≥80%-coverage Guardrail measurable and enforceable. Install SimpleCov (line + branch, scoped to the code we wrote), and close the gap where **both** CI surfaces — the local `bin/ci` runner and GitHub Actions — currently run lint + security checks but never the tests. The gate ships report-only because the flows the PRD scopes 80% to don't exist yet; one documented knob turns it on later.

## Starting Point

F-01 already created `test/` and a live suite (user model + 3 auth integration tests) with a standard `test_helper.rb`. The Rails 8 starter shipped `.github/workflows/ci.yml` (brakeman/bundler-audit/importmap/rubocop — **no test job, no Postgres**) and a local `bin/ci`→`config/ci.rb` that also **never runs `bin/rails test`**. No SimpleCov anywhere. The 4 core flows (create/accept/start/complete) are S-04/S-05/S-07 — not built; F-02 is only planned.

## Desired End State

`bin/rails test` produces a coverage report (HTML + console summary) over `app/` minus boilerplate with branch coverage on, suite green. `bin/ci` runs the full pipeline including tests. GitHub Actions runs tests against Postgres 17 on every push/PR. The 80% gate is wired but dormant, flippable in one line when the core flows land. Auto-Deploy stays off.

## Key Decisions Made

| Decision | Choice | Why (1 sentence) | Source |
| --- | --- | --- | --- |
| Gate timing | Report now, enforce when flows land | The PRD's 80% is scoped to 4 flows that don't exist yet; gating now would measure boilerplate, not the flows | Plan |
| Coverage scope | `app/` minus generated boilerplate | The % should reflect code we wrote and the marketplace logic, not framework scaffolding | Plan |
| Coverage type | Line + branch | Catches untested branches in F-02's state-machine guards / role checks where the real risk lives | Plan |
| CI scope | Both local `bin/ci` + GHA test job | Delivers the roadmap's "CI runs tests + coverage gate on push" literally; local loop matches CI | Plan |
| Test parallelism | Keep serial | SimpleCov "just works" with no per-process merge; suite is tiny; simpler for the F-02 concurrency test | Plan |
| Gate knob | `COVERAGE_MIN` env (default 0) | One visible value flips report-only → 80% across both local and CI runs | Plan |

## Scope

**In scope:** SimpleCov gem + config (branch coverage, filters, HTML/console report, dormant gate); `/coverage` gitignore; `Tests` step in `config/ci.rb`; a `test` job in `.github/workflows/ci.yml` with a Postgres 17 service.

**Out of scope:** enforcing 80% now; test parallelization; Auto-Deploy; new feature tests; coverage-upload services (Codecov/LCOV); DB rename; touching the existing scan/lint jobs.

## Architecture / Approach

`SimpleCov.start` goes at the very top of `test_helper.rb` (before `require config/environment`, or it under-counts). Coverage runs in SimpleCov's `at_exit` during every `bin/rails test` — locally, in `bin/ci`, and in GHA — so the single `COVERAGE_MIN` knob enforces everywhere at once. The GHA `test` job copies the existing jobs' Ruby setup and adds a `postgres:17` service + `db:prepare`.

## Phases at a Glance

| Phase | What it delivers | Key risk |
| --- | --- | --- |
| 1. SimpleCov tooling | Coverage measuring correctly, report-only gate wired | `SimpleCov.start` load-order — must precede the environment require |
| 2. Local `bin/ci` test step | `bin/ci` stops skipping tests | Trivial; ordering relative to other steps |
| 3. GitHub Actions test job | Tests run on push against Postgres 17 | Postgres service wiring + `db:prepare` connecting to `bootstrap_scaffold_test` |

**Prerequisites:** None (F-03 had no deps; F-01's suite is the coverage corpus). Docker dev environment + a GitHub repo with Actions enabled.
**Estimated effort:** ~1–2 sessions across 3 small phases.

## Open Risks & Assumptions

- **Deferred enforcement is a tracked obligation:** the 80% gate is dormant until S-04/S-05/S-07 set `COVERAGE_MIN=80`. If those slices forget, the Guardrail silently never binds — documented in `test_helper.rb` next to the knob and in the slices' References.
- **GHA Postgres connection** depends on `config/database.yml`'s `bootstrap_scaffold_test` pointing at the service (via env/`DATABASE_URL`); first remote run may need a tweak.
- **Stale `bootstrap_scaffold_*` DB name** persists (out of scope, same as F-01/F-02).

## Success Criteria (Summary)

- `bin/rails test` emits a line + branch coverage report over `app/` minus boilerplate; suite stays green.
- `bin/ci` runs the full pipeline including tests; GitHub Actions `test` job goes green against Postgres on push.
- The 80% gate is provably wired (setting `COVERAGE_MIN` high makes it fail) but dormant by default.
