---
project: Walkie
version: 2
status: active
created: 2026-05-25
updated: 2026-07-08
decisions:
  q4_remove_dog_policy: soft-delete  # deleted_at on Dog; walks preserved
prd_version: 1
main_goal: market-feedback
top_blocker: none
---

# Roadmap: Walkie

> Derived from `context/foundation/prd.md` (v1) + auto-researched codebase baseline.
> Edit in place; archive when superseded.
> Items below are listed in dependency order. The "At a glance" table is the index.

## Vision recap

Walkie fills the gap of "my dog needs a walk RIGHT NOW" — existing channels (asking friends, Facebook groups, Rover-like platforms) are built for advance booking, not for the unplanned "now". The product bets that the supply of casual walkers already exists; what's missing is the "I'm free this hour" signal made visible to nearby owners.

The product wedge — the single trait whose removal would strip Walkie of its reason to exist — is the direct short circuit: an Owner posts a request, any available Walker in the same locale can claim it instantly, with no out-of-app coordination and no pre-onboarding between the two sides. Everything else (sign-up, profiles, dog list, history) is scaffolding around that central binding.

## North star

**S-05: Walker accepts an open request (transition to ACCEPTED)** — this is the slice that put the PRD's central hypothesis ("the gap isn't supply, it's the 'available right now' signal") in front of real users. **Delivered** (archived 2026-06-17).

> *North star* in this document means: the smallest end-to-end slice whose successful delivery proves the product's core hypothesis works — placed as early as its Prerequisites allow, because everything else only matters once it works. The validation milestone — the event at which we test whether the hypothesis holds — lands at the first real-user acceptance of a request by a Walker.

PRD §Business Logic §Singleness states: *"the binding IS the confirmation"*. S-05 produced that binding. The full lifecycle (S-07 start/complete) rounded out the flow but did not move the moment of truth.

## At a glance

| ID    | Change ID                          | Outcome (user can …)                                              | Prerequisites             | PRD refs                | Status   |
| ----- | ---------------------------------- | ----------------------------------------------------------------- | ------------------------- | ----------------------- | -------- |
| F-01  | auth-and-role-typing               | (foundation) Rails 8 auth + role column on User                   | —                         | FR-001..004, §Access    | done     |
| F-02  | domain-schema-walks-and-dogs       | (foundation) Dog + Walk schema + state machine + constraints      | F-01                      | NFR (Singleness, role)  | done     |
| F-03  | test-infrastructure-scaffold       | (foundation) `test/` dir + coverage tooling baseline              | —                         | §Guardrails (80%)       | done     |
| S-01  | signup-and-signin-with-role        | Visitor signs up as Owner or Walker, signs in, signs out          | F-01                      | FR-001, 002, 003, 004   | done     |
| S-02  | profile-with-city                  | Signed-in user views + edits profile (display name + city)        | S-01                      | FR-005                  | done     |
| S-03  | owner-manages-dog                  | Owner adds + edits their own dog                                  | S-01, F-02                | FR-006, 007, US-01      | done     |
| S-04  | owner-creates-walk-request         | Owner creates a walk request (REQUESTED), sees it in history      | S-01, S-02, S-03, F-02    | FR-009, US-01           | done     |
| S-05  | walker-accepts-request             | Walker sees open list + accepts (REQ→ACCEPTED)                    | S-01, S-02, S-04, F-02    | FR-011, 012, US-02      | done     |
| S-06  | owner-cancels-requested-walk       | Owner cancels their request while still in REQUESTED              | S-04                      | FR-010                  | done     |
| S-07  | walker-starts-and-completes-walk   | Walker starts (ACC→IP) + ends walk (IP→COMPLETED)                 | S-05                      | FR-013, 014, US-03      | done     |
| S-08  | owner-walk-history                 | Owner sees their own walk history                                 | S-04                      | FR-015                  | done     |
| S-09  | walker-walk-history                | Walker sees their own walk history                                | S-05                      | FR-016                  | done     |
| S-10  | owner-removes-dog                  | Owner removes their own dog (soft-delete; history preserved)      | S-03                      | FR-008                  | done     |
| U-01  | tailwind-setup                     | (foundation) Tailwind CSS + design tokens wired into Propshaft    | S-01                      | §NFR (usability)        | done     |
| U-02  | ui-layout-and-nav                  | Responsive layout shell + role-aware navbar + flash messages      | U-01                      | FR-001..004 (UX)        | done     |
| U-03  | ui-auth-and-profile                | Sign-in, sign-up, profile edit screens styled                     | U-01, U-02                | FR-001..005             | done     |
| U-04  | ui-owner-dashboard                 | Dog cards, walk-request form, owner walk-history screen styled    | U-01, U-02                | FR-006..010, FR-015     | done     |
| U-05  | ui-walker-dashboard                | Open-requests list, accept/start/complete cards, history styled   | U-01, U-02                | FR-011..014, FR-016     | done     |
| O-01  | sentry-integration                 | (infra) Sentry SDK wired; exceptions + performance traces to Sentry | —                        | §NFR (observability)    | proposed |
| T-01  | e2e-system-tests                   | (infra) Rails System Tests (Capybara + Selenium) wired into Docker + CI; first browser-level e2e test | — | (user-requested; not PRD-derived) | planned |

