# Full Walk Lifecycle — E2E System Test Implementation Plan

## Overview

Add a fourth real-flow browser-level system test (Rails System Tests, Capybara + Selenium — infra from T-01, sign-in helper from T-02) proving the entire walk lifecycle across two personas: an Owner creates a walk request, signs out; a Walker signs in, accepts it, starts it, and completes it — asserting the visible state badge after every transition. Roadmap item **T-04**.

Like T-03, no infra work is needed. This plan is a single phase — one new test file.

## Current State Analysis

- `test/application_system_test_case.rb` already `include`s `SystemSignInHelper` (wired by T-02); `sign_in_via_form(user, password: "secret123")` is available to every system test.
- Every individual transition already has a proven pattern to copy from an existing system test or controller:
  - **Create**: `owner_creates_walk_request_test.rb` — `visit dogs_path` → `click_on "Walk my dog"` → redirects to `walks_path` with `notice: "Walk requested for #{dog.name}."`.
  - **Accept**: `walker_accepts_request_test.rb` — `visit open_requests_path` → `click_button "Accept"` → redirects to `open_requests_path` with `notice: "You accepted the walk for #{dog.name}."`. No `turbo_confirm` on this button.
  - **Start**: `WalkerWalksController#start` (`app/controllers/walker_walks_controller.rb:21`) → `button_to "Start walk", start_walker_walk_path(@walk)` (`app/views/walker_walks/index.html.erb:14`), no confirm dialog — redirects to `walker_walks_path` with `notice: "Walk started — you're on your way!"`.
  - **Complete**: `WalkerWalksController#complete` (`app/controllers/walker_walks_controller.rb:33`) → `button_to "End walk", complete_walker_walk_path(@walk), data: { turbo_confirm: "End walk? This cannot be undone." }` (`app/views/walker_walks/index.html.erb:18-21`) — redirects to `open_requests_path` with `notice: "Walk completed. Well done!"`.
- `owner_cancels_request_test.rb` (T-03) already proved the `turbo_confirm` dialog gotcha: Selenium does not auto-accept it, so any confirm-guarded button needs `accept_confirm { click_on "..." }`. "End walk" carries the same `turbo_confirm` attribute, so this test needs the same wrapper for that one click.
- Sign-out (`button_to "Sign out", session_path, method: :delete`, `app/views/layouts/_nav.html.erb:30`) has no confirm dialog — a plain `click_on "Sign out"` works for switching personas mid-test.
- `app/views/walker_walks/index.html.erb` renders the state badge via `walk_state_badge_classes(@walk.state)` + `@walk.state.humanize` (e.g. "Accepted", "In progress") for the current active walk at the top of the page.
- No fixtures (YAML) anywhere in this suite — test data built inline via `User.create!` / `owner.dogs.create!`, matching every existing system test.

## Desired End State

A new `test/system/full_walk_lifecycle_test.rb` passes against the real app: an Owner creates a request, a Walker accepts/starts/completes it, and every transition's flash message and resulting state badge are asserted — verified via a deliberate-break check on `Walk#start!` during implementation.

### Key Discoveries:

- Two-persona flow uses a single Capybara session with sign-out/sign-in-again to switch identity — no `using_session` needed, since the flow is strictly sequential (Owner then Walker), matching how the existing suite already only ever uses one session per test.
- The Walker's `walker_walks_path` page shows the badge for the single active walk (`@walk`) at the top — the same page renders after accept (redirects to `open_requests_path`, so the Walker must navigate to `walker_walks_path` to see it) and after start (redirects to `walker_walks_path` directly).

## What We're NOT Doing

- Not asserting the Owner's side after completion (e.g., their `walks_path` showing "Completed" + walker name) — that's T-05's scope (`e2e-walk-history`); this test stops once the Walker completes the walk.
- Not breaking `accept!`/`complete!`/`cancel!` in the deliberate-break check — `start!` shares the identical `swap_state` guard already proven breakable by T-02's and T-03's checks on `accept!`/`cancel!`; breaking one representative transition is sufficient.
- Not splitting this into multiple test files or turning it into a template for further multi-step e2e tests — per the roadmap's explicit design intent, this stays a single scenario.
- Not touching CI, Gemfile, Dockerfile.dev, or `test/support/system_sign_in_helper.rb` — all infra already exists from T-01/T-02.

## Implementation Approach

Single phase: one new test file chaining four already-proven transitions (create, accept, start, complete) across two personas in sequence, using the shared sign-in helper and the `accept_confirm` pattern T-03 established for the one `turbo_confirm`-guarded button in this chain ("End walk").

## Phase 1: Add the full-walk-lifecycle system test

### Overview

