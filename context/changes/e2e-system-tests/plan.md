# E2E System Tests Implementation Plan

## Overview

Add the project's first browser-level end-to-end test using Rails' built-in
System Tests (Capybara + Selenium, headless Chromium) — no Node toolchain,
consistent with this project's Propshaft + importmap stack. This is a
standalone infra + first-test addition requested directly by the user, not
part of the `context/foundation/test-plan.md` phased rollout (that plan
explicitly deferred e2e for v1 since the four core flows are already
covered by ActionDispatch integration tests).

## Current State Analysis

No e2e infrastructure exists: no Playwright, no Capybara/Selenium gems, no
`test/system/` directory, no browser in either Docker image. `Gemfile`'s
test-relevant group (`group :development, :test`) has only
debug/bundler-audit/brakeman/rubocop/simplecov — no test-only group exists
yet. `Dockerfile.dev` installs `build-essential curl git libpq-dev libvips
libyaml-dev pkg-config postgresql-client` — no browser. CI
(`.github/workflows/ci.yml`) runs natively on `ubuntu-latest` via
`ruby/setup-ruby` (not Docker) and its `test` job runs `bin/rails test`,
which excludes `test/system/*` by Rails convention — a new system test
would silently not run in CI without an explicit `bin/rails test:system`
step.

The target flow ("Owner creates a walk request") is simpler than a typical
form flow: `app/views/dogs/index.html.erb:30` renders a single
`button_to "Walk my dog", walks_path, params: { dog_id: dog.id }` per dog
(with an `aria-label` for accessible disambiguation). `WalksController#create`
(`app/controllers/walks_controller.rb`) scopes the dog lookup to
`current_user.dogs.active`, creates the walk, and redirects to `walks_path`
with a notice on success or an alert on failure. Sign-in is a real form at
`app/views/sessions/new.html.erb` with labeled "Email address" and
"Password" fields — existing integration tests bypass this via a direct
`post session_path`, but a system test should drive the real form since
that's exactly the kind of real-browser behavior integration tests can't
prove.

## Desired End State

`docker compose exec web bin/rails test:system` runs two passing system
tests: a smoke test proving the Capybara+Selenium+headless-Chromium
pipeline works, and a real test proving an Owner can sign in through the
actual login form and create a walk request by clicking through the actual
rendered UI. The same command (or equivalent) runs in CI on every PR. The
existing Minitest suite (`bin/rails test`) is unaffected.

### Key Discoveries:

- `app/views/dogs/index.html.erb:30` — the walk-creation trigger is a
  `button_to`, not a form with fields; the system test drives it via
  `click_on "Walk my dog"`.
- `app/controllers/walks_controller.rb` `create` action — redirects to
  `walks_path` with `notice: "Walk requested for #{dog.name}."` on success.
- `.github/workflows/ci.yml`'s `test` job runs on `ubuntu-latest`, which
  ships Google Chrome preinstalled — Selenium 4.6+'s Selenium Manager
  auto-detects it and downloads a matching chromedriver, so CI needs only a
  new step, not a new browser install.
- The `web` container's `Dockerfile.dev` has no `USER` directive (runs as
  root) — headless Chromium refuses to run as root without `--no-sandbox`,
  and Docker's default small `/dev/shm` can crash Chromium without
  `--disable-dev-shm-usage`. Both flags are required in
  `test/application_system_test_case.rb`, not optional hardening.

## What We're NOT Doing

- Not touching `context/foundation/test-plan.md` — this change is
  explicitly outside that phased rollout (see `change.md`).
- Not adding Playwright or any Node toolchain.
- Not writing more than two system tests (one smoke test, one real flow) —
  e2e is expensive; this establishes the pattern, not a sweep.
- Not adding a headed/debuggable browser mode — the `web` container has no
  display server, so a headed toggle would be dead weight until X11/VNC
  forwarding is also set up.
- Not modifying the production `Dockerfile` — system tests never run there.
- Not modifying `test/integration/*` or `test/models/*` — those stay as-is.

## Implementation Approach

Phase 1 stands up the full pipeline (gems, browser, base class, CI step)
and proves it works end-to-end with a trivial smoke test before any real
flow logic is involved — isolating "is the infra broken" from "is the flow
broken" for whoever debugs a failure later. Phase 2 adds the one real test
this change exists to deliver, verified with a deliberate-break check so
it's confirmed to actually catch a regression, not just render green.

