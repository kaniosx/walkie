# S-04: Owner Creates a Walk Request Implementation Plan

## Overview

Let an Owner with at least one dog tap "Walk my dog" (from the home page or the `/dogs` index) and create a walk request in REQUESTED state, with the walk's locality copied from the owner's profile. The request then appears in a minimal "My walk requests" list. This is roadmap item **S-04** (FR-009, US-01) — the request that the north-star slice S-05 (walker accepts) consumes. F-02 already built the `Walk` model, state machine, DB CHECK constraints, and the `owner_id = dog.user_id` invariant, so this slice is the owner-side creation flow + listing, plus one new integrity guard (one active request per dog).

## Current State Analysis

- **`Walk` model exists** (`app/models/walk.rb`, F-02): `belongs_to :dog/:owner/:accepted_by_walker`, state enum (requested/accepted/in_progress/completed/cancelled), `validates :city, presence`, `owner_matches_dog_owner` (owner_id must equal dog.user_id), role validations, and atomic transition methods (`accept!`/`start!`/`complete!`/`cancel!`).
- **`walks` table** (`db/schema.rb`): `city` NOT NULL, `postcode` nullable, `state` default `"requested"`, `dog_id`/`owner_id` NOT NULL, `[state, city]` index, DB CHECKs for state validity + walker-presence. **No migration needed for S-04.**
- **`User has_many :owned_walks, class_name: "Walk", foreign_key: :owner_id`** — the owner-side listing association already exists.
- **`users.city`/`postcode` are NOT NULL** (S-02) — every owner has a locality to copy onto the walk.
- **`Dog` + owner-scoped CRUD exist** (S-03): `current_user.dogs.active`, `DogsController` with a private `require_owner` before_action that redirects non-owners to `root_path` with an alert.
- **No walks controller / routes / views.** Routes: session, registration, profile, dogs, passwords, root.
- **Home** (`app/views/home/index.html.erb`) has owner/walker branches; owner branch links to `/dogs`. **Nav** has an owners-only "My dogs" link.

### Key Discoveries:

