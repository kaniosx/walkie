# Walker Accepts an Open Request — E2E System Test Implementation Plan

## Overview

Add a second real-flow browser-level system test (Rails System Tests, Capybara + Selenium — the infra `e2e-system-tests`/T-01 wired up) proving a Walker can sign in through the real form, see an open walk request in the open-requests list, click "Accept", and see the flash confirmation plus the request disappear from the list. Roadmap item **T-02**.

Because this will be the second system test repeating the exact sign-in-via-form sequence (and T-03/T-04/T-05 are queued right behind it per the roadmap), this plan also extracts that sequence into a shared helper and retrofits the existing `owner_creates_walk_request_test.rb` to use it, so the convention doesn't fork between "old inline" and "new via helper."

## Current State Analysis

- `test/application_system_test_case.rb` configures Selenium headless Chrome (`--no-sandbox --disable-dev-shm-usage`, screen `[1400, 1400]`) and nothing else — no shared helpers included.
- `test/system/smoke_test.rb` and `test/system/owner_creates_walk_request_test.rb` are the only two system tests (T-01's self-imposed cap of exactly two). The latter inlines its sign-in sequence directly in the test method.
- The Walker-accepts-request flow (S-05) is fully implemented and already covered at the integration layer (`test/integration/open_requests_test.rb`) — including the concurrency race and role-gating cases. This plan adds only the browser-level layer on top of an already-proven state machine.
- `bin/rails test:system` already runs in CI (`.github/workflows/ci.yml`, added by T-01) — no CI changes needed here.

## Desired End State

A new `test/system/walker_accepts_request_test.rb` passes against the real app, driving the actual "Accept" button through a rendered page, and would fail if the accept action stopped working (verified via a deliberate-break check during implementation). A new `test/support/system_sign_in_helper.rb` is used by both this test and the existing `owner_creates_walk_request_test.rb`.

### Key Discoveries:

- `OpenRequestsController#accept` (`app/controllers/open_requests_controller.rb`): on success redirects to `open_requests_path` with `notice: "You accepted the walk for #{walk.dog.name}."`; on race loss, `alert: "Sorry, that walk was just accepted by someone else."`.
- The "Accept" control is a `button_to "Accept", accept_open_request_path(walk), ...` (`app/views/open_requests/index.html.erb`) — a plain POST form, label text exactly `"Accept"`.
- Empty-state copy when the list is empty: `"No open walk requests in #{current_user.city} right now."` (same view).
- `Walk.open_in_locality(city, postcode)` (`app/models/walk.rb`) matches **exact** city + postcode — the Owner's walk and the Walker's own `city`/`postcode` fields must be identical strings, or the fixture walk never appears in the Walker's list.
- Established system-test sign-in pattern (`test/system/owner_creates_walk_request_test.rb`): drive the real form (`visit new_session_path` → `fill_in` → `click_button "Sign in"`), then `assert_text "Sign out"` before navigating further — Capybara's auto-waiting needs that explicit wait for the authenticated redirect.
- No fixtures (YAML) are used anywhere in this test suite — all test data is built inline via `User.create!` / `owner.dogs.create!` / `dog.walks.create!`, matching `test/integration/open_requests_test.rb`'s existing convention.
- `test/system/*.rb` files `require "application_system_test_case"` with no path prefix — Rails' test runner (`bin/rails test`) puts `test/` on `$LOAD_PATH`, so a new `test/support/system_sign_in_helper.rb` can be required the same way (`require "support/system_sign_in_helper"`).

## What We're NOT Doing

- Not testing the concurrency race ("already accepted by someone else") at the browser layer — already proven at the integration + model layers (`test-plan.md` §2 Risk #1); this test stays happy-path only.
- Not asserting the post-accept state on `walker_walks_path` (the Walker's "My walk" page) — this test stops at the open-requests list side of the flow, per T-02's roadmap outcome.
- Not adding a second open request to the fixture — a single open request is enough to prove both "it's gone" (via the empty-state text) and the flow itself.
- Not touching CI, Gemfile, or Dockerfile.dev — all system-test infra already exists from T-01.

## Implementation Approach

Two phases: first extract and retrofit the shared sign-in helper (touches only the existing passing test — no new test coverage yet, but keeps risk isolated from the new test), then add the new test itself. This mirrors T-01's own phasing discipline (isolate infra changes from flow-logic changes).

## Critical Implementation Details

- **Load path for the new helper**: `test/support/system_sign_in_helper.rb` must be required as `require "support/system_sign_in_helper"` (relative to `test/`, no leading `test/`) — consistent with how `test/system/*.rb` already require `application_system_test_case` without a path prefix. Requiring it with a different relative path (e.g. `"./support/..."`) will fail under `bin/rails test:system`.
- **Locality fixture gotcha**: `Walk.open_in_locality` matches city and postcode as exact strings against `current_user.city`/`current_user.postcode`. The Owner's dog/walk and the Walker's own user record must use the identical city/postcode values (e.g. both `"Kraków"` / `"30-001"`) or the fixture walk silently never appears in the list — the test would then fail on the "sees an open request" assertion, not on the accept step, which can be confusing to debug.

## Phase 1: Extract shared sign-in helper

### Overview

Create a small helper module for the Capybara real-form sign-in sequence and have both the existing and new system tests use it, so the pattern is established once before it's the third or fourth copy.

### Changes Required:

#### 1. New sign-in helper module

**File**: `test/support/system_sign_in_helper.rb`

**Intent**: Encapsulate the "visit sign-in page, fill in credentials, submit, wait for authenticated redirect" sequence that both system tests need, as a single reusable method.

**Contract**: A module `SystemSignInHelper` with one instance method `sign_in_via_form(user, password: "secret123")` that performs the same `visit`/`fill_in`/`click_button`/`assert_text "Sign out"` sequence currently inlined in `owner_creates_walk_request_test.rb`, parameterized on the `user` (reads `user.email_address`) and an overridable `password` (default `"secret123"`, matching every existing test's fixture password).

#### 2. Wire the helper into the system test base class

**File**: `test/application_system_test_case.rb`

**Intent**: Make `sign_in_via_form` available to every system test without per-file `include` boilerplate.

**Contract**: `require "support/system_sign_in_helper"` at the top, and `include SystemSignInHelper` inside the `ApplicationSystemTestCase` class body, alongside the existing `driven_by` config.

#### 3. Retrofit the existing system test

**File**: `test/system/owner_creates_walk_request_test.rb`

**Intent**: Replace the inlined sign-in block with a call to the new helper — no behavior change, this only proves the extraction is behavior-preserving before the new test relies on it.

**Contract**: Replace the four-line `visit new_session_path` … `assert_text "Sign out"` block with `sign_in_via_form(owner)`. Everything else in the test (dog creation, `visit dogs_path`, `click_on "Walk my dog"`, assertions) stays unchanged.

### Success Criteria:

#### Automated Verification:

- [ ] 1.1 `docker compose exec web bin/rails test:system` passes (both existing system tests green)
- [ ] 1.2 `docker compose exec web bundle exec rubocop` passes on the new and changed files

#### Manual Verification:

- [ ] 1.3 Confirm `owner_creates_walk_request_test.rb` still exercises the real sign-in form end-to-end (no behavior silently changed by the extraction — e.g. temporarily misspell `password` default and confirm the existing test goes red before reverting)

---

## Phase 2: Add the walker-accepts-request system test

### Overview

Add the new test file proving the Walker-accepts-an-open-request flow through the browser, using the Phase 1 helper.

### Changes Required:

#### 1. New system test

**File**: `test/system/walker_accepts_request_test.rb`

**Intent**: Drive the full happy-path flow: an Owner with an open walk request in a given city/postcode, and a Walker in the same locality, signs in as the Walker, sees the request, accepts it, and sees the confirmation.

**Contract**: One `test` inside a class extending `ApplicationSystemTestCase`. Setup: `owner = User.create!(...)` (role `"owner"`, city/postcode e.g. `"Kraków"`/`"30-001"`), `walker = User.create!(...)` (role `"walker"`, same city/postcode), `dog = owner.dogs.create!(name:, breed:)`, `dog.walks.create!(owner:, city:, postcode:)` — same field values as `owner`'s. Body: `sign_in_via_form(walker)` → `visit open_requests_path` → `assert_text dog.name` → `click_button "Accept"` → `assert_text "You accepted the walk for #{dog.name}."` → `assert_text "No open walk requests in Kraków right now."` (using the literal city value from setup).

### Success Criteria:

#### Automated Verification:

- [ ] 2.1 `docker compose exec web bin/rails test:system` passes, including the new test
- [ ] 2.2 `docker compose exec web bundle exec rubocop` passes on the new file
- [ ] 2.3 `docker compose exec web bin/rails test:system test/system/walker_accepts_request_test.rb` run in isolation passes (proves it's independently runnable, not order-dependent on the other system test)

#### Manual Verification:

- [ ] 2.4 Deliberate-break check: temporarily change `OpenRequestsController#accept`'s success branch to always take the `else` (race-loss) path, re-run the new test, confirm it goes red on the `"You accepted the walk for..."` assertion, then revert the change and confirm green again
- [ ] 2.5 Visually confirm in a local run (`docker compose exec web bin/rails test:system`) that the test isn't flaky across 2-3 consecutive runs

---

## Testing Strategy

### Unit Tests:

- None added — this plan is browser-level-only; the state machine and role-gating logic already have model/integration coverage from S-05.

### Integration Tests:

- None added — `test/integration/open_requests_test.rb` already covers the HTTP contract, race, and role-gating cases for this flow.

### Manual Testing Steps:

1. Run `docker compose exec web bin/rails test:system` locally and confirm both the existing and new system tests pass.
2. Perform the Phase 2 deliberate-break check (item 2.4) to prove the new test actually protects the accept flow.
3. Re-run the full system-test suite 2-3 times to rule out flakiness before considering the phase done.

## Performance Considerations

None — this is a test-only change; no production code paths are added or altered (aside from the deliberate, reverted break used for verification).

## Migration Notes

None — no schema or data changes.

## References

- Roadmap: `context/foundation/roadmap.md` — T-02 (`e2e-walker-accepts-request`)
- Prior infra + pattern: `context/archive/2026-07-08-e2e-system-tests/plan.md`, `plan-brief.md`
- Existing system tests: `test/system/smoke_test.rb`, `test/system/owner_creates_walk_request_test.rb`
- Feature under test: `context/archive/2026-06-17-walker-accepts-request/` (S-05)
- Existing HTTP-layer coverage: `test/integration/open_requests_test.rb`
- Test strategy context: `context/foundation/test-plan.md` §2 Risk #1

## Progress

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles. See `references/progress-format.md`.

### Phase 1: Extract shared sign-in helper

#### Automated

- [x] 1.1 `docker compose exec web bin/rails test:system` passes (both existing system tests green) — 8394e36
- [x] 1.2 `docker compose exec web bundle exec rubocop` passes on the new and changed files — 8394e36

#### Manual

- [x] 1.3 Confirm the extraction is behavior-preserving (misspell-and-revert check on the helper's default password) — 8394e36

### Phase 2: Add the walker-accepts-request system test

#### Automated

- [x] 2.1 `docker compose exec web bin/rails test:system` passes, including the new test — 9036774
- [x] 2.2 `docker compose exec web bundle exec rubocop` passes on the new file — 9036774
- [x] 2.3 New test passes when run in isolation — 9036774

#### Manual

- [x] 2.4 Deliberate-break check on `OpenRequestsController#accept`'s success branch — 9036774
- [x] 2.5 Re-run 2-3 times locally to rule out flakiness — 9036774