## Critical Implementation Details

### Running headless Chromium as root inside Docker

`test/application_system_test_case.rb` must pass `--no-sandbox` and
`--disable-dev-shm-usage` to Chrome via the `driven_by` block form —
without them, Selenium will fail to launch the browser inside the `web`
container (root user, small `/dev/shm`). This is not generic hardening,
it's required for the smoke test to pass at all:

```ruby
driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400] do |driver_option|
  driver_option.add_argument("--no-sandbox")
  driver_option.add_argument("--disable-dev-shm-usage")
end
```

### Signing in through the real form, not the integration-test shortcut

Existing integration tests sign in via `post session_path` directly
(`test/integration/walker_walks_test.rb:16-18`). The system test must NOT
reuse that shortcut — it should `visit new_session_path`, `fill_in "Email
address"` / `fill_in "Password"`, and `click_on "Sign in"`, because driving
the real login form is part of what makes this an end-to-end test rather
than a relabeled integration test.

## Phase 1: Infra bootstrap, CI wiring, smoke test

### Overview

Stand up Capybara + Selenium + headless Chromium locally and in CI, and
prove the pipeline works with one trivial test before building the real
flow on top of it.

### Changes Required:

#### 1. Add test-only gems

**File**: `Gemfile`

**Intent**: Add Capybara and Selenium WebDriver, scoped to the `test` group
only (not needed in development).

**Contract**: A new `group :test do ... end` block (Rails' own default
Gemfile shape) containing `gem "capybara"` and `gem "selenium-webdriver"`.
Run `bundle install` inside the container afterward; commit the updated
`Gemfile.lock`.

#### 2. Install a headless browser in the dev/test Docker image

**File**: `Dockerfile.dev`

**Intent**: Give the `web` container a real browser to drive, since Rails
commands only run inside Docker for this project.

**Contract**: Add `chromium chromium-driver` to the existing
`apt-get install --no-install-recommends` package list (same line as the
current `build-essential curl git ...` packages — don't add a second
`RUN apt-get` layer). Rebuild the image afterward
(`docker compose build web` or `docker compose up -d --build`).

#### 3. System test base class

**File**: `test/application_system_test_case.rb`

**Intent**: The standard Rails base class every system test inherits from,
configured for headless Chromium running as root in Docker (see Critical
Implementation Details above).

**Contract**: `ActionDispatch::SystemTestCase` subclass named
`ApplicationSystemTestCase`, `driven_by :selenium, using: :headless_chrome,
screen_size: [1400, 1400]` with the `--no-sandbox` /
`--disable-dev-shm-usage` driver-option block from Critical Implementation
Details.

#### 4. Wire system tests into CI

**File**: `.github/workflows/ci.yml`

**Intent**: Make the new test layer a real regression gate on PRs, not just
a local-only capability.