Add the new test file proving the entire lifecycle through the browser: Owner creates a request, Walker accepts/starts/completes it, with flash + badge assertions after every transition.

### Changes Required:

#### 1. New system test

**File**: `test/system/full_walk_lifecycle_test.rb`

**Intent**: Drive the full happy-path lifecycle across two personas in one browser session: an Owner creates a walk request for their dog, signs out; a Walker signs in, accepts the request, starts the walk, and completes it — with the flash message and visible state badge checked after every transition.

**Contract**: One `test` inside a class extending `ApplicationSystemTestCase`. Setup: `owner = User.create!(...)` (role `"owner"`, city `"Kraków"`, postcode `"30-001"`), `walker = User.create!(...)` (role `"walker"`, same city/postcode), `dog = owner.dogs.create!(name: "Rex", breed: "Labrador")`. Body, in order:
1. `sign_in_via_form(owner)` → `visit dogs_path` → `click_on "Walk my dog"` → `assert_text "Walk requested for #{dog.name}."`
2. `click_on "Sign out"` → `sign_in_via_form(walker)`
3. `visit open_requests_path` → `assert_text dog.name` → `click_button "Accept"` → `assert_text "You accepted the walk for #{dog.name}."`
4. `visit walker_walks_path` → `assert_text "Accepted"` (state badge)
5. `click_on "Start walk"` → `assert_text "Walk started — you're on your way!"` → `assert_text "In progress"` (state badge)
6. `accept_confirm { click_on "End walk" }` → `assert_text "Walk completed. Well done!"`

### Success Criteria:

#### Automated Verification:

- [ ] 1.1 `docker compose exec web bin/rails test:system` passes, including the new test
- [ ] 1.2 `docker compose exec web bundle exec rubocop` passes on the new file
- [ ] 1.3 `docker compose exec web bin/rails test test/system/full_walk_lifecycle_test.rb` run in isolation passes (proves it's independently runnable, not order-dependent on the other system tests)

#### Manual Verification:

- [ ] 1.4 Deliberate-break check: temporarily hardcode `Walk#start!` to always `return false`, re-run the new test, confirm it goes red on the `"Walk started — you're on your way!"` assertion, then revert and confirm green again
- [ ] 1.5 Visually confirm in a local run (`docker compose exec web bin/rails test:system`) that the test isn't flaky across 3 consecutive runs

---

## Testing Strategy

### Unit Tests:

- None added — this plan is browser-level-only; the state machine (`Walk#accept!`/`start!`/`complete!`) already has model/integration coverage from S-05/S-07.

### Integration Tests:

- None added — existing integration coverage already proves the HTTP contract for each transition.

### Manual Testing Steps:

1. Run `docker compose exec web bin/rails test:system` locally and confirm all four system tests pass (smoke, owner-creates, walker-accepts, owner-cancels, full-lifecycle).
2. Perform the deliberate-break check (item 1.4) on `Walk#start!` to prove the new test actually protects the middle of the chain.
3. Re-run the full system-test suite 3 consecutive times to rule out flakiness before considering the phase done — this is the highest flake-risk test in the batch per the roadmap.

## Performance Considerations

None — this is a test-only change; no production code paths are added or altered (aside from the deliberate, reverted break used for verification).

## Migration Notes

None — no schema or data changes.

## References

- Roadmap: `context/foundation/roadmap.md` — T-04 (`e2e-full-walk-lifecycle`)
- Prior infra + pattern: `context/archive/2026-07-08-e2e-system-tests/plan.md`, `context/archive/2026-07-13-e2e-walker-accepts-request/plan.md`, `context/archive/2026-07-13-e2e-owner-cancels-request/plan.md`
- Existing system tests: `test/system/smoke_test.rb`, `test/system/owner_creates_walk_request_test.rb`, `test/system/walker_accepts_request_test.rb`, `test/system/owner_cancels_request_test.rb`
- Features under test: `context/archive/2026-06-16-owner-creates-walk-request/` (S-04), `context/archive/2026-06-17-walker-accepts-request/` (S-05), `context/archive/2026-06-22-walker-starts-and-completes-walk/` (S-07)
- Test strategy context: `context/foundation/test-plan.md`

## Progress

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles. See `references/progress-format.md`.

### Phase 1: Add the full-walk-lifecycle system test

#### Automated

- [x] 1.1 `docker compose exec web bin/rails test:system` passes, including the new test — a64a1ef
- [x] 1.2 `docker compose exec web bundle exec rubocop` passes on the new file — a64a1ef
- [x] 1.3 New test passes when run in isolation — a64a1ef

#### Manual

- [x] 1.4 Deliberate-break check on `Walk#start!` — a64a1ef
- [x] 1.5 Re-run 3 times locally to rule out flakiness — a64a1ef
