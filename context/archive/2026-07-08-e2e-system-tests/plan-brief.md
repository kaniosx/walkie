# E2E System Tests — Plan Brief

> Full plan: `context/changes/e2e-system-tests/plan.md`

## What & Why

User asked for "any e2e test" to exist in the project. Since this repo has
no Node toolchain (Propshaft + importmap by design), Playwright — the
`/10x-e2e` skill's native tooling — was rejected in favor of Rails' built-in
System Tests (Capybara + Selenium, headless Chromium), which need no Node
at all and run via `bin/rails test:system` alongside the existing Minitest
suite.

## Starting Point

No e2e infrastructure exists anywhere: no gems, no browser in either Docker
image, no `test/system/` directory, and CI's `test` job runs `bin/rails
test` which silently excludes system tests by Rails convention. The target
flow ("Owner creates a walk request") is a single `button_to` on the dogs
page, not a form — simpler than a typical e2e candidate.

## Desired End State

`docker compose exec web bin/rails test:system` runs two green tests
locally and in CI: a smoke test proving the pipeline works, and a real test
proving an Owner can sign in through the actual login form and create a
walk request by clicking through the real rendered UI.

## Key Decisions Made

| Decision | Choice | Why (1 sentence) |
|---|---|---|
| E2E tooling | Rails System Tests (Capybara + Selenium), not Playwright | No Node toolchain exists or is wanted in this project |
| Browser install | Debian's `chromium` + `chromium-driver` via apt | Matches the existing `ruby:slim` base image's package manager; simplest Dockerfile diff |
| CI wiring | Add `bin/rails test:system` to the CI `test` job now | `ubuntu-latest` ships Chrome already; an e2e test that never runs in CI provides no PR-level protection |
| Phasing | Infra + trivial smoke test first, real flow test second | Isolates "is the browser infra broken" from "is the flow logic broken" for future debugging |
| Debug mode | Always headless, no headed toggle | The `web` container has no display server — a headed toggle would be dead weight today |
| Tracking | Formal change folder (not `/10x-e2e` standalone mode) | Touches Gemfile/Dockerfile/CI — real infra worth a paper trail, not just a quick test file |

## Scope

**In scope:**
- `capybara` + `selenium-webdriver` gems (test group)
- Chromium in `Dockerfile.dev`
- `test/application_system_test_case.rb` (headless, `--no-sandbox` / `--disable-dev-shm-usage` for Docker-as-root)
- One CI step: `bin/rails test:system`
- One smoke test + one real flow test ("Owner creates a walk request")

**Out of scope:**
- Playwright / any Node toolchain
- Headed/debuggable browser mode
- More than two system tests total
- Any change to `context/foundation/test-plan.md` or its phased rollout
- Production `Dockerfile` changes

## Architecture / Approach

Phase 1 stands up the whole pipeline (gems → Docker browser → base class →
CI step) and proves it with a throwaway-simple smoke test before Phase 2
spends any effort on real flow logic. This way, if something breaks later,
it's immediately clear whether the browser infra or the flow itself is at
fault.

## Phases at a Glance

| Phase | What it delivers | Key risk |
|---|---|---|
| 1. Infra + CI + smoke test | Working Capybara+Selenium+Chromium pipeline, locally and in CI | Headless Chromium running as root in Docker needs `--no-sandbox`/`--disable-dev-shm-usage` or it won't launch at all |
| 2. Owner-creates-walk-request test | The one real e2e test this change exists to deliver | A test that passes without ever having been proven to fail (no deliberate-break check) protects nothing |

**Prerequisites:** None — additive infra, no dependency on other in-flight changes.
**Estimated effort:** ~1 session, both phases.

## Open Risks & Assumptions

- CI's new system-test step can only be confirmed working after an actual push — the manual verification for Phase 1 depends on a real GitHub Actions run, not something checkable locally.
- Debian's `chromium`/`chromium-driver` apt packages could lag Google's stable Chrome release by a few weeks; acceptable for a test-only browser, but worth knowing if a chromedriver/browser version mismatch ever surfaces.

## Success Criteria (Summary)

- `bin/rails test:system` passes locally and in CI, with two tests: one smoke test, one real Owner-flow test
- The real flow test is proven to actually catch a regression via a deliberate-break check, not just proven to pass
- The existing Minitest suite (`bin/rails test`) is completely unaffected