**Contract**: Add a `Run system tests` step to the existing `test` job
(after the `Run tests` step), running `bin/rails test:system`. No new job,
no new services — reuses the job's existing Postgres service and `RAILS_ENV:
test` env block. No browser install needed (`ubuntu-latest` ships Chrome;
Selenium Manager auto-detects it).

#### 5. Smoke test

**File**: `test/system/smoke_test.rb`

**Intent**: Prove Capybara + Selenium + headless Chromium actually boot and
render a real page, independent of any application flow — the canary that
isolates infra failures from flow-logic failures.

**Contract**: One test in a new `ApplicationSystemTestCase` subclass:
`visit new_session_path` and assert the rendered page shows the "Sign in"
heading and both form fields. No database fixtures needed.

### Success Criteria:

#### Automated Verification:

- [ ] Bundle installs cleanly: `docker compose exec web bundle install`
- [ ] Docker image rebuilds with the new browser: `docker compose build web`
- [ ] Smoke test passes: `docker compose exec web bin/rails test:system`
- [ ] Full suite still passes: `docker compose exec web bin/rails test`
- [ ] Lint passes: `docker compose exec web bundle exec rubocop`
- [ ] Security scan passes: `docker compose exec web bundle exec brakeman --no-pager`
- [ ] CI workflow YAML is syntactically valid: `docker compose exec web ruby -ryaml -e "YAML.load_file('.github/workflows/ci.yml')"`

#### Manual Verification:

- [ ] After pushing this phase, confirm the CI `test` job's new "Run system tests" step actually passes in the GitHub Actions tab (can't be verified locally — GitHub-hosted runner behavior).

---

## Phase 2: Owner-creates-walk-request system test

### Overview

Write the one real flow this change exists to deliver: an Owner signing in
through the actual login form and creating a walk request by clicking
through the actual rendered UI — proving a real-browser path that the
existing ActionDispatch integration tests can't exercise.

### Changes Required:

#### 1. Owner-creates-walk-request system test

**File**: `test/system/owner_creates_walk_request_test.rb`

**Intent**: Prove the full real-browser journey — sign in via the real
form, navigate to the dogs page, click the real "Walk my dog" button, and
see the walk request reflected on the walks page — works end-to-end.

**Contract**: One `ApplicationSystemTestCase` test. Setup creates an owner
and a dog inline (`User.create!` / `owner.dogs.create!`, matching the
existing test suite's convention of inline fixtures over YAML — see
`test/test_helper.rb`'s comment on `has_secure_password`). Flow: `visit
new_session_path` → `fill_in "Email address"` / `fill_in "Password"` →
`click_on "Sign in"` → `visit dogs_path` → `click_on "Walk my dog"` →
`assert_text "Walk requested for <dog name>."` and assert the dog's name
appears in the walks page's Active section.

### Success Criteria:

#### Automated Verification:

- [ ] New system test passes: `docker compose exec web bin/rails test:system`
- [ ] Full suite still passes: `docker compose exec web bin/rails test`
- [ ] Lint passes: `docker compose exec web bundle exec rubocop`
- [ ] Security scan passes: `docker compose exec web bundle exec brakeman --no-pager`

#### Manual Verification:

- [ ] Deliberate-break check: temporarily invert `WalksController#create`'s success outcome (e.g. force the `if walk.save` branch to always take the `else`/alert path) and confirm the new system test fails. Revert immediately.

---

## Testing Strategy

### Unit Tests:

- None — no model/business-logic changes.

### Integration Tests:

- None — existing `test/integration/*` coverage is untouched and unaffected.

### Manual Testing Steps:

1. Phase 1: after pushing, check the GitHub Actions run for the new CI step.
2. Phase 2: perform the deliberate-break check and confirm the test goes red, then green again after reverting.

## Performance Considerations

System tests are the slowest, most flake-prone layer in this suite — kept
to exactly two tests (one smoke, one real flow) by design. CI's new step
adds real wall-clock time to the `test` job (launching a real browser is
much slower than plain HTTP integration tests) but reuses the job's
existing Postgres service, so no additional infra cost.

## Migration Notes

Not applicable — no schema or data changes.

## References

- Existing integration-test conventions: `test/integration/walker_walks_test.rb`
- Target flow controller: `app/controllers/walks_controller.rb`
- Target flow view: `app/views/dogs/index.html.erb:30`
- Login form: `app/views/sessions/new.html.erb`
- Existing CI test job: `.github/workflows/ci.yml`

## Progress

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles. See `references/progress-format.md`.

### Phase 1: Infra bootstrap, CI wiring, smoke test

#### Automated

- [x] 1.1 Bundle installs cleanly: `docker compose exec web bundle install`
- [x] 1.2 Docker image rebuilds with the new browser: `docker compose build web`
- [x] 1.3 Smoke test passes: `docker compose exec web bin/rails test:system`
- [x] 1.4 Full suite still passes: `docker compose exec web bin/rails test`
- [x] 1.5 Lint passes: `docker compose exec web bundle exec rubocop`
- [x] 1.6 Security scan passes: `docker compose exec web bundle exec brakeman --no-pager`
- [x] 1.7 CI workflow YAML is syntactically valid

#### Manual

- [ ] 1.8 Confirm the CI test job's new system-test step passes after pushing

### Phase 2: Owner-creates-walk-request system test

#### Automated

- [ ] 2.1 New system test passes: `docker compose exec web bin/rails test:system`
- [ ] 2.2 Full suite still passes: `docker compose exec web bin/rails test`
- [ ] 2.3 Lint passes: `docker compose exec web bundle exec rubocop`
- [ ] 2.4 Security scan passes: `docker compose exec web bundle exec brakeman --no-pager`

#### Manual

- [ ] 2.5 Deliberate-break check: invert the create action's outcome, confirm the test fails, then revert