- Creation is `current_user.dogs.active.find(params[:dog_id])` → `dog.walks.build(owner: current_user, city: current_user.city, postcode: current_user.postcode)` → `save`. `state` defaults to `requested`; `owner_matches_dog_owner` holds because the dog belongs to `current_user`.
- The scoped `current_user.dogs.active.find` is the binding no-dogs / cross-owner / soft-deleted-dog guard — a forged or foreign `dog_id` 404s, and an owner with no dogs has no button to press.
- **One-active-request-per-dog is a NEW guard** (not in F-02): a dog can only be walked once at a time. It is *not* a PRD Singleness invariant (that's walker-side, one walker per walk), so a model validation is proportionate; no DB index.
- Two controllers now need the Owner gate (Dogs from S-03, Walks here) → extract a shared concern.

## Desired End State

An Owner lands on home, sees their active dogs each with a one-tap "Walk my dog" button (also on `/dogs`), taps it, and a REQUESTED walk is created with city/postcode from their profile; they're redirected to "My walk requests" showing the new request (dog + state) with a confirmation flash. Tapping again for a dog that already has an active request is rejected with a clear message. Walkers cannot create requests; an Owner cannot request for another owner's (or a soft-deleted) dog.

Verifiable by: `docker compose exec web bin/rails test` green (walks integration + dupe-guard model test, plus the refactored dogs tests); `rubocop` + `brakeman` clean; manual round-trip — Owner taps "Walk my dog" → request appears in the list in well under 30s.

## What We're NOT Doing

- **No walker-facing open-requests list or accept** — that's S-05 (the north star).
- **No start/complete/cancel from this UI** — transitions are S-06 (cancel) / S-07 (start+complete). The model methods exist but aren't wired here.
- **No scheduling / future-dated requests / per-request note** — PRD is now-only; the request is dog + copied locality + requested. Dog notes (S-03) carry standing care info.
- **No full walk-history view** — S-04 ships a *minimal* owner walks index; filters, all-state grouping, and detail are S-08.
- **No per-request locality entry** — locality is copied from the profile (PRD §Locality); no form.
- **No DB-level one-active-per-dog constraint** — model guard only (not a PRD guardrail).
- **No migration** — the walks schema from F-02 is sufficient.

## Implementation Approach

Two phases. Phase 1 is the backend plumbing that has no user-facing surface on its own: the `Walk` active scope + the one-active-request-per-dog validation, and the extraction of the Owner gate into a shared concern (refactoring `DogsController` to use it). Both are independently verifiable and keep the existing suite green. Phase 2 builds the owner-facing flow on top: routes, `WalksController`, the walks index, the per-dog "Walk my dog" buttons on home and `/dogs`, the nav link, and the integration tests.

## Critical Implementation Details

- **Dupe-guard is create-time and not race-safe by design.** The validation rejects a new walk when the dog already has an active walk (`requested`/`accepted`/`in_progress`). Two simultaneous taps could theoretically both pass — acceptable because this is a single owner acting sequentially and it is *not* a PRD Singleness invariant (which is enforced DB-side on the walker accept in F-02/S-05). Document this in the model comment.
- **Shared owner gate changes DogsController's alert text.** Extracting `require_owner` into a concern with a single generic message (e.g. "Only Owners can do that.") replaces DogsController's "Only Owners can manage dogs." — so the S-03 dogs integration test that asserts the old message must be updated in Phase 1.

## Phase 1: Walk active-guard + shared Owner gate

### Overview

Add the Walk `active` scope and the one-active-request-per-dog validation, and extract the Owner-only before_action into a shared concern used by both DogsController and (next phase) WalksController. No migration; suite stays green.

### Changes Required:

#### 1. Walk active scope + one-active-request-per-dog validation

**File**: `app/models/walk.rb`

**Intent**: Express "active" walk states once, and prevent creating a second active request for a dog that already has one (a dog can only be walked once at a time).

**Contract**: `scope :active, -> { where(state: %w[requested accepted in_progress]) }`. A `validate :no_active_walk_for_dog, on: :create` that adds an error (e.g. on `:base` or `:dog`, message "already has an active walk request") when `dog` is present and `dog.walks.active.exists?`. Leave all existing F-02 validations and transition methods untouched. Add a comment noting the guard is create-time and intentionally not DB-enforced (not a PRD Singleness invariant).

#### 2. Shared Owner-only concern

**File**: `app/controllers/concerns/owner_only.rb` (new)

**Intent**: Provide one reusable Owner gate for the controllers that manage owner-only resources.

**Contract**: A concern exposing a `require_owner` before-action helper that redirects non-Owners to `root_path` with a generic alert (e.g. "Only Owners can do that."). Mirrors the structure of the existing `Authentication` concern. Controllers opt in with `include OwnerOnly` + `before_action :require_owner` (or the concern registers it on include — match the chosen style to `Authentication`).

#### 3. Refactor DogsController to the shared gate

**File**: `app/controllers/dogs_controller.rb`

**Intent**: Use the shared concern instead of the private `require_owner`, so there is one definition of the Owner gate.

**Contract**: `include OwnerOnly`; remove the private `require_owner` method; keep behavior identical except the alert text becomes the generic message.

#### 4. Update affected tests + add the dupe-guard test

**File**: `test/integration/dogs_test.rb`, `test/models/walk_test.rb`

**Intent**: Keep the dogs suite green under the new alert text, and unit-test the new Walk guard.

**Contract**: In `dogs_test.rb`, update the walker-blocked assertion to the new generic alert string. In `walk_test.rb`, add tests: creating a second walk for a dog that already has an active walk is invalid (error present, not persisted); creating a walk for a dog whose only prior walk is `completed`/`cancelled` is allowed; the `active` scope returns requested/accepted/in_progress and excludes completed/cancelled.

### Success Criteria:

#### Automated Verification:

- Full suite passes: `docker compose exec web bin/rails test`
- Linting passes: `docker compose exec web bundle exec rubocop`

#### Manual Verification:

- In console, building a second walk for a dog with an active walk is invalid; after the first walk is `completed`/`cancelled`, a new request is allowed.
- DogsController still blocks Walkers (now with the generic alert).

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation before proceeding to Phase 2.

---

## Phase 2: Owner walk-request flow + listing

### Overview

Add the owner-facing creation flow: routes, WalksController (owner-gated, scoped dog lookup, locality copy), a minimal "My walk requests" index, per-dog "Walk my dog" buttons on home and `/dogs`, an owners-only nav link, and integration tests. Full gate at the end.

### Changes Required:

#### 1. Walks routes

**File**: `config/routes.rb`

**Intent**: Expose the owner's walk-request creation and listing.

**Contract**: `resources :walks, only: %i[index create]` (no `new` — creation is a one-tap `button_to`; no show/edit/destroy in this slice).

#### 2. WalksController

**File**: `app/controllers/walks_controller.rb`

**Intent**: Create a REQUESTED walk for one of the owner's dogs with locality copied from the profile, and list the owner's own requests.

**Contract**: `include OwnerOnly`. `index` assigns `current_user.owned_walks` (most-recent first). `create` looks up `current_user.dogs.active.find(params[:dog_id])` (404 on foreign/absent/soft-deleted dog), builds `dog.walks.new(owner: current_user, city: current_user.city, postcode: current_user.postcode)`, and saves; on success redirects to `walks_path` with a notice ("Walk requested for <dog>."), on failure (dupe guard / validation) redirects back (to `walks_path` or the referrer) with the error as an alert. Inherits `require_authentication`. Permit no user-supplied walk attributes other than `dog_id` (locality/owner/state are all server-set).

#### 3. Walks index view

**File**: `app/views/walks/index.html.erb`

**Intent**: Show the owner their walk requests (the "visible in own history" of US-01), minimally.

**Contract**: A `.form-container` page listing each of `current_user.owned_walks` with the dog name, state (humanized), and created time; an empty state ("No walk requests yet."). No filters/grouping (S-08). Each row is read-only here (no actions — cancel is S-06).

#### 4. "Walk my dog" buttons on /dogs and home

**File**: `app/views/dogs/index.html.erb`, `app/views/home/index.html.erb`

**Intent**: Give the Owner the one-tap request action where their dogs are shown.

**Contract**: On the dogs index, add a `button_to "Walk my dog", walks_path, params: { dog_id: dog.id }` per dog row (alongside Edit). On home, in the owner branch, list `current_user.dogs.active` each with the same `button_to` (plus keep an "Add a dog" affordance / link to manage dogs); if the owner has no active dogs, show the existing "Add a dog" nudge instead. Walker home branch unchanged.

#### 5. Owners-only "My requests" nav link

**File**: `app/views/layouts/application.html.erb`

**Intent**: Make the walk-requests list reachable from anywhere for Owners.

**Contract**: In the `authenticated?` + `current_user.owner?` nav region (next to "My dogs"), add `link_to "My requests", walks_path`. Walker nav unchanged.

#### 6. Walks integration tests

**File**: `test/integration/walks_test.rb`

**Intent**: Cover the creation flow, the guardrails, and the listing.

**Contract**: Owner creates a request for their dog → persists with `state: "requested"` and `city`/`postcode` copied from the profile, redirects to `walks_path` with a notice; index lists only the current owner's walks (a second owner's walk absent); a Walker POSTing to `/walks` is blocked (redirect + alert, nothing created); an Owner POSTing with another owner's `dog_id` (or a soft-deleted dog) → 404, nothing created; a second active request for the same dog is rejected (redirect + alert, only one walk exists); unauthenticated access to index/create redirects to sign-in.