## Streams

Navigation aid — groups items sharing a Prerequisites chain. Canonical ordering still lives in the dependency graph in `## Foundations` + `## Slices`; this table is the proposed reading order across parallel tracks.

| Stream | Theme                              | Chain                                                                              | Note                                                                                                       |
| ------ | ---------------------------------- | ---------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| A      | Account lifecycle & foundations    | `F-01` / `F-03` → `S-01` → `S-02`                                                  | F-01 and F-03 are parallel. The fixed base for every other slice — without identity+role nothing makes sense. |
| B      | Owner journey                      | `F-02` → `S-03` → `S-04` → `S-06` / `S-08`; `S-10` (branches from `S-03`)          | Domain schema + Owner's path from adding a dog to posting and managing requests. S-10 ready (soft-delete decided 2026-07-06). |
| C      | Marketplace binding (north star)   | `S-05` → `S-07` → `S-09`                                                            | Joins Stream B at `S-04` (Walker needs something to accept). Validation milestone delivered at S-05.        |
| D      | UI/UX layer                        | `U-01` → `U-02` → `U-03` / `U-04` / `U-05`                                         | Tailwind + styled flows for auth, Owner, and Walker journeys. U-03/04/05 ran in parallel.                   |
| E      | Observability                      | `O-01`                                                                              | Independent of all feature slices — ready to run in parallel with any other work.                           |
| F      | Testing infrastructure             | `T-01`                                                                              | Independent of all feature slices — ready to run in parallel with any other work.                           |

## Baseline

What's already in the codebase as of 2026-07-06 (auto-researched + user-confirmed).
Foundations below assume these are present and do NOT re-scaffold them.

