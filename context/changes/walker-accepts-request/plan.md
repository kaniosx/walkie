# S-05: Walker Accepts an Open Request Implementation Plan

## Overview

Let a signed-in Walker see the open (REQUESTED) walk requests in their own city + postcode and accept one — transitioning it REQUESTED → ACCEPTED, binding it to that walker, and removing it from every other walker's list. This is roadmap item **S-05**, the **north star**: it puts the PRD's central hypothesis ("the gap isn't supply, it's the 'available right now' signal") in front of real users. The hard part — the single-Walker acceptance race — is already solved and tested at the DB/model layer by F-02 (`Walk#accept!` atomic compare-and-swap + `walks_walker_presence` CHECK + `walk_concurrency_test`). This slice wires the walker-facing list + accept flow on top and verifies the outcome at the HTTP layer.

## Current State Analysis

- **`Walk#accept!(walker)`** (`app/models/walk.rb`) already performs the transition atomically: a single guarded `update_all` (`where(id:, state: "requested")` → set `accepted`, `accepted_by_walker_id`, `accepted_at`), returning `true` if this call won and `false` if it lost the race / the walk wasn't requested. It guards `walker.walker? && walker.id != owner_id`. **S-05 calls this; it writes no new transition code.**
- **DB backstop**: `walks_walker_presence` + `walks_state_valid` CHECK constraints; `walk_concurrency_test` proves exactly one winner across 10 racing threads.
- **`Walk` has the enum** (`requested`/.../`cancelled`) giving `Walk.requested` scope, and an `active` scope (S-04). The `[state, city]` index supports the open-list query.
- **`walks` locality**: `city` NOT NULL, `postcode` (S-04 copies both from the owner's profile, so every REQUESTED walk has both populated).
- **`User has_many :accepted_walks, class_name: "Walk", foreign_key: :accepted_by_walker_id`** — the walker-side association exists (used by S-09, not needed for the list here).
- **`OwnerOnly` concern** (`app/controllers/concerns/owner_only.rb`, S-04) is the pattern to mirror for the walker gate. `WalksController` is owner-gated (owner's requests + create).
- **No walker-facing controller / route / view.** Home's walker branch is a placeholder ("you'll be able to see and accept…"); nav has owner-only links.

### Key Discoveries:

- The accept action is `walk.accept!(current_user)` returning a boolean — the controller branches on it (won → notice; lost/taken → "already accepted" alert). No locking, no transaction code in S-05.
- "Disappears from other walkers' lists" is automatic: once `state != "requested"`, the walk falls out of the REQUESTED-filtered query — no extra bookkeeping.
- Minitest integration tests are serial + transactional, so a *literally parallel* HTTP race can't be tested reliably there; the genuine race is owned by `walk_concurrency_test` (real threads). S-05's HTTP test verifies the *outcome contract* sequentially (second accept on a taken walk → "already accepted", binding unchanged).
- Role separation: the walker controller must be `WalkerOnly` and the list must be city+postcode scoped — the walker never sees owner views or out-of-locality requests.

## Desired End State

A signed-in Walker opens "Open requests" (nav + home link), sees the REQUESTED walks in their exact city + postcode — each row showing the dog's name, breed, and locality (no owner identity) with an "Accept" button — and taps Accept. The walk becomes ACCEPTED bound to them and drops off the list (and off every other walker's list). If they tap a walk someone else just took, they're returned to the refreshed list with "Sorry, that walk was just accepted by someone else." Owners cannot reach the walker controller; out-of-locality and non-requested walks never appear.

Verifiable by: `docker compose exec web bin/rails test` green (new open-requests integration tests + the open-in-locality scope test, alongside the untouched F-02 race tests); `rubocop` + `brakeman` clean; manual round-trip — two browser sessions (one Owner posts a request, one Walker in the same city/postcode accepts it; a second walker then sees it gone).

## What We're NOT Doing

- **No start / complete** — ACCEPTED → IN_PROGRESS → COMPLETED is S-07. `start!`/`complete!` exist on the model but are not wired here.
- **No walker walk-history view** — the walker's own accepted/in-progress/completed list is S-09. S-05 lands the walker back on the open list after accepting; the accepted walk simply drops off.
- **No owner identity in the list** — rows show dog + breed + locality only (PRD §NFR: expose only what the FR requires).
- **No realtime / auto-refresh** — the list updates on navigation/refresh (PRD §Non-Goals: status changes seen on refresh, not push).
- **No new concurrency mechanism** — the accept race is already DB-enforced (F-02); S-05 only calls `accept!` and surfaces its boolean.
- **No radius / proximity / map** — exact city + postcode equality only (PRD coarse-locality, §Open Q #6).
- **No migration** — the F-02 walks schema + indexes are sufficient.

## Implementation Approach

Two phases. Phase 1 is backend plumbing with no user surface: a `WalkerOnly` concern (mirroring `OwnerOnly`) and a `Walk.open_in_locality(city, postcode)` scope (REQUESTED + city + postcode), with a scope unit test. Phase 2 builds the walker-facing flow on top: an `OpenRequestsController` (walker-gated index + member accept that calls `accept!`), the route, the list view, walker nav/home links, and the integration tests covering the full flow plus both guardrails (single-Walker outcome, role separation never leaks) and the locality filter.

## Critical Implementation Details

- **Accept is `accept!`, not a re-implementation.** The controller's accept action looks up the walk (unscoped by owner — any walker may accept any open request in their locality), calls `current_user.something… accept!`, and branches on the boolean. Do NOT add locking, `with_lock`, or a transaction — that would duplicate (and could weaken) the atomic compare-and-swap F-02 already proved.
- **HTTP race test is sequential by necessity.** Integration tests run in a transaction that serializes writes, so a parallel HTTP race can't be exercised there. Verify the *contract* (second accept → false → "already accepted", original binding intact) sequentially; the parallel race remains `walk_concurrency_test`'s job. Don't attempt threaded HTTP requests in the integration suite.

## Phase 1: Walker gate + open-requests scope

### Overview

Add the `WalkerOnly` controller gate and the `Walk.open_in_locality` scope that the walker list will use. No user-facing surface yet; suite stays green.

### Changes Required:

#### 1. WalkerOnly concern

**File**: `app/controllers/concerns/walker_only.rb` (new)

**Intent**: Provide one reusable Walker gate, symmetric with `OwnerOnly`, for walker-only controllers.

**Contract**: A concern mirroring `OwnerOnly`: `included do before_action :require_walker end`; private `require_walker` redirects non-Walkers to `root_path` with a generic alert (e.g. "Only Walkers can do that."). Runs after `require_authentication` (registered on `ApplicationController`), so `current_user` is present.

#### 2. Walk open-in-locality scope

**File**: `app/models/walk.rb`

**Intent**: Express "open requests a walker in this locality can accept" once, for reuse by the controller and direct testing.

**Contract**: `scope :open_in_locality, ->(city, postcode) { requested.where(city: city, postcode: postcode) }` (uses the enum-provided `requested` scope; city+postcode equality). Leave all existing F-02 validations, the S-04 `active` scope / dupe-guard, and transition methods untouched.

#### 3. Scope unit test

**File**: `test/models/walk_test.rb`

**Intent**: Lock the locality filter: only REQUESTED walks in the exact city + postcode are returned.

**Contract**: Tests asserting `Walk.open_in_locality(city, postcode)` includes a matching REQUESTED walk and excludes: a walk in a different city, a walk in the same city but different postcode, and a non-requested walk (accepted/cancelled). Reuse the existing `walk_test.rb` setup; create the extra walks with distinct dogs/owners to avoid the one-active-per-dog guard.

### Success Criteria:

#### Automated Verification:

- Full suite passes: `docker compose exec web bin/rails test`
- Linting passes: `docker compose exec web bundle exec rubocop`

#### Manual Verification:

- In console, `Walk.open_in_locality("Kraków", "30-001")` returns only REQUESTED walks matching both fields; a same-city/different-postcode walk and an accepted walk are excluded.

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation before proceeding to Phase 2.

---

## Phase 2: Walker open-requests flow + accept

### Overview

Add the walker-facing open-requests list and the accept action (calling `accept!`), the route, the view, walker nav/home links, and the integration tests. Full gate at the end.

### Changes Required:

#### 1. Open-requests route

**File**: `config/routes.rb`

**Intent**: Expose the walker's open-requests list and a per-walk accept action.

**Contract**: `resources :open_requests, only: %i[index] do member { post :accept } end` — `GET /open_requests` (list) and `POST /open_requests/:id/accept` (`:id` = walk id), giving `accept_open_request_path(walk)`.

#### 2. OpenRequestsController

**File**: `app/controllers/open_requests_controller.rb` (new)

**Intent**: Show the walker the open requests in their locality and let them accept one via the existing atomic transition.

**Contract**: `include WalkerOnly`. `index` assigns `Walk.open_in_locality(current_user.city, current_user.postcode).includes(:dog).order(created_at: :asc)` (oldest first — fairest "available now" queue; ordering is a minor choice). `accept` looks up the walk by `params[:id]` (Walk.find — any open walk in any locality is acceptable in principle; the list only *surfaces* in-locality ones, but accept does not need owner/locality scoping beyond what `accept!` guards), calls `walk.accept!(current_user)`, and branches: `true` → redirect to `open_requests_path` with notice ("You accepted the walk for #{walk.dog.name}."); `false` → redirect to `open_requests_path` with alert ("Sorry, that walk was just accepted by someone else."). Inherits `require_authentication`. No walk attributes are read from params beyond the id.

#### 3. Open-requests index view

**File**: `app/views/open_requests/index.html.erb`

**Intent**: List the in-locality open requests with an Accept button each, plus a friendly empty state.

**Contract**: A `.form-container` page; for each walk, a row with the dog's name + breed and the walk's city/postcode, and a `button_to "Accept", accept_open_request_path(walk)` (POST). No owner name/email. Empty state names the locality: "No open walk requests in #{current_user.city} right now." Read-only otherwise (no start/complete — S-07).

#### 4. Walker nav + home links

**File**: `app/views/layouts/application.html.erb`, `app/views/home/index.html.erb`

**Intent**: Make the open-requests list reachable for Walkers; hidden from Owners (defense-in-depth with the controller gate).

**Contract**: In the `authenticated?` nav, add `link_to "Open requests", open_requests_path` inside an `if current_user.walker?` branch (parallel to the owner links). On home, the walker branch links to `open_requests_path` (e.g. "See open walk requests in your area"). Owner nav/home unchanged.

#### 5. Open-requests integration tests

**File**: `test/integration/open_requests_test.rb` (new)

**Intent**: Cover the full walker flow plus both PRD guardrails and the locality filter at the HTTP layer.

**Contract**: A Walker sees only REQUESTED walks in their city+postcode (a different-city walk, a same-city/different-postcode walk, and an accepted walk are all absent from the list); accepting binds the walk REQUESTED→ACCEPTED to the walker and it no longer appears in the list; a second accept on an already-accepted walk → redirect with "already accepted" alert, state unchanged and still bound to the first walker (sequential race-outcome contract); an Owner GET/POST to the open-requests controller is blocked (redirect + alert, no state change — role separation); unauthenticated access redirects to sign-in. (The genuine parallel race remains covered by `walk_concurrency_test`.)

### Success Criteria:

#### Automated Verification:

- Open-requests tests pass: `docker compose exec web bin/rails test test/integration/open_requests_test.rb`
- Full suite passes: `docker compose exec web bin/rails test`
- Linting passes: `docker compose exec web bundle exec rubocop`
- Security scan clean: `docker compose exec web bundle exec brakeman --no-pager`

#### Manual Verification:

- As a Walker: "Open requests" appears in nav/home; the list shows only same city+postcode REQUESTED walks (dog + breed + locality, no owner name).
- Accepting a request shows the notice and the request drops off the list; in a second walker's session (same locality) the request is already gone.
- Tapping a walk that was just accepted shows "already accepted" and the original acceptance is unchanged.
- As an Owner: no "Open requests" link; visiting `/open_requests` redirects with an alert.
- Signed out, `/open_requests` redirects to sign-in.

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation. This completes S-05 — the north-star validation milestone.

---

## Testing Strategy

### Unit Tests:

- `Walk.open_in_locality(city, postcode)` returns only REQUESTED walks matching both fields; excludes other-city, other-postcode, and non-requested walks.
- (Existing, untouched) `walk_test.rb` accept!/transition tests + `walk_concurrency_test.rb` parallel race.

### Integration Tests:

- Walker open-list scoping (locality + requested-only); accept binds REQUESTED→ACCEPTED and drops off the list; "already accepted" outcome on a taken walk (state + binding unchanged); Owner blocked (role separation); unauthenticated redirect.

### Manual Testing Steps:

1. Owner (city A) posts a request; Walker (city A, same postcode) sees it in Open requests; Walker (city B) does not.
2. Walker A accepts; confirm notice + request gone; second Walker (same locality) no longer sees it.
3. Force the lost-race path (accept an already-accepted walk via a stale page) → "already accepted".
4. Owner visits `/open_requests` → redirected with alert.
5. Sign out → `/open_requests` redirects to sign-in.

## Performance Considerations

The open-list query is `requested + city + postcode`, backed by the `[state, city]` index (postcode is a cheap residual filter at v1 scale). `includes(:dog)` avoids an N+1 on the dog per row. `accept!` is a single indexed UPDATE. PRD §NFR 2s is comfortably met on a warm DB; the free-tier Postgres cold-start caveat (deploy-plan Risk Register) applies to the first request after idle, as for S-04.

## Migration Notes

None — F-02's walks schema, CHECK constraints, and `[state, city]` index are sufficient. No data changes.

## References

- Roadmap item S-05 (north star): `context/foundation/roadmap.md`
- PRD: `context/foundation/prd.md` — FR-011, FR-012, US-02, §Business Logic §Singleness/§Locality, §Guardrails (single-Walker race; role separation), §NFR
- F-02 race machinery: `app/models/walk.rb` (`accept!`), `db/schema.rb` (`walks_walker_presence` CHECK, `[state, city]` index), `test/models/walk_concurrency_test.rb`
- Patterns: `app/controllers/concerns/owner_only.rb` (gate to mirror), `app/controllers/walks_controller.rb` (S-04 owner flow), `app/views/walks/index.html.erb` (list view)
- Prior slice: `context/archive/2026-06-16-owner-creates-walk-request/plan.md` (S-04, produces the requests S-05 consumes)
- Change identity: `context/changes/walker-accepts-request/change.md`

## Progress

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles. See `references/progress-format.md`.

### Phase 1: Walker gate + open-requests scope

#### Automated

- [x] 1.1 Full suite passes: `docker compose exec web bin/rails test` — 7224aaa
- [x] 1.2 Linting passes: `docker compose exec web bundle exec rubocop` — 7224aaa

#### Manual

- [x] 1.3 Console: `Walk.open_in_locality` returns only requested + exact city+postcode; excludes other-postcode + accepted — 7224aaa

### Phase 2: Walker open-requests flow + accept

#### Automated

- [x] 2.1 Open-requests tests pass: `docker compose exec web bin/rails test test/integration/open_requests_test.rb` — 4a268c7
- [x] 2.2 Full suite passes: `docker compose exec web bin/rails test` — 4a268c7
- [x] 2.3 Linting passes: `docker compose exec web bundle exec rubocop` — 4a268c7
- [x] 2.4 Security scan clean: `docker compose exec web bundle exec brakeman --no-pager` — 4a268c7

#### Manual

- [x] 2.5 Walker: "Open requests" in nav/home; list shows only same city+postcode requested walks (dog+breed+locality, no owner) — 4a268c7
- [x] 2.6 Accept → notice + request drops off; gone from a second walker's list — 4a268c7
- [x] 2.7 Accepting an already-taken walk → "already accepted", original acceptance unchanged — 4a268c7
- [x] 2.8 Owner blocked from `/open_requests` (redirect + alert); signed out redirects to sign-in — 4a268c7