### Success Criteria:

#### Automated Verification:

- Walks tests pass: `docker compose exec web bin/rails test test/integration/walks_test.rb`
- Full suite passes: `docker compose exec web bin/rails test`
- Linting passes: `docker compose exec web bundle exec rubocop`
- Security scan clean: `docker compose exec web bundle exec brakeman --no-pager`

#### Manual Verification:

- As an Owner with a dog: "Walk my dog" appears on home and `/dogs`; one tap creates a request and lands on "My requests" showing it (well under 30s).
- Tapping "Walk my dog" again for the same dog shows "already has an active walk request" and does not create a duplicate.
- As a Walker: no "Walk my dog" buttons / "My requests" link; POSTing to `/walks` is blocked.
- Signed out, `/walks` redirects to sign-in.

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation. This completes S-04.

---

## Testing Strategy

### Unit Tests:

- Walk `active` scope membership (requested/accepted/in_progress in; completed/cancelled out).
- One-active-request-per-dog: second active walk invalid; allowed again once the prior is completed/cancelled.

### Integration Tests:

- Owner create → requested + locality copied + redirect + notice.
- Index lists only the owner's own walks.
- Walker blocked from create; Owner blocked from foreign/soft-deleted dog (404); dupe rejected; unauthenticated redirected.

