# Owner Cancels a Requested Walk — E2E System Test Implementation Plan

## Overview

Add a third real-flow browser-level system test (Rails System Tests, Capybara + Selenium — infra from T-01, sign-in helper from T-02) proving an Owner can sign in through the real form, create a walk request, cancel it while still REQUESTED, and see it reflected in their walk history. Roadmap item **T-03**.

Unlike T-02, no infra work is needed: `test/support/system_sign_in_helper.rb` already exists and is already wired into `ApplicationSystemTestCase`. This plan is a single phase — one new test file.

## Current State Analysis

- `test/application_system_test_case.rb` already `include`s `SystemSignInHelper` (wired by T-02); `sign_in_via_form(user, password: "secret123")` is available to every system test with no further setup.
- `test/system/owner_creates_walk_request_test.rb` (T-01) already drives the walk-request creation flow: `visit dogs_path` → `click_on "Walk my dog"` → asserts `"Walk requested for #{dog.name}."` and `dog.name`. `WalksController#create` redirects to `walks_path` on success, so the test lands directly on the page this plan's cancel step continues from.
- `WalksController#cancel` (`app/controllers/walks_controller.rb:13`): scopes to `current_user.owned_walks.find(params[:id])`, calls `walk.cancel!(current_user)`. On success, redirects to `walks_path` with `notice: "Walk request cancelled."`; on failure, `alert: "This walk can no longer be cancelled."`.
- `app/views/walks/index.html.erb` renders two tables on one page: **Active** (REQUESTED/ACCEPTED/IN_PROGRESS, with a `button_to "Cancel", cancel_walk_path(walk)` + `turbo_confirm: "Cancel this walk request?"` for REQUESTED rows) and **Past** (COMPLETED/CANCELLED, with `walk.state.humanize` as the badge text and `cancelled_at`/`completed_at` as the timestamp). This single page *is* the Owner's walk history (confirmed against the archived S-08 plan) — "sees it reflected in history" means the walk moves from the Active table to the Past table with a "Cancelled" badge, on the same `walks_path` load after the redirect.
- `Walk#cancel!` (`app/models/walk.rb:70`) is a `swap_state(from: "requested", to: "cancelled", ...)` guard — already proven at the model/integration layer (S-06's archived coverage, `test-plan.md` §6.2). The post-accept restriction (Cancel button gone once ACCEPTED) is out of scope for this browser-level test per the roadmap's own risk note ("no concurrency angle at browser layer").
- No fixtures (YAML) anywhere in this suite — test data built inline via `User.create!` / `owner.dogs.create!`, matching every existing system test.

## Desired End State

A new `test/system/owner_cancels_request_test.rb` passes against the real app: an Owner signs in, creates a walk request through the real UI, cancels it, and the page reflects the cancellation — verified via a deliberate-break check during implementation (see Phase 1, Manual Verification).

### Key Discoveries:

- `dogs/index.html.erb:30`: the walk-request creation trigger is `button_to "Walk my dog", walks_path, params: { dog_id: dog.id }` — already exercised by the existing `owner_creates_walk_request_test.rb`, reusable verbatim here.
- `walks/index.html.erb`'s Cancel button carries `data: { turbo_confirm: "Cancel this walk request?" }` — Capybara's Rails system test driver (Selenium) auto-accepts `confirm()` dialogs by default, so no extra handling is needed for this to work in a real browser.
- Single persona (Owner only) — no Walker fixture needed, unlike T-02.

## What We're NOT Doing

- Not testing the post-accept restriction (Cancel button absent once ACCEPTED) at the browser layer — already proven at the model layer via `Walk#cancel!`'s `swap_state(from: "requested", ...)` guard (S-06 archived coverage); this test stays REQUESTED-only, per T-03's roadmap risk note.
- Not adding a second walk/dog to the fixture — one dog/one walk is enough to prove both the Active→Past move and the cancelled badge.
- Not extracting or modifying `test/support/system_sign_in_helper.rb` — already done by T-02.
- Not touching CI, Gemfile, or Dockerfile.dev — all system-test infra already exists from T-01.

## Implementation Approach

Single phase: one new test file that chains the already-proven creation flow (from `owner_creates_walk_request_test.rb`) with the new cancel assertion, using the shared sign-in helper. No shared code needs extracting since this is a single-persona test with no duplication risk yet.

## Phase 1: Add the owner-cancels-request system test

### Overview

Add the new test file proving the Owner-cancels-a-requested-walk flow through the browser: sign in, create a request, cancel it, see it move to history as Cancelled.

### Changes Required:

#### 1. New system test

**File**: `test/system/owner_cancels_request_test.rb`

**Intent**: Drive the full happy-path flow: an Owner signs in, creates a walk request for their dog, cancels it while REQUESTED, and sees the confirmation plus the walk reflected as Cancelled in the Past section of the same page.

**Contract**: One `test` inside a class extending `ApplicationSystemTestCase`. Setup: `owner = User.create!(...)` (role `"owner"`, city `"Kraków"`, postcode `"30-001"` — same literals as the existing system tests), `dog = owner.dogs.create!(name: "Rex", breed: "Labrador")`. Body: `sign_in_via_form(owner)` → `visit dogs_path` → `click_on "Walk my dog"` → `assert_text "Walk requested for #{dog.name}."` (lands on `walks_path`) → `click_on "Cancel"` (accepts the `turbo_confirm` dialog automatically under Selenium) → `assert_text "Walk request cancelled."` → assert the dog's row no longer renders a Cancel button (e.g. `assert_no_button "Cancel"`) → assert `"Cancelled"` appears as the state badge text on the page (Past section).

### Success Criteria:

#### Automated Verification:

- [ ] 1.1 `docker compose exec web bin/rails test:system` passes, including the new test
- [ ] 1.2 `docker compose exec web bundle exec rubocop` passes on the new file
- [ ] 1.3 `docker compose exec web bin/rails test:system test/system/owner_cancels_request_test.rb` run in isolation passes (proves it's independently runnable, not order-dependent on the other system tests)

#### Manual Verification:

- [ ] 1.4 Deliberate-break check: temporarily hardcode `Walk#cancel!` to always `return false`, re-run the new test, confirm it goes red on the `"Walk request cancelled."` assertion, then revert and confirm green again
- [ ] 1.5 Visually confirm in a local run (`docker compose exec web bin/rails test:system`) that the test isn't flaky across 2-3 consecutive runs

---

## Testing Strategy

### Unit Tests:

- None added — this plan is browser-level-only; the state machine (`Walk#cancel!`) already has model/integration coverage from S-06.

### Integration Tests:

- None added — S-06's existing integration coverage already proves the HTTP contract and state-guard for cancellation.

### Manual Testing Steps:

1. Run `docker compose exec web bin/rails test:system` locally and confirm all three system tests pass (smoke, owner-creates, walker-accepts, owner-cancels).
2. Perform the deliberate-break check (item 1.4) to prove the new test actually protects the cancel flow.
3. Re-run the full system-test suite 2-3 times to rule out flakiness before considering the phase done.

## Performance Considerations

None — this is a test-only change; no production code paths are added or altered (aside from the deliberate, reverted break used for verification).

## Migration Notes

None — no schema or data changes.

## References

- Roadmap: `context/foundation/roadmap.md` — T-03 (`e2e-owner-cancels-request`)
- Prior infra + pattern: `context/archive/2026-07-08-e2e-system-tests/plan.md`, `context/archive/2026-07-13-e2e-walker-accepts-request/plan.md`
- Existing system tests: `test/system/smoke_test.rb`, `test/system/owner_creates_walk_request_test.rb`, `test/system/walker_accepts_request_test.rb`
- Feature under test: `context/archive/2026-06-19-owner-cancels-requested-walk/` (S-06)
- History page this test asserts against: `context/archive/2026-06-23-owner-walk-history/` (S-08)
- Test strategy context: `context/foundation/test-plan.md` §6.2

## Progress

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles. See `references/progress-format.md`.

### Phase 1: Add the owner-cancels-request system test

#### Automated

- [x] 1.1 `docker compose exec web bin/rails test:system` passes, including the new test — 25d7e14
- [x] 1.2 `docker compose exec web bundle exec rubocop` passes on the new file — 25d7e14
- [x] 1.3 New test passes when run in isolation — 25d7e14

#### Manual

- [x] 1.4 Deliberate-break check on `Walk#cancel!` — 25d7e14
- [x] 1.5 Re-run 2-3 times locally to rule out flakiness — 25d7e14
