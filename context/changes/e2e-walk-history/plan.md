# Owner and Walker Walk History — E2E System Test Implementation Plan

## Overview

Add a fifth real-flow browser-level system test (Rails System Tests, Capybara + Selenium — infra from T-01, sign-in helper from T-02) proving both walk-history views render correctly: an Owner signs in and sees a completed walk in their `walks_path` Past section with the walker's name; a Walker signs in and sees the same completed walk in their `walker_walks_path` history section with the owner's name. Roadmap item **T-05**.

Like T-02/T-03/T-04, no infra work is needed. This plan is a single phase — one new test file with two independent test methods.

## Current State Analysis

- `WalksController#index` (`app/controllers/walks_controller.rb:4-9`) assigns `@active_walks` and `@past_walks` (state `completed`/`cancelled`, `.limit(50)`, eager-loads `:dog, :accepted_by_walker`).
- `app/views/walks/index.html.erb` renders `@past_walks` in a "Past" table: dog name, state badge (`walk_state_badge_classes` + `state.humanize`), terminal timestamp (`completed_at` or `cancelled_at`), and — only when `walk.completed?` — `walk.accepted_by_walker.display_label` in the "Walked by" column. Empty state: `"No past walks yet."`
- `WalkerWalksController#index` (`app/controllers/walker_walks_controller.rb:4-14`) assigns `@walk` (current active walk, if any) and `@past_walks` (scoped to `accepted_by_walker_id: current_user.id`, state `completed`/`cancelled`, `.limit(50)`, eager-loads `:dog, :owner`).
- `app/views/walker_walks/index.html.erb` renders a "Walk history" table below the active-walk block: dog name, state badge, terminal timestamp, and `past.owner&.display_label`. Empty state: `"No past walks yet."`
- Both views and controllers are unchanged from their originating slices (S-08 `context/archive/2026-06-23-owner-walk-history/`, S-09 `context/archive/2026-06-23-walker-walk-history/`) — confirmed by re-reading current source against those archived plans.
- Established fixture convention for reaching a terminal walk state (from `test/integration/walks_test.rb:104-130` and `test/integration/walker_walks_test.rb:98-118`): call the model's bang methods directly in test setup — `walk.accept!(walker)` → `walk.start!(walker)` → `walk.complete!(walker)` — rather than driving the UI transition path. T-04 already proved the full UI lifecycle end-to-end and explicitly scoped this test out of its own coverage ("Not asserting the Owner's side after completion... that's T-05's scope").
- `sign_in_via_form(user, password:)` (`test/support/system_sign_in_helper.rb`) is available on every `ApplicationSystemTestCase` via T-02.
- No fixtures (YAML) anywhere in this suite — test data built inline via `User.create!` / `owner.dogs.create!`, matching every existing system test.

## Desired End State

A new `test/system/walk_history_test.rb` passes against the real app with two tests: one signs in as an Owner and confirms a completed walk appears in the Past section of `walks_path` with the walker's name; the other signs in as a Walker and confirms the same completed walk appears in the history section of `walker_walks_path` with the owner's name. Both tests also confirm the `"No past walks yet."` empty state renders when no past walks exist. A deliberate-break check on the view's past-section rendering confirms both tests actually fail when the rendering breaks.

### Key Discoveries:

- Both target views are confirmed unchanged from S-08/S-09 (see Current State Analysis) — no production code needs to change for this test to be meaningful.
- The "Walked by" / owner-name column only ever prints for `walk.completed?` — a CANCELLED walk never shows the other party's name in either view. This test only exercises the COMPLETED path (per the scenario-depth decision below), so this nuance doesn't need special handling here, but it's why an empty-state assertion needs a *separate* user/walk with nothing completed rather than reusing the same fixture.
- `walk_state_badge_classes` (`app/helpers/application_helper.rb:2`) is a pure CSS-class helper — the visible text asserted on is `state.humanize` ("Completed"), not the badge classes.

## What We're NOT Doing