### Manual Testing Steps:

1. Owner taps "Walk my dog" on home; confirm request created and listed under 30s.
2. Tap again for the same dog; confirm the dupe message, no second request.
3. Complete/cancel is not yet available (S-06/S-07) — confirm no such buttons here.
4. Walker: confirm no buttons/link and `/walks` POST blocked.
5. Sign out; visit `/walks`; confirm redirect to sign-in.

## Performance Considerations

PRD §NFR: a user action produces a visible result within 2s. Stock Rails + Postgres handle this easily at v1 scale; the only caveat is the free-tier Postgres cold start (deploy-plan Risk Register) — measure the under-30s / 2s target against a warm DB / Basic-tier, not a cold free instance. Home now runs a small `current_user.dogs.active` query on load (negligible; `user_id` indexed).

## Migration Notes

None — the F-02 walks schema (state default `requested`, city/postcode, constraints) is sufficient. No data changes.

## References

- Roadmap item S-04: `context/foundation/roadmap.md`
- PRD: `context/foundation/prd.md` — FR-009, US-01, §Business Logic §Locality, §NFR (2s), §Acceptance (request invisible to other Owners)
- F-02 model: `app/models/walk.rb`, `db/schema.rb` (walks table + CHECKs)
- Patterns: `app/controllers/dogs_controller.rb` (owner gate, scoped find), `app/views/dogs/index.html.erb` (button_to), `app/views/layouts/application.html.erb` (owners-only nav)
- Prior slices: `context/archive/2026-06-16-owner-manages-dog/plan.md` (S-03), `context/archive/2026-06-16-profile-with-city/` (S-02 locality)
- Change identity: `context/changes/owner-creates-walk-request/change.md`

## Progress

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles. See `references/progress-format.md`.

### Phase 1: Walk active-guard + shared Owner gate

#### Automated

- [x] 1.1 Full suite passes: `docker compose exec web bin/rails test` — f7c06dd
- [x] 1.2 Linting passes: `docker compose exec web bundle exec rubocop` — f7c06dd

#### Manual

- [x] 1.3 Console: second active walk for a dog is invalid; allowed again after prior completed/cancelled — f7c06dd
- [x] 1.4 DogsController still blocks Walkers (generic alert) — f7c06dd

### Phase 2: Owner walk-request flow + listing

#### Automated

- [x] 2.1 Walks tests pass: `docker compose exec web bin/rails test test/integration/walks_test.rb`
- [x] 2.2 Full suite passes: `docker compose exec web bin/rails test`
- [x] 2.3 Linting passes: `docker compose exec web bundle exec rubocop`
- [x] 2.4 Security scan clean: `docker compose exec web bundle exec brakeman --no-pager`

#### Manual

- [x] 2.5 Owner: "Walk my dog" on home + /dogs; one tap creates request, lands on "My requests" under 30s
- [x] 2.6 Second tap for same dog → dupe message, no duplicate
- [x] 2.7 Walker: no buttons/link; `/walks` POST blocked
- [x] 2.8 Signed out, `/walks` redirects to sign-in