- **Frontend:** present — `tailwindcss-rails 3.3.1` wired with `config/tailwind.config.js`; full ERB view set covering auth, owner dashboard, walker dashboard, profiles (`app/views/sessions/`, `app/views/open_requests/`, `app/views/dogs/`, etc.)
- **Backend / API:** present — 10 controllers (`dogs`, `walks`, `open_requests`, `walker_walks`, `registrations`, `sessions`, `profiles`, `passwords`, `home`, `application`) + 3 concerns (`authentication`, `owner_only`, `walker_only`); full `config/routes.rb` with walk lifecycle actions (cancel, accept, start, complete)
- **Data:** present — 5 domain models (`User`, `Session`, `Dog`, `Walk`, `Current`) + `ApplicationRecord`; 7 migrations (create_users through add_details_to_dogs); `db/schema.rb` present
- **Auth:** present — Rails 8 authentication generated; `sessions_controller.rb`, `authentication` concern with `current_user`, `bcrypt ~> 3.1.7`; `role` enum on User
- **Deploy / infra:** present — Render Frankfurt + Docker; `walkie-web` live at `https://walkie-web.onrender.com`; Postgres **free tier** (expired 2026-06-24 — **12 days overdue**, see Open Q #3)
- **Observability:** absent — no `sentry-ruby` gem in Gemfile, no `config/initializers/sentry.rb`

## Foundations

### F-01: Rails 8 auth + role-typed accounts

- **Outcome:** (foundation) `User` model exists with hashed password (bcrypt), sessions controller handles sign-up/sign-in/sign-out, a `role` column (Owner | Walker) is chosen at registration. All internal hooks (`current_user`, `require_authentication`) are available.
- **Change ID:** `auth-and-role-typing`
- **PRD refs:** FR-001, FR-002, FR-003, FR-004, §Access Control (Role → capability matrix)
- **Unlocks:** S-01 (sign-up/sign-in UI), and transitively every other slice (each requires an authenticated user with role)
- **Prerequisites:** —
- **Parallel with:** F-03
- **Blockers:** —
- **Unknowns:** —
- **Risk:** If role typing is designed poorly (STI vs enum vs polymorphic), every later slice has to work around it. PRD §Access Control states "A user is one or the other" — dual-role is explicitly out of scope, so a simple `enum role: { owner: 0, walker: 1 }` or a typed column is sufficient.
- **Status:** done

### F-02: Domain data schema (Dog + Walk + state machine + constraints)

- **Outcome:** (foundation) Tables `dogs` (belongs_to User, basic fields) and `walks` (belongs_to Dog, has a `state` enum spanning REQUESTED/ACCEPTED/IN_PROGRESS/COMPLETED, nullable `accepted_by_walker_id`). DB-level constraints: check on linear state progression, partial unique index enforcing Singleness (one Walker per Walk once it leaves REQUESTED), foreign keys. Active Record validations + a transactional state-transition method (a test-able invariant).
- **Change ID:** `domain-schema-walks-and-dogs`
- **PRD refs:** §Business Logic (Singleness, Locality, Immediacy), §NFR (state machine invariant, role separation), FR-009..FR-014 (state transitions)
- **Unlocks:** S-03, S-04, S-05, S-07
- **Prerequisites:** F-01 (the User table must exist before `belongs_to :user` on Dog and `accepted_by_walker_id` on Walk make sense)
- **Parallel with:** —
- **Blockers:** —
- **Unknowns:** —
- **Risk:** The Singleness invariant must be enforced **in the DB**, not only in Active Record (PRD §Guardrails: "Both invariants are binding outside the UI, not advisory hints"). A concurrency test is load-bearing — the race is between HTTP requests, not model methods. F-02 leaves the DB-level constraint as the backstop.
- **Status:** done

### F-03: Test infrastructure scaffold

- **Outcome:** (foundation) `test/` directory exists (Minitest), `test/test_helper.rb` configured, a coverage tool (SimpleCov) installed and reporting. CI placeholder — runs tests + the coverage gate on push.
- **Change ID:** `test-infrastructure-scaffold`
- **PRD refs:** §Success Criteria §Guardrails (≥ 80% coverage on the 4 core flows)
- **Unlocks:** Verification path: the ≥ 80% coverage gate on every slice (S-01..S-09); without F-03 the Guardrail is not measurable.
- **Prerequisites:** —
- **Parallel with:** F-01
- **Blockers:** —
- **Unknowns:**
  - Do we wire up CI now (GitHub Actions matrix Ruby 3.4.9 + Postgres 17), or only the local-test loop? — Owner: user. Block: no (CI can be deferred; local tests are enough for skill-level validation in v1).
- **Risk:** CLAUDE.md tripwire: "No `test/` directory yet. Do not claim tests pass before the suite exists; generating models with `bin/rails g` will create the directory as a side effect." F-03 formalizes that side effect ahead of the first `bin/rails g`, so SimpleCov isn't bolted onto an existing suite later.
- **Status:** done

## Slices

### S-01: Sign-up + sign-in with role choice

- **Outcome:** Visitor signs up as Owner or Walker (email + password, role chosen at sign-up), signs in, signs out. The role choice is binding — a user is Owner XOR Walker (PRD §Access Control).
- **Change ID:** `signup-and-signin-with-role`
- **PRD refs:** FR-001, FR-002, FR-003, FR-004, §Access Control
- **Prerequisites:** F-01
- **Parallel with:** —
- **Blockers:** —
- **Unknowns:**
  - Is the role choice a radio on sign-up, or two separate pages (`/owners/sign_up` + `/walkers/sign_up`)? — Owner: user. Block: no (UX decision, both satisfy the PRD).
- **Risk:** The only slice where role typing surfaces in the UI. If F-01 types role as an enum, this slice must enforce a one-time role choice in the UI (no role switching post-signup per §Access Control).
- **Status:** done

### S-02: Profile with city / postcode

- **Outcome:** A signed-in user (Owner or Walker) sees their profile and can edit display name + city/postcode. The city/postcode field is required before the first FR that uses it (Owner request creation, Walker open-requests view).
- **Change ID:** `profile-with-city`
- **PRD refs:** FR-005, §Business Logic §Locality, §Open Q #6 (informational)
- **Prerequisites:** S-01
- **Parallel with:** F-02
- **Blockers:** —
- **Unknowns:**
  - Is city/postcode required at sign-up (gating S-01), or can it be empty until first use? — Owner: user. Block: no (both satisfy FR-005; required-at-signup simplifies later "is city set?" checks in S-04/S-05).
- **Risk:** Coarse city/postcode filtering (Open Q #6) is an accepted v1 limitation. This is the moment the field locks in — a later modelling change (geolocation) post-v1 will require a migration.
- **Status:** done

### S-03: Owner adds + edits a dog

- **Outcome:** A signed-in Owner can add a dog (name + basic details) to their account and edit its data. The dog is the entity the entire marketplace orbits around (PRD FR-006 Socratic note: "without it Walkie reduces to a generic gig list").
- **Change ID:** `owner-manages-dog`
- **PRD refs:** FR-006, FR-007, US-01 (Given: "Owner with at least one dog on their account")
- **Prerequisites:** S-01, F-02
- **Parallel with:** S-02
- **Blockers:** —
- **Unknowns:**
  - Which fields exactly count as "basic details"? Name is unambiguous; breed/weight/notes are open. — Owner: user. Block: no (defer to `/10x-plan owner-manages-dog`).
- **Risk:** PRD §FR-008 Socratic flag: "Removing a dog with past walks should keep history intact, not erase it." Edit (FR-007) doesn't carry that trap — only remove (S-10) does. S-03 is deliberately scoped to add+edit to avoid the blocking Open Q #4 inside this slice.
- **Status:** done

### S-04: Owner creates a walk request (US-01)

- **Outcome:** An Owner with at least one dog and a set city/postcode taps "Walk my dog" and creates a new walk request in REQUESTED state. The request is visible in their own history and (transitively, via S-05) visible to Walkers in the same city/postcode.
- **Change ID:** `owner-creates-walk-request`
- **PRD refs:** FR-009, US-01, §Acceptance Criteria (request invisible to other Owners; under-30s flow)
- **Prerequisites:** S-01, S-02, S-03, F-02
- **Parallel with:** —
- **Blockers:** —
- **Unknowns:**
  - PRD US-01 Acceptance: "under 30 seconds for a logged-in Owner with one dog." Do we measure that as a test (Capybara instrumentation), or as a manual smoke target? — Owner: user. Block: no (both are acceptable; manual smoke is go-simple consistent with `main_goal: market-feedback`).
- **Risk:** PRD §NFR "user-initiated action … within 2 seconds." Stock Rails + Postgres should fit, but the free Postgres cold start can blow this target on the first request after idle. Measure the NFR against paid Postgres (see Open Q #3).
- **Status:** done

### S-05: Walker accepts an open request (north star)

- **Outcome:** A signed-in Walker in a given city/postcode sees a filtered list of open requests. Tapping "Accept" on a request in REQUESTED state that they did not create themselves transitions it to ACCEPTED, binds it to that Walker, and removes it from every other Walker's list. Concurrency invariant: when two Walkers tap "Accept" near-simultaneously, exactly one succeeds; the other receives "already accepted".
- **Change ID:** `walker-accepts-request`
- **PRD refs:** FR-011, FR-012, US-02, §Business Logic §Singleness, §Guardrails (single-Walker race, role separation never leaks)
- **Prerequisites:** S-01, S-02, S-04, F-02
- **Parallel with:** —
- **Blockers:** —
- **Unknowns:**
  - Pessimistic locking (`SELECT FOR UPDATE`) vs optimistic (compare-and-swap on the state column) for the accept transition? — Owner: downstream `/10x-plan walker-accepts-request`. Block: no.
- **Risk:** **This was the moment of truth for the hypothesis** — now delivered. The concurrency test must be an integration test (race is between HTTP requests, not model methods). F-02 left the DB-level constraint as the backstop; S-05 verified it under load.
- **Status:** done

### S-06: Owner cancels a walk request in REQUESTED state

- **Outcome:** The Owner who created a request can cancel it while still in REQUESTED. After ACCEPTED — cancellation is unavailable in v1 (per the FR-010 Socratic note; Open Q #5 is post-v1).
- **Change ID:** `owner-cancels-requested-walk`
- **PRD refs:** FR-010, §Open Q #5 (informational, explicit post-v1)
- **Prerequisites:** S-04
- **Parallel with:** S-05, S-07, S-08
- **Blockers:** —
- **Unknowns:** —
- **Risk:** Small and contained. Edge case: race between a Walker accepting (S-05) and the Owner cancelling near-simultaneously. The PRD does not specify who wins — propose a deterministic rule at `/10x-plan` time (e.g., first-write on state wins, the second action receives "already moved").
- **Status:** done

### S-07: Walker starts + completes a walk (US-03)

- **Outcome:** A Walker who accepted a walk can start it ("Start walk", ACCEPTED → IN_PROGRESS) and end it ("End walk", IN_PROGRESS → COMPLETED). Only that specific Walker can advance state; no other Walker and no Owner may.
- **Change ID:** `walker-starts-and-completes-walk`
- **PRD refs:** FR-013, FR-014, US-03, §NFR (linear state machine, no skip/reverse), §Open Q #7 (informational, explicit post-v1)
- **Prerequisites:** S-05
- **Parallel with:** S-06, S-08
- **Blockers:** —
- **Unknowns:**
  - Are "Start walk" and "End walk" two separate screens / actions, or one "Active walk" screen with two buttons? — Owner: downstream `/10x-plan`. Block: no (UX detail).
- **Risk:** PRD §Open Q #7: no Owner-confirmation of completion. v1 trusts Walker self-report. The post-COMPLETED state is immutable — a Walker error (premature end) is irreversible. Mitigation: clear UI copy.
- **Status:** done

### S-08: Owner walk history

- **Outcome:** An Owner sees the list of their own past + current walks (every state including COMPLETED). PRD §NFR: "Any view rendered to a signed-in Owner contains no walk that the Owner did not create."
- **Change ID:** `owner-walk-history`
- **PRD refs:** FR-015, §NFR (role separation)
- **Prerequisites:** S-04
- **Parallel with:** S-05, S-06, S-07, S-09
- **Blockers:** —
- **Unknowns:** —
- **Risk:** Low. The scoping query must be binding (`Walk.where(owner: current_user)` enforced at the controller, not only in the view). Test must include "Owner B cannot see Owner A's walk" — a direct test for PRD §Guardrails "role separation never leaks".
- **Status:** done

### S-09: Walker walk history

- **Outcome:** A Walker sees the list of their own accepted + current + completed walks. The Walker does not see requests they did not accept (beyond the open-requests view from S-05).
- **Change ID:** `walker-walk-history`
- **PRD refs:** FR-016, §NFR (role separation)
- **Prerequisites:** S-05
- **Parallel with:** S-06, S-07, S-08
- **Blockers:** —
- **Unknowns:** —
- **Risk:** Symmetric to S-08. Scoping: `Walk.where(accepted_by_walker: current_user)` — never `Walk.where(walker_visible_to: current_user)` (the latter would leak other Walkers' open requests into "history").
- **Status:** done

### S-10: Owner removes their own dog

- **Outcome:** An Owner removes their own dog. Dog record is soft-deleted (`deleted_at` timestamp) — not physically removed. Walk history for both Owner and Walker is preserved and remains visible. The dog no longer appears in active lists or as an option for new requests.
- **Change ID:** `owner-removes-dog`
- **PRD refs:** FR-008, §Open Q #4
- **Prerequisites:** S-03
- **Parallel with:** S-06, S-07, S-08, S-09
- **Blockers:** —
- **Unknowns:** —
- **Risk:** F-02 schema used a `RESTRICT` or hard FK on `walks.dog_id` — `/10x-plan owner-removes-dog` must check the migration and add `deleted_at :datetime` to dogs + a default scope that filters deleted records. The soft-delete must NOT cascade to walks; history is load-bearing.
- **Status:** done

### U-01: Tailwind CSS setup + design tokens

- **Outcome:** (foundation) `tailwindcss-rails` gem installed (standalone binary — no Node/npm required), Tailwind config wired into Propshaft + importmap pipeline, application layout includes the compiled stylesheet. A minimal design-token layer defined in `tailwind.config.js`: brand colour palette (2–3 colours), type scale, spacing scale.
- **Change ID:** `tailwind-setup`
- **PRD refs:** §NFR (usability, responsiveness implied by mobile-browser-only MVP)
- **Prerequisites:** S-01 (views must exist before we can verify the pipeline works end-to-end)
- **Parallel with:** —
- **Blockers:** —
- **Unknowns:**
  - Which brand direction? A short colour palette decision is needed before tokens are written. — Owner: user. Block: no (a neutral palette is fine as a placeholder).
- **Risk:** `tailwindcss-rails` ships a standalone Tailwind CLI binary — correct for Rails 8 + Propshaft + importmap (no Webpack/esbuild). Misconfiguring content paths is the most common failure mode — classes that aren't scanned are purged silently in production.
- **Status:** done

### U-02: Global layout shell + role-aware navigation

- **Outcome:** Every page uses a shared layout shell: responsive top navbar with app logo, role-aware navigation links (Owner sees "My dogs / Post a walk / History"; Walker sees "Open requests / History"), a sign-out button, and a flash message area.
- **Change ID:** `ui-layout-and-nav`
- **PRD refs:** FR-001 (sign-out), §Access Control (role-aware visibility)
- **Prerequisites:** U-01
- **Parallel with:** —
- **Blockers:** —
- **Unknowns:** —
- **Risk:** Flash messages must survive Turbo Drive page transitions — `data-turbo-permanent` on the flash container or a Stimulus controller that auto-dismisses. Plain `<div class="flash">` without Turbo awareness disappears on the first SPA navigation.
- **Status:** done

### U-03: Auth + profile screens

- **Outcome:** Sign-in, sign-up (with role radio), and profile-edit pages are fully styled with Tailwind: centred card layout, labelled inputs, validation error messages highlighted in red, primary action button. Usable on mobile without horizontal scroll.
- **Change ID:** `ui-auth-and-profile`
- **PRD refs:** FR-001, FR-002, FR-003, FR-004, FR-005
- **Prerequisites:** U-01, U-02
- **Parallel with:** U-04, U-05
- **Blockers:** —
- **Unknowns:** —
- **Risk:** Sign-up already has a role radio (S-01); it must remain functional after styling. No behaviour changes in this slice — only CSS classes added to existing views.
- **Status:** done

### U-04: Owner dashboard screens

- **Outcome:** Owner-facing screens styled: dog list as cards with edit/add actions, "Post a walk" form, and walk-history table. Empty states ("No dogs yet — add one") shown when lists are empty.
- **Change ID:** `ui-owner-dashboard`
- **PRD refs:** FR-006, FR-007, FR-009, FR-010, FR-015
- **Prerequisites:** U-01, U-02
- **Parallel with:** U-03, U-05
- **Blockers:** —
- **Unknowns:** —
- **Risk:** Walk-history table can grow long; `overflow-x: auto` wrapper on small screens is mandatory so it does not break layout.
- **Status:** done

### U-05: Walker dashboard screens

- **Outcome:** Walker-facing screens styled: open-requests list as cards (dog name, city, time posted), "Accept" CTA button prominent on each card, active-walk screen with "Start walk" / "End walk" states, walk-history list. Status badges (REQUESTED / ACCEPTED / IN_PROGRESS / COMPLETED) colour-coded.
- **Change ID:** `ui-walker-dashboard`
- **PRD refs:** FR-011, FR-012, FR-013, FR-014, FR-016
- **Prerequisites:** U-01, U-02
- **Parallel with:** U-03, U-04
- **Blockers:** —
- **Unknowns:** —
- **Risk:** State badge colours must be consistent across Owner history (U-04) and Walker history (U-05). Define badge classes in `tailwind.config.js` as component aliases or use a shared partial, not duplicated inline colours.
- **Status:** done

## Observability

### O-01: Sentry integration

- **Outcome:** (infra) `sentry-ruby` + `sentry-rails` (+ `stackprof` for profiling) gems added and configured. An initializer at `config/initializers/sentry.rb` reads `SENTRY_DSN` from the environment and enables breadcrumb loggers, performance tracing, and profiling. Unhandled exceptions are automatically captured; `Sentry.capture_exception` / `Sentry.capture_message` work from anywhere. A smoke-test (`1/0` inside a `begin/rescue`) is run in the Rails console on Render to confirm the first event lands in the Sentry project.
- **Change ID:** `sentry-integration`
- **PRD refs:** §NFR (observability — "No structured logging, error tracking, or metrics dashboard" is the current baseline gap)
- **Prerequisites:** — (independent of all feature slices)
- **Parallel with:** any active stream
- **Blockers:** —
- **Unknowns:**
  - `traces_sample_rate = 1.0` and `profiles_sample_rate = 1.0` are correct for early-MVP signal-gathering, but should be tuned down before high-traffic production use. No blocker for v1.
  - `send_default_pii = true` captures request headers and IPs — acceptable for an internal MVP; revisit before GDPR-sensitive public launch.
- **Risk:** DSN **must** come from an environment variable (`SENTRY_DSN`), never hard-coded in the initializer committed to git. A hard-coded DSN is a secret leak — rotatable on Sentry but noisy.
- **Status:** proposed

## Testing Infrastructure

### T-01: E2E system tests (Capybara + Selenium)

- **Outcome:** (infra) `capybara` + `selenium-webdriver` gems wired (test group); headless Chromium installed in `Dockerfile.dev`; `test/application_system_test_case.rb` configured for root-in-Docker (`--no-sandbox`, `--disable-dev-shm-usage`); `bin/rails test:system` runs locally and as a step in CI's `test` job. One smoke test plus one real browser-level test ("Owner creates a walk request": sign in via the real form, click through to create a request) prove the pipeline end-to-end.
- **Change ID:** `e2e-system-tests`
- **PRD refs:** — (user-requested directly, not derived from a PRD line; adjacent to §Guardrails' test-coverage intent but this is a browser-level layer the PRD does not call for)
- **Prerequisites:** — (independent of all feature slices)
- **Parallel with:** any active stream
- **Blockers:** —
- **Unknowns:** — (fully scoped in `context/changes/e2e-system-tests/plan.md`)
- **Risk:** Explicitly outside `context/foundation/test-plan.md`'s phased rollout, which deferred e2e for v1 (integration tests already cover the four core flows). Kept to exactly two system tests by design — e2e is the slowest, most flake-prone layer, and this establishes the pattern rather than sweeping the app. Debian's `chromium`/`chromium-driver` apt packages can lag Google's stable Chrome release by a few weeks; low-risk for a test-only browser.
- **Status:** planned

## Backlog Handoff

| Roadmap ID | Change ID                          | Suggested issue title                                            | Ready for `/10x-plan` | Notes                                                                       |
| ---------- | ---------------------------------- | ---------------------------------------------------------------- | --------------------- | --------------------------------------------------------------------------- |
| F-01       | auth-and-role-typing               | Foundation: Rails 8 auth + role-typed accounts                   | done                  | Archived 2026-06-15 → `context/archive/2026-05-29-auth-and-role-typing/`    |
| F-02       | domain-schema-walks-and-dogs       | Foundation: Dog + Walk schema with DB-level invariants           | done                  | Archived 2026-06-15 → `context/archive/2026-06-02-domain-schema-walks-and-dogs/` |
| F-03       | test-infrastructure-scaffold       | Foundation: Minitest + coverage tooling                          | done                  | Archived 2026-06-15 → `context/archive/2026-06-02-test-infrastructure-scaffold/` |
| S-01       | signup-and-signin-with-role        | Sign-up + sign-in with role choice (Owner/Walker)                | done                  | Archived 2026-06-15 → `context/archive/2026-06-15-signup-and-signin-with-role/` |
| S-02       | profile-with-city                  | User profile with city/postcode                                  | done                  | Archived 2026-06-16 → `context/archive/2026-06-16-profile-with-city/`      |
| S-03       | owner-manages-dog                  | Owner adds + edits their own dog                                 | done                  | Archived 2026-06-16 → `context/archive/2026-06-16-owner-manages-dog/`      |
| S-04       | owner-creates-walk-request         | Owner creates a walk request (US-01)                             | done                  | Archived 2026-06-17 → `context/archive/2026-06-16-owner-creates-walk-request/` |
| S-05       | walker-accepts-request             | **North star.** Walker accepts a request (US-02)                 | done                  | Archived 2026-06-17 → `context/archive/2026-06-17-walker-accepts-request/` |
| S-06       | owner-cancels-requested-walk       | Owner cancels a request in REQUESTED                             | done                  | Archived 2026-06-19 → `context/archive/2026-06-19-owner-cancels-requested-walk/` |
| S-07       | walker-starts-and-completes-walk   | Walker start + end walk (US-03)                                  | done                  | Archived 2026-06-22 → `context/archive/2026-06-22-walker-starts-and-completes-walk/` |
| S-08       | owner-walk-history                 | Owner sees their own walk history                                | done                  | Archived 2026-06-23 → `context/archive/2026-06-23-owner-walk-history/`     |
| S-09       | walker-walk-history                | Walker sees their own walk history                               | done                  | Archived 2026-06-23 → `context/archive/2026-06-23-walker-walk-history/`    |
| S-10       | owner-removes-dog                  | Owner removes own dog (soft-delete; walk history preserved)      | done                  | Archived 2026-07-06 → `context/archive/2026-07-06-owner-removes-dog/`      |
| U-01       | tailwind-setup                     | UI Foundation: Tailwind CSS + design tokens                      | done                  | Archived 2026-06-25 → `context/archive/2026-06-25-tailwind-setup/`         |
| U-02       | ui-layout-and-nav                  | UI: Global layout shell + role-aware navbar                      | done                  | Archived 2026-06-26 → `context/archive/2026-06-26-ui-layout-and-nav/`      |
| U-03       | ui-auth-and-profile                | UI: Auth + profile screens                                       | done                  | Archived 2026-06-26 → `context/archive/2026-06-26-ui-auth-and-profile/`    |
| U-04       | ui-owner-dashboard                 | UI: Owner dashboard (dogs, walk request, history)                | done                  | Archived 2026-06-26 → `context/archive/2026-06-26-ui-owner-dashboard/`     |
| U-05       | ui-walker-dashboard                | UI: Walker dashboard (open requests, active walk, history)       | done                  | Archived 2026-06-29 → `context/archive/2026-06-29-ui-walker-dashboard/`    |
| O-01       | sentry-integration                 | Infra: Sentry error tracking + performance tracing               | yes                   | Independent; DSN from `SENTRY_DSN` env var — do not hard-code              |
| T-01       | e2e-system-tests                   | Infra: Rails System Tests (Capybara + Selenium) + first e2e test | planned               | Plan at `context/changes/e2e-system-tests/plan.md`; Phase 1 not yet started |

## Open Roadmap Questions

1. **Sharpen the Owner persona before v2 scope.** PRD §Open Q #1: v1 is deliberately broad ("anyone with a dog"). Risk: design tradeoffs resurfacing per feature. Owner: user. Block: **roadmap-wide** for v2; no v1 slice.
2. **Walker trust / verification.** PRD §Open Q #3. FR-002 leaves Walker self-sign-up open. Owner: user / downstream design. Block: **before any real (non-test) Owner uses Walkie**. This does NOT block v1 slices, but it blocks any real launch beyond the two-test-user smoke. Resolving it promotes the roadmap from "MVP demonstrable" to "MVP launchable".
3. **Postgres free tier — conscious hold (decided 2026-07-06).** User chose to stay on the free tier for now. Consequence: the 60s cold start skews the 2s latency NFR on first post-idle request; NFR measurements are not reliable until upgraded. Upgrade path: Basic-1GB ($20/mo) recommended by `infrastructure.md`. Owner: user. Block: **infra-wide** for reliable NFR measurement — not a feature blocker.
4. ~~**Remove-dog policy (Open Q #4 from PRD).**~~ **Resolved 2026-07-06: soft-delete** — `deleted_at` on `Dog`; walk history preserved for both sides. S-10 unblocked.

## Parked

### From PRD §Non-Goals (functional)

- **Native mobile apps** — Why parked: PRD §Non-Goals. MVP is web only; mobile-browser support is sufficient.
- **Payments / money flow** — Why parked: PRD §Non-Goals. Trust + compliance + dispute machinery is a project in its own right.
- **Identity verification, ratings / reviews, insurance, trust & safety machinery** — Why parked: PRD §Non-Goals. A real trust system is a separate project; v1 explicitly accepts the gap (see Open Roadmap Q #2 above).
- **Real-time UI layer (live GPS, live map, live status push, in-app chat, push notifications)** — Why parked: PRD §Non-Goals. The "no out-of-app coordination" insight is proven through status transitions seen on refresh, not via live telemetry.
- **Advanced geolocation matching** — Why parked: PRD §Non-Goals and §Open Q #6. v1 filters strictly by city/postcode; no radius, no map, no proximity ranking.
- **AI / ML algorithms anywhere in the product** — Why parked: PRD §Non-Goals. The domain rule is deterministic (first-Walker-claims-it).
- **Advanced Walker-availability scheduling** — Why parked: PRD §Non-Goals. A Walker is "available" iff they sign in and act; load-bearing for the "available right now" insight.

### From PRD §Non-Goals (non-functional)

- **No real-time UI updates** — Why parked: PRD §Non-Goals.
- **No offline support** — Why parked: PRD §Non-Goals.

### From PRD §Open Questions (explicit post-v1)

- **Walker-side insight beyond the "available right now" signal** (local-first matching, no-advance-commitment) — Why parked: PRD §Open Q #2 explicit post-v1.
- **Post-accept cancellation (FR-010 extension)** — Why parked: PRD §Open Q #5 explicit post-v1.
- **Coarse city/postcode filtering improvement** — Why parked: PRD §Open Q #6 explicit "deferred to a later release".
- **Owner confirmation of walk completion (FR-014 extension)** — Why parked: PRD §Open Q #7 explicit post-v1, linked to broader trust/verification work.

## Done

- **F-01: (foundation) Rails 8 auth + role column on User** — Archived 2026-06-15 → `context/archive/2026-05-29-auth-and-role-typing/`. Lesson: —.
- **F-02: (foundation) Dog + Walk schema + state machine + constraints** — Archived 2026-06-15 → `context/archive/2026-06-02-domain-schema-walks-and-dogs/`. Lesson: —.
- **F-03: (foundation) `test/` dir + coverage tooling baseline** — Archived 2026-06-15 → `context/archive/2026-06-02-test-infrastructure-scaffold/`. Lesson: —.
- **S-01: Visitor signs up as Owner or Walker, signs in, signs out** — Archived 2026-06-15 → `context/archive/2026-06-15-signup-and-signin-with-role/`. Lesson: —.
- **S-02: Signed-in user views + edits profile (display name + city)** — Archived 2026-06-16 → `context/archive/2026-06-16-profile-with-city/`. Lesson: —.
- **S-03: Owner adds + edits their own dog** — Archived 2026-06-16 → `context/archive/2026-06-16-owner-manages-dog/`. Lesson: —.
- **S-04: Owner creates a walk request (REQUESTED), sees it in history** — Archived 2026-06-17 → `context/archive/2026-06-16-owner-creates-walk-request/`. Lesson: —.
- **S-05: Walker sees open list + accepts (REQ→ACCEPTED)** — Archived 2026-06-17 → `context/archive/2026-06-17-walker-accepts-request/`. Lesson: —.
- **S-06: Owner cancels their request while still in REQUESTED** — Archived 2026-06-19 → `context/archive/2026-06-19-owner-cancels-requested-walk/`. Lesson: —.
- **S-07: Walker starts (ACC→IP) + ends walk (IP→COMPLETED)** — Archived 2026-06-22 → `context/archive/2026-06-22-walker-starts-and-completes-walk/`. Lesson: —.
- **S-08: Owner sees their own walk history** — Archived 2026-06-23 → `context/archive/2026-06-23-owner-walk-history/`. Lesson: —.
- **S-09: Walker sees their own walk history** — Archived 2026-06-23 → `context/archive/2026-06-23-walker-walk-history/`. Lesson: —.
- **U-01: (foundation) Tailwind CSS + design tokens wired into Propshaft** — Archived 2026-06-25 → `context/archive/2026-06-25-tailwind-setup/`. Lesson: —.
- **U-02: Responsive layout shell + role-aware navbar + flash messages** — Archived 2026-06-26 → `context/archive/2026-06-26-ui-layout-and-nav/`. Lesson: —.
- **U-03: Sign-in, sign-up (with role radio), and profile-edit pages fully styled with Tailwind** — Archived 2026-06-26 → `context/archive/2026-06-26-ui-auth-and-profile/`. Lesson: —.
- **U-04: Dog cards, walk-request form, owner walk-history screen styled** — Archived 2026-06-26 → `context/archive/2026-06-26-ui-owner-dashboard/`. Lesson: —.
- **U-05: Walker-facing screens styled — open-requests list, "Accept" CTA, active-walk screen ("Start walk" / "End walk"), walk-history list, colour-coded status badges** — Archived 2026-06-29 → `context/archive/2026-06-29-ui-walker-dashboard/`. Lesson: —.
- **S-10: Owner removes their own dog (soft-delete; history preserved)** — Archived 2026-07-06 → `context/archive/2026-07-06-owner-removes-dog/`. Lesson: —.