- Not adding a CANCELLED-walk case — T-03 already proves Owner+Cancelled at the browser layer, and both roles' cancelled-state rendering is proven at the integration layer (`test-plan.md` §2).
- Not re-proving cross-account isolation at the browser layer — already proven at the integration layer (`test-plan.md` §2 Risk #3) per T-05's own roadmap risk note.
- Not driving the UI transition path (create → accept → start → complete) to build fixtures — that's T-04's proven coverage; this test builds terminal-state walks directly via model bang! calls, matching existing integration-test convention.
- Not splitting this into two separate test files — both assertions serve one roadmap outcome (T-05) and share no state, so one file with two independent tests is a single logical unit, not two artifacts.
- Not touching CI, Gemfile, Dockerfile.dev, or `test/support/system_sign_in_helper.rb` — all infra already exists from T-01/T-02.
- Not modifying `app/controllers/walks_controller.rb`, `app/controllers/walker_walks_controller.rb`, or either view — this is a test-only addition; the view edits used for the deliberate-break check are temporary and reverted before the phase is considered done.

## Implementation Approach

Single phase: one new test file with two independent test methods (Owner history, Walker history), each building its own completed-walk fixture via model bang! calls, then signing in through the real form and asserting on the rendered history section. A third-user, no-past-walks fixture in each test proves the empty state renders correctly.

## Phase 1: Add the walk-history system test

### Overview

Add the new test file proving both history views render correctly: a completed walk shows with the other party's name in the Past/history section, and the empty state shows when there are no past walks.

### Changes Required:

#### 1. New system test

**File**: `test/system/walk_history_test.rb`

**Intent**: Prove the Owner's `walks_path` Past section and the Walker's `walker_walks_path` history section each render a completed walk with the correct counterpart name and terminal state, and each show the empty-state message when there are no past walks.

**Contract**: One file, two tests, both extending `ApplicationSystemTestCase`.

Test 1 — `"owner sees a completed walk in their walk history"`:
- Setup: `owner = User.create!(role: "owner", city: "Kraków", postcode: "30-001", ...)`, `walker = User.create!(role: "walker", same city/postcode, ...)`, `dog = owner.dogs.create!(name: "Rex", breed: "Labrador")`, `walk = dog.walks.create!(owner: owner, city: owner.city, postcode: owner.postcode)`, then `walk.accept!(walker); walk.start!(walker); walk.complete!(walker)`.
- Body: `sign_in_via_form(owner)` → `visit walks_path` → assert `"Rex"`, `"Completed"`, and the walker's `display_label` all appear in the Past section; assert `"No past walks yet."` is absent.
- Empty-state sub-case: a second Owner with no walks at all — `sign_in_via_form` that owner (or reuse the session via sign-out/sign-in) → `visit walks_path` → assert `"No past walks yet."` appears.

Test 2 — `"walker sees a completed walk in their walk history"`:
- Setup: mirrors Test 1's fixture (owner, walker, dog, walk taken through `accept!`/`start!`/`complete!`).
- Body: `sign_in_via_form(walker)` → `visit walker_walks_path` → assert `"Rex"`, `"Completed"`, and the owner's `display_label` all appear in the history section; assert `"No past walks yet."` is absent.
- Empty-state sub-case: a second Walker with no completed walks — sign in as that walker → `visit walker_walks_path` → assert `"No past walks yet."` appears.

Each test builds its own fixtures independently (no shared `setup` block reused across the two tests) so the two tests remain independently runnable, matching this suite's existing test-independence convention.

### Success Criteria:

#### Automated Verification:

- `docker compose exec web bin/rails test:system` passes, including both new tests
- `docker compose exec web bundle exec rubocop` passes on the new file
- `docker compose exec web bin/rails test test/system/walk_history_test.rb` run in isolation passes (proves independence from the other system tests)

#### Manual Verification:

- Deliberate-break check: temporarily force the Past/history section's rendering condition to always take the empty-state branch in both `app/views/walks/index.html.erb` and `app/views/walker_walks/index.html.erb` (e.g. change `<% if @past_walks.any? %>` to `<% if false %>` in each), re-run the new test file, confirm both tests fail on the dog-name/state assertions, then revert both view edits and confirm green again
- Visually confirm in a local run (`docker compose exec web bin/rails test:system`) that the test isn't flaky across 3 consecutive runs

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase. Phase blocks use plain bullets — the corresponding `- [ ]` checkboxes for these items live in the `## Progress` section at the bottom of the plan.

---

## Testing Strategy

### Unit Tests:

- None added — no model/business-logic changes.

### Integration Tests:

- None added — existing `test/integration/walks_test.rb` and `test/integration/walker_walks_test.rb` coverage already proves the HTTP-level rendering contract; this plan adds the browser-level equivalent per T-05's roadmap scope.

### Manual Testing Steps:

1. Run `docker compose exec web bin/rails test:system` locally and confirm all system tests pass (smoke, owner-creates, walker-accepts, owner-cancels, full-lifecycle, walk-history).
2. Perform the deliberate-break check on both views' past-section rendering to prove the new tests actually protect what they claim to.
3. Re-run the new test file 3 consecutive times to rule out flakiness.

## Performance Considerations

None — this is a test-only change; no production code paths are added or altered (aside from the deliberate, reverted break used for verification).

## Migration Notes

None — no schema or data changes.

## References

- Roadmap: `context/foundation/roadmap.md` — T-05 (`e2e-walk-history`)
- Prior infra + pattern: `context/archive/2026-07-08-e2e-system-tests/plan.md`, `context/archive/2026-07-13-e2e-full-walk-lifecycle/plan.md`
- Existing system tests: `test/system/smoke_test.rb`, `test/system/owner_creates_walk_request_test.rb`, `test/system/walker_accepts_request_test.rb`, `test/system/owner_cancels_request_test.rb`, `test/system/full_walk_lifecycle_test.rb`
- Features under test: `context/archive/2026-06-23-owner-walk-history/` (S-08), `context/archive/2026-06-23-walker-walk-history/` (S-09)
- Fixture convention precedent: `test/integration/walks_test.rb:104-130`, `test/integration/walker_walks_test.rb:98-118`
- Test strategy context: `context/foundation/test-plan.md`

## Progress

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles. See `references/progress-format.md`.

### Phase 1: Add the walk-history system test

#### Automated

- [x] 1.1 `docker compose exec web bin/rails test:system` passes, including both new tests
- [x] 1.2 `docker compose exec web bundle exec rubocop` passes on the new file
- [x] 1.3 New test file passes when run in isolation

#### Manual

- [ ] 1.4 Deliberate-break check on both views' past-section rendering, then revert
- [ ] 1.5 Re-run 3 times locally to rule out flakiness
