# F-03: Test Infrastructure Scaffold — Coverage Tooling + CI Test Gate

## Overview

Add the coverage tooling and CI test gate that make the PRD's ≥80%-coverage Guardrail measurable and enforceable. Install **SimpleCov** (line + branch coverage, scoped to `app/` minus generated boilerplate), wired **report-only** today — because the four core flows the PRD scopes the 80% target to (create-request / accept / start / complete) don't exist yet — with a single documented hook that S-04/S-05/S-07 flip to enforce 80%. Then close the gap where **both** CI surfaces currently skip tests: add a test step to the local `bin/ci` runner (`config/ci.rb`) and a `test` job to GitHub Actions (`.github/workflows/ci.yml`) backed by a Postgres 17 service. This is roadmap item **F-03**; it has no prerequisites and was meant to run parallel with F-01.

## Current State Analysis

The ground shifted since the roadmap was written (all confirmed by direct inspection):

- **`test/` already exists with a live suite.** F-01 wrote `test/models/user_test.rb` + three integration tests (`registration_test.rb`, `authentication_test.rb`, `sessions_test.rb`) and a standard `test/test_helper.rb` (`fixtures :all`, **no `parallelize`**). This change bolts coverage onto an existing suite, not a from-zero scaffold.
- **CI exists but never runs tests.** The Rails 8 starter shipped `.github/workflows/ci.yml` with jobs `scan_ruby` (brakeman + bundler-audit), `scan_js` (importmap audit), and `lint` (rubocop) — **no test job, no Postgres service**. The local `bin/ci` → `config/ci.rb` (Rails 8.1 `ActiveSupport::ContinuousIntegration`) runs Setup, rubocop, bundler-audit, importmap audit, brakeman — **but never `bin/rails test`**.
- **No SimpleCov** in `Gemfile`, `Gemfile.lock`, or `.gitignore`.
- **The 80% target can't be measured against the named flows yet.** Create-request / accept / start / complete are S-04/S-05/S-07; F-02 (walks schema) is only *planned*. The sole domain code today is auth (F-01). A global `minimum_coverage 80` enforced now would gate against auth + framework boilerplate, not the PRD's flows.
- Ruby 3.4.9 (`.ruby-version`), Postgres, Docker-only Rails commands. Stale `bootstrap_scaffold_*` DB name persists (out of scope).

### Key Discoveries:

- **`SimpleCov.start` must run before `require "../config/environment"`** in `test_helper.rb:2`. SimpleCov only counts files loaded *after* it starts; placing it below the environment require silently under-reports coverage of everything loaded at boot (most of `app/`). This is the single most important ordering constraint.
- **Branch coverage needs `enable_coverage :branch`** inside the `SimpleCov.start` block, and the threshold form becomes `minimum_coverage line: X, branch: Y`.
- **The existing GHA jobs are the copy template** — each does `actions/checkout@v6` + `ruby/setup-ruby@v1` (`bundler-cache: true`). The new `test` job follows the same shape, adding a Postgres service + `db:prepare`.
- **Serial suite keeps SimpleCov trivial** — `test_helper.rb` has no `parallelize`, so no per-process result merging is needed. Leave it serial (decision).
- **`bin/ci` is a Ruby script** (`config/boot` → `ActiveSupport::ContinuousIntegration` → `config/ci.rb`); steps are `step "<name>", "<shell command>"`.

## Desired End State

Running `bin/rails test` (locally or in Docker) produces a coverage report (`coverage/` HTML + a console summary) over `app/` minus boilerplate, with branch coverage on; the suite stays green. `bin/ci` runs the full pipeline **including tests**. GitHub Actions runs tests against Postgres 17 on every push/PR and reports pass/fail. The 80% gate is wired but dormant, with a documented one-line flip for the slice that completes the core flows. Verifiable by: `bin/rails test` green + `coverage/index.html` generated; `bin/ci` green end-to-end; `ci.yml` parses and the remote `test` job goes green on push.

## What We're NOT Doing

- **Not enforcing the hard 80% gate now** — it's report-only until the 4 core flows exist (S-04/S-05/S-07 ratchet it). Enforcing today would gate against boilerplate, not the PRD's flows.
- **Not enabling test parallelization** — suite stays serial to keep SimpleCov merge-free; revisit when the suite grows.
- **Not turning on Auto-Deploy** — explicitly deferred (roadmap F-03); the GHA workflow gains a test job only, no deploy job.
- **Not writing new feature tests** — F-03 is tooling/CI; the core-flow tests that satisfy 80% are authored in their own slices (S-04/S-05/S-07).
- **Not adding a CI coverage-annotation service** (Codecov/Coveralls/LCOV upload) — local HTML + console summary is enough for v1; can be added later.
- **Not renaming the `bootstrap_scaffold_*` DB** — orthogonal, same as F-01/F-02.
- **Not touching the existing brakeman/bundler-audit/rubocop jobs** — they stay as-is.

## Implementation Approach

Three small, independently verifiable phases in dependency order: get coverage measuring correctly first (it's the artifact the gate consumes), then wire tests into the local runner, then into remote CI. Each phase ends green. Mirror the repo's conventions: comment-documented config, omakase rubocop, the existing GHA job shape.

## Critical Implementation Details

- **SimpleCov load order.** `require "simplecov"` + `SimpleCov.start` must be the first lines of `test/test_helper.rb`, above `require_relative "../config/environment"`. Out of order, coverage is silently wrong.
- **Dormant-but-wired gate.** Express the threshold through a single visible knob (a constant or `ENV.fetch("COVERAGE_MIN", 0)`), defaulting to report-only (0 / no failing minimum) now, with a comment naming S-04/S-05/S-07 as the slices that raise it to `line: 80, branch: 80`. Flipping one value enforces the gate across both local and CI runs (SimpleCov's `at_exit` runs during `bin/rails test` everywhere).
- **GHA Postgres + DB prep.** The `test` job needs a `postgres:17` service and `RAILS_ENV=test`; run `bin/rails db:prepare` before `bin/rails test`. The `bootstrap_scaffold_test` DB name in `config/database.yml` is what `db:prepare` targets — the job must point at the service (via `DATABASE_URL` or matching `database.yml` host/credentials env).

## Phase 1: SimpleCov coverage tooling

### Overview

Install and configure SimpleCov so `bin/rails test` measures line + branch coverage over `app/` minus boilerplate, emits an HTML report + console summary, and carries a dormant-but-wired 80% gate.

### Changes Required:

#### 1. Add the SimpleCov gem

**File**: `Gemfile`

**Intent**: Make the coverage tool available in the test environment only.

**Contract**: Add `gem "simplecov", require: false` to the existing `group :development, :test do` block (or a `group :test`). Run `docker compose exec web bundle install`. `require: false` because SimpleCov is started explicitly in `test_helper`, not auto-required.

#### 2. Configure SimpleCov at the top of the test helper

**File**: `test/test_helper.rb`

**Intent**: Start coverage tracking before the app boots, scope it to the code we wrote, enable branch coverage, and wire the dormant gate.

**Contract**: At the **very top of the file**, before `require_relative "../config/environment"`:
- `require "simplecov"` then `SimpleCov.start "rails" do … end`.
- Inside the block: `enable_coverage :branch`; `add_filter`s removing generated boilerplate (e.g. `app/channels`, `application_cable`, `application_mailer`, `application_record`, `app/jobs` scaffolding, plus the default `config/`, `test/`, `db/`, `bin/`, `vendor/`); optional `add_group "Models"`/`"Controllers"` for readable reports; formatter producing HTML + a console summary.
- The dormant gate: a single visible knob, e.g.
  ```ruby
  # Report-only until the 4 core flows exist. S-04/S-05/S-07 raise this to 80.
  coverage_min = ENV.fetch("COVERAGE_MIN", "0").to_f
  minimum_coverage(line: coverage_min, branch: coverage_min) if coverage_min.positive?
  ```
Leave the rest of `test_helper.rb` (the `ActiveSupport::TestCase` / `fixtures :all` block) unchanged. Do **not** add `parallelize`.

#### 3. Ignore the coverage output

**File**: `.gitignore`

**Intent**: Keep generated coverage artifacts out of version control.

**Contract**: Add `/coverage` (and `/coverage/` if needed) to `.gitignore`.

### Success Criteria:

#### Automated Verification:

- Bundle installs cleanly: `docker compose exec web bundle install`
- Full suite stays green: `docker compose exec web bin/rails test`
- Coverage report is generated: `coverage/index.html` exists after a test run
- Linting passes: `docker compose exec web bundle exec rubocop`

#### Manual Verification:

- The test run prints a coverage summary line to the console (line + branch %).
- `coverage/index.html` opens and shows `app/` files (models/controllers) with boilerplate filtered out.
- No failing coverage gate fires (report-only): a run with low coverage does not exit non-zero.

**Implementation Note**: After completing this phase and all automated verification passes, pause for manual confirmation before proceeding.

---

## Phase 2: Wire tests into the local `bin/ci` runner

### Overview

Close the gap where `bin/ci` runs lint + security but never tests, so the local pipeline matches what CI should enforce.

### Changes Required:

#### 1. Add a Tests step to the CI runner

**File**: `config/ci.rb`

**Intent**: Make `bin/ci` run the test suite (and thus produce coverage) as part of the local pipeline.

**Contract**: Add `step "Tests", "bin/rails test"` to the `CI.run do … end` block. Place it after `step "Setup", …` so the DB/setup is ready; ordering relative to style/security steps is a readability choice (recommend tests early so failures surface fast). Leave the commented `gh signoff` block untouched.

### Success Criteria:

#### Automated Verification:

- The local CI pipeline runs and passes end-to-end including tests: `docker compose exec web bin/ci`
- Linting passes: `docker compose exec web bundle exec rubocop`

#### Manual Verification:

- `bin/ci` output shows the "Tests" step executing `bin/rails test` and the coverage summary appears.
- The pipeline fails fast and visibly if a test is made to fail (try one, then revert).

**Implementation Note**: After completing this phase and all automated verification passes, pause for manual confirmation before proceeding.

---

## Phase 3: GitHub Actions test job

### Overview

Add the missing `test` job to the existing GitHub Actions workflow so tests run on every push/PR against Postgres 17. Auto-Deploy stays off.

### Changes Required:

#### 1. Add a `test` job to the CI workflow

**File**: `.github/workflows/ci.yml`

**Intent**: Run the suite (and the coverage gate, once enabled) remotely on push/PR, delivering the roadmap's "CI placeholder runs tests + coverage gate on push."

**Contract**: A new `test` job alongside `scan_ruby` / `scan_js` / `lint`, mirroring their `actions/checkout@v6` + `ruby/setup-ruby@v1` (`bundler-cache: true`) setup, plus:
- a `services.postgres` using `postgres:17` with health-check options and exposed port 5432;
- environment (`RAILS_ENV: test`, and `DATABASE_URL` or matching PG host/user/password env so `config/database.yml`'s `bootstrap_scaffold_test` connects to the service);
- steps: `bin/rails db:prepare` then `bin/rails test`.
No deploy job is added (Auto-Deploy stays off). Do not modify the existing three jobs.

### Success Criteria:

#### Automated Verification:

- Workflow YAML is valid (parses; `actionlint` or a GitHub push without syntax error).
- The `test` job runs `bin/rails db:prepare` + `bin/rails test` and the suite passes in CI.

#### Manual Verification:

- After pushing, the GitHub Actions run shows a green `test` job (alongside the existing scan/lint jobs).
- The Postgres service connects (no "could not connect to server" in the job log).
- No deploy is triggered (Auto-Deploy remains off).

**Implementation Note**: After completing this phase and all automated verification passes, pause for manual confirmation. This completes F-03.

---

## Testing Strategy

F-03 adds no application tests — it instruments and gates the existing suite. Verification is the tooling behaving correctly:

### Unit / Integration Tests:

- The existing F-01 suite (user model + auth/registration/sessions integration) must stay green throughout; it is the corpus coverage is measured against.

### Manual Testing Steps:

1. Run `bin/rails test`; confirm a coverage summary prints and `coverage/index.html` is generated over `app/` minus boilerplate.
2. Temporarily set `COVERAGE_MIN=95` and re-run; confirm the gate now fails (proves it's wired), then unset.
3. Run `bin/ci`; confirm the "Tests" step runs and the whole pipeline is green.
4. Push a branch; confirm the GitHub Actions `test` job runs against Postgres and goes green.

## Performance Considerations

Negligible. SimpleCov adds minor instrumentation overhead to the (tiny) suite. The GHA `test` job adds one parallel job with a Postgres service — standard. No application-runtime impact (test-only gem).

## Migration Notes

No data migrations. One new dev/test dependency (`simplecov`). The coverage gate ships **dormant** (`COVERAGE_MIN` defaults to 0 / report-only); the follow-up obligation is explicit: the slice that completes the core lifecycle (S-05, with S-04/S-07) sets `COVERAGE_MIN=80` (CI env or the constant default) so the PRD's ≥80% Guardrail becomes binding once the flows it scopes to exist. This is documented in `test_helper.rb` next to the knob.

## References

- Roadmap item: `context/foundation/roadmap.md` §F-03 (and §Success Criteria §Guardrails for the ≥80% target)
- PRD: `context/foundation/prd.md` — §Success Criteria §Guardrails (≥80% coverage on the 4 core flows)
- Change identity: `context/changes/test-infrastructure-scaffold/change.md`
- Existing CI: `.github/workflows/ci.yml`, `config/ci.rb`, `bin/ci`
- Existing suite (coverage corpus): `test/test_helper.rb`, `test/models/user_test.rb`, `test/integration/*.rb`
- Downstream consumers of the gate: S-04 (`owner-creates-walk-request`), S-05 (`walker-accepts-request`), S-07 (`walker-starts-and-completes-walk`)
- CLAUDE.md tripwires: Docker-only Rails commands; stale `bootstrap_scaffold_*` DB name

## Progress

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles. See `references/progress-format.md`.

### Phase 1: SimpleCov coverage tooling

#### Automated

- [x] 1.1 Bundle installs cleanly: `docker compose exec web bundle install` — 1b3571f
- [x] 1.2 Full suite stays green: `docker compose exec web bin/rails test` — 1b3571f
- [x] 1.3 Coverage report generated: `coverage/index.html` exists after a test run — 1b3571f
- [x] 1.4 Linting passes: `docker compose exec web bundle exec rubocop` — 1b3571f

#### Manual

- [x] 1.5 Test run prints a console coverage summary (line + branch %) — 1b3571f
- [x] 1.6 `coverage/index.html` shows `app/` files with boilerplate filtered out — 1b3571f
- [x] 1.7 Report-only confirmed: a low-coverage run does not exit non-zero — 1b3571f

### Phase 2: Wire tests into the local `bin/ci` runner

#### Automated

- [x] 2.1 Local CI pipeline passes end-to-end including tests: `docker compose exec web bin/ci` — 46590e9
- [x] 2.2 Linting passes: `docker compose exec web bundle exec rubocop` — 46590e9

#### Manual

- [x] 2.3 `bin/ci` output shows the "Tests" step running `bin/rails test` + coverage summary — 46590e9
- [x] 2.4 Pipeline fails fast on an intentionally-failing test (then reverted) — 46590e9

### Phase 3: GitHub Actions test job

#### Automated

- [x] 3.1 Workflow YAML is valid (parses / no syntax error on push) — f04b72e
- [x] 3.2 `test` job runs `db:prepare` + `bin/rails test` and the suite passes in CI — f04b72e

#### Manual

- [x] 3.3 GitHub Actions run shows a green `test` job alongside the existing jobs — f04b72e
- [x] 3.4 Postgres service connects (no connection error in the job log) — f04b72e
- [x] 3.5 No deploy is triggered (Auto-Deploy remains off) — f04b72e
