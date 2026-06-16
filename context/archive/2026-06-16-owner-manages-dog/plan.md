# S-03: Owner Manages Dog Implementation Plan

## Overview

Let a signed-in Owner add and edit their own dogs. F-02 already built the `Dog` model (`belongs_to :user`, `name` presence, soft-delete, `walks` restrict); this slice adds the remaining "basic details" fields (`breed` required, `weight` optional kg, `notes` optional), an Owner-only `/dogs` CRUD resource (add + edit, **no remove**), per-owner scoping, and nav/home wiring. This is roadmap item **S-03** (FR-006, FR-007, US-01) — the dog is the entity the marketplace orbits, and S-04 (create walk request) requires an Owner with at least one dog.

## Current State Analysis

- **`Dog` model exists** (`app/models/dog.rb`, F-02): `belongs_to :user`, `validates :name, presence: true`, `has_many :walks, dependent: :restrict_with_exception`, soft-delete (`deactivate!`, `active` scope, `active?`). No `breed`/`weight`/`notes`.
- **`dogs` table** (`db/schema.rb:17`): `name` (NOT NULL), `user_id` (NOT NULL, FK `on_delete: :restrict`), `deactivated_at` (nullable), timestamps. Index on `user_id`.
- **`User has_many :dogs, dependent: :restrict_with_exception`** (`app/models/user.rb`) — the scoping association already exists.
- **No dogs controller / routes / views.** Routes: session, registration, profile, passwords, root.
- **Patterns to follow**: `ProfilesController` (current_user scoping, strong params, render/redirect with `:unprocessable_entity`); the `authenticated?` nav block (Profile + Sign out); registration/profile forms (`.form-container`, `.form-errors`, `form.label` + field); home owner-hint.
- **Owner-only is a guardrail** (PRD §Access Control: "Add / edit / remove own dog" = Owner only). Walkers must be blocked from `/dogs`.
- **Dog-creating test fixtures** (all create `Dog` with `name:` only — will break once `breed` is required): `test/models/walk_test.rb:11`, `test/models/walk_constraints_test.rb:13`, `test/models/walk_concurrency_test.rb:20`, `test/models/dog_test.rb` (`build_dog` helper line 17, plus lines 32/39/40).

### Key Discoveries:

- The S-02 precedent for a required field: DB `NOT NULL` via add → backfill → change-null, collected at creation, with lockstep fixture updates. `breed` follows this; `weight`/`notes` are nullable.
- `current_user.dogs.find(params[:id])` is the idiomatic scoped lookup — a foreign or absent id raises `ActiveRecord::RecordNotFound` → 404, structurally preventing cross-owner access (no IDOR). Same shape as `ProfilesController`'s `current_user`.
- Soft-delete `active` scope means the index should list `current_user.dogs.active`; no deactivated dogs exist yet (remove is S-10) but scoping to `active` is correct from the start.
- `weight` as integer kilograms avoids decimal/locale formatting; validated `> 0` and bounded when present.

## Desired End State

A signed-in Owner sees a "My dogs" nav link, opens it to a list of their dogs (each with an Edit link) plus an "Add a dog" action, adds a dog (name + breed required; weight/notes optional), and edits it. Walkers cannot reach `/dogs` (redirected with an explanatory alert) and the link is hidden from them. An Owner cannot view or edit another Owner's dog (404). The home owner-hint links toward managing dogs.

Verifiable by: `docker compose exec web bin/rails test` green (new model + dogs integration tests, updated fixtures); `rubocop` + `brakeman` clean; manual round-trip — sign in as Owner → My dogs → add a dog → edit it → see it listed; sign in as Walker → `/dogs` redirects with alert.

## What We're NOT Doing

- **No remove / delete** — `destroy` is out of scope (S-10, blocked on Open Q #4: what happens to walk history when a dog is removed). The `active` scope and `deactivate!` already exist from F-02 but are not wired to any action here.
- **No dog photos / avatars** — only name, breed, weight, notes.
- **No decimal/free-text weight, no unit toggle** — integer kilograms only.
- **No breed autocomplete / canonical breed list** — free-text string.
- **No Walker-facing dog views** — Walkers see a dog only via an open walk request (S-05), not here.
- **No creating walk requests** — that's S-04.

## Implementation Approach

Two phases. Phase 1 is the coupled data layer: the migration, the new model validations, and the dog-creating test fixtures must land together, because making `breed` required breaks every fixture that builds a `Dog` with name only — same lockstep constraint as S-02. Phase 2 is the Owner-scoped `/dogs` CRUD (controller + routes + views) plus nav/home wiring and the role/scoping integration tests.

## Critical Implementation Details

- **Migration ordering for NOT NULL on a populated table.** Add `breed` nullable, backfill existing rows with a placeholder (e.g. `"Unknown"`), then `change_column_null :dogs, :breed, false`. `weight` (integer) and `notes` (text) are added nullable and stay nullable. Existing rows are dev/test only.
- **Fixtures break in lockstep.** Once `breed` is required, the four dog-creating test files (see Current State Analysis) must each add `breed:` to their `Dog.create!`/`Dog.new` calls in the same phase, or the suite goes red. This is required for Phase 1 to verify green, not optional cleanup.
- **Owner gate is defense-in-depth.** The controller `before_action` (reject non-owners) is the binding guard; hiding the nav link from Walkers is cosmetic on top. Both ship, but the controller guard is the one the test asserts.

## Phase 1: Schema, model fields, and fixtures

### Overview

Add `breed`/`weight`/`notes` to `dogs`, validate them on the model, and update every dog-creating test so the suite stays green. End state: dogs require name + breed; weight/notes optional.

### Changes Required:

#### 1. Migration adding dog detail fields

**File**: `db/migrate/*_add_details_to_dogs.rb`

**Intent**: Add the "basic details" fields, making `breed` required via the safe add→backfill→change-null sequence on the populated table.

**Contract**: New columns `breed:string` (→ NOT NULL), `weight:integer` (nullable), `notes:text` (nullable). Sequence: add all three nullable → backfill existing rows' `breed` with a documented placeholder (`"Unknown"`) → `change_column_null :dogs, :breed, false`. Use explicit `up`/`down` (the backfill+null-change is not auto-reversible). Generate via `docker compose exec web bin/rails generate migration AddDetailsToDogs` then edit; run `bin/rails db:migrate`.

#### 2. Dog model validations

**File**: `app/models/dog.rb`

**Intent**: Require breed; validate weight as a positive, bounded integer when present; keep notes free-form; add light length caps.

**Contract**: `validates :breed, presence: true, length: { maximum: 100 }`; `validates :weight, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 150 }, allow_nil: true`; optional length cap on `notes`. Leave existing `name` presence, soft-delete, and `walks` association untouched. Optionally `normalizes` breed/name whitespace (strip) consistent with User.

#### 3. Update dog-creating test fixtures + model tests

**File**: `test/models/dog_test.rb`, `test/models/walk_test.rb`, `test/models/walk_constraints_test.rb`, `test/models/walk_concurrency_test.rb`

**Intent**: Keep the suite green under the new required `breed`, and cover the new validations.

**Contract**: Add `breed: "Labrador"` (or similar) to every `Dog.create!`/`Dog.new` that currently passes only `name:` — `build_dog` helper default in dog_test.rb plus the `@dog` setups in the three walk tests. (The `Dog.new(name: "Rex")` no-user test stays invalid for the user reason; adding breed is harmless.) Add model tests: breed required; weight rejects 0 / negative / non-integer / over-bound and accepts nil and a valid value; notes optional; name still required.

### Success Criteria:

#### Automated Verification:

- Migration applies cleanly: `docker compose exec web bin/rails db:migrate`
- Full suite passes: `docker compose exec web bin/rails test`
- Linting passes: `docker compose exec web bundle exec rubocop`

#### Manual Verification:

- In console, a dog with name + breed saves; without breed it's invalid; weight 0 / -1 / 12.5 / 999 are rejected, nil and 12 accepted.
- Existing (backfilled) dogs still load without error.

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation before proceeding to Phase 2.

---

## Phase 2: Owner-scoped /dogs CRUD + nav/home

### Overview

Add the Owner-only `/dogs` resource (list, add, edit — no remove), scoped to the current Owner's dogs, with nav/home wiring and role/scoping integration tests. Full gate at the end.

### Changes Required:

#### 1. Dogs routes

**File**: `config/routes.rb`

**Intent**: Expose dogs as a plural resource without a remove action.

**Contract**: `resources :dogs, only: %i[index new create edit update]` (no `:show`, no `:destroy` — show is unnecessary in v1; remove is S-10).

#### 2. DogsController

**File**: `app/controllers/dogs_controller.rb`

**Intent**: Let an Owner list/add/edit their own dogs, blocked for Walkers and scoped to `current_user`.

**Contract**: A `before_action` that redirects non-Owners (e.g. to `root_path`) with an explanatory alert — name it clearly (e.g. `require_owner`). `index` assigns `current_user.dogs.active`. `new` builds `current_user.dogs.new`; `create` builds from `current_user.dogs.new(dog_params)`, redirects to `dogs_path` with notice on success, re-renders `:new` with `:unprocessable_entity` on failure. `edit`/`update` look up via `current_user.dogs.find(params[:id])` (404 on foreign/absent id); `update` redirects to `dogs_path` on success, re-renders `:edit` with `:unprocessable_entity` on failure. `dog_params` permits `:name, :breed, :weight, :notes` only (never `:user_id`, never `:deactivated_at`). Inherits `require_authentication`.

#### 3. Dogs views

**File**: `app/views/dogs/index.html.erb`, `app/views/dogs/new.html.erb`, `app/views/dogs/edit.html.erb` (+ optional shared `_form` partial)

**Intent**: List the owner's dogs and provide add/edit forms.

**Contract**: `index` lists each dog (name, breed, weight, notes) with an Edit link and an "Add a dog" link to `new_dog_path`; includes an empty-state message when the owner has no dogs. `new`/`edit` are `.form-container` forms (to `dogs_path` POST / `dog_path` PATCH) with labelled fields: name (required), breed (required), weight (optional, "Weight (kg)", `type=number min=1`), notes (optional textarea), plus the shared `.form-errors` block. A `_form` partial shared by new/edit is encouraged (matches Rails convention) but optional.

#### 4. Nav link (owners) + home CTA

**File**: `app/views/layouts/application.html.erb`, `app/views/home/index.html.erb`

**Intent**: Make dogs reachable for Owners and hidden from Walkers (defense-in-depth with the controller gate).

**Contract**: In the `authenticated?` nav block, add `link_to "My dogs", dogs_path` wrapped in `if current_user.owner?`. On home, turn the owner hint into (or add) a link toward `dogs_path` (e.g. "Add or manage your dogs"). Walker nav/home unchanged.

#### 5. Dogs integration tests

**File**: `test/integration/dogs_test.rb`

**Intent**: Cover the happy path plus the two guardrails (owner-only, per-owner scoping) and auth.

**Contract**: Owner can GET index/new/edit (`:success`); POST creates a dog scoped to them and redirects to index; PATCH updates and redirects; invalid create/update (missing breed) re-renders with `:unprocessable_entity` and no persistence; index lists only the current owner's dogs (a second owner's dog is absent); a Walker GET/POST to `/dogs` is redirected with an alert and creates nothing; an Owner requesting another Owner's dog id on edit/update gets 404; unauthenticated access redirects to sign-in.

### Success Criteria:

#### Automated Verification:

- Dogs tests pass: `docker compose exec web bin/rails test test/integration/dogs_test.rb`
- Full suite passes: `docker compose exec web bin/rails test`
- Linting passes: `docker compose exec web bundle exec rubocop`
- Security scan clean: `docker compose exec web bundle exec brakeman --no-pager`

#### Manual Verification:

- As an Owner: "My dogs" appears in nav; add a dog (name + breed), see it listed; edit it; weight/notes optional; missing breed shows an error.
- As a Walker: no "My dogs" link; visiting `/dogs` redirects with an alert.
- Owner A cannot edit Owner B's dog (manually altering the id → 404).
- Signed out, `/dogs` redirects to sign-in.

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation. This completes S-03.

---

## Testing Strategy

### Unit Tests:

- breed required; name still required.
- weight: rejects 0, negative, non-integer, over-bound; accepts nil and a valid integer.
- notes optional; (optional) breed/name whitespace stripped.

### Integration Tests:

- Owner add + edit dog persists and redirects; invalid (missing breed) re-renders 422.
- Index lists only the current owner's dogs (cross-owner isolation).
- Walker blocked from `/dogs` (redirect + alert, no creation).
- Owner cannot edit another owner's dog (404 via scoped find).
- Unauthenticated `/dogs` redirects to sign-in.

### Manual Testing Steps:

1. Owner: add a dog with name + breed; confirm it lists; edit weight + notes; confirm saved.
2. Owner: submit add with blank breed; confirm error, no dog created.
3. Walker: confirm no "My dogs" link and `/dogs` redirects with alert.
4. Owner A: edit URL with Owner B's dog id; confirm 404.
5. Sign out; visit `/dogs`; confirm redirect to sign-in.

## Performance Considerations

Negligible at v1 scale — an owner has a handful of dogs; index is a single scoped query (`current_user.dogs.active`). The existing `user_id` index covers it.

## Migration Notes

One migration adds `breed` (→ NOT NULL via add→backfill→change-null), `weight` (integer, nullable), `notes` (text, nullable). Existing rows are dev/test only (no real users per roadmap baseline) and get a `"Unknown"` breed placeholder. `down` removes the three columns.

## References

- Roadmap item S-03: `context/foundation/roadmap.md`
- PRD: `context/foundation/prd.md` — FR-006, FR-007, US-01, §Access Control (Owner-only dog management)
- F-02 model: `app/models/dog.rb`, `db/schema.rb:17` (dogs table + soft-delete)
- Patterns: `app/controllers/profiles_controller.rb` (scoping/strong-params), `app/views/profiles/edit.html.erb` (form), `app/views/layouts/application.html.erb` (nav)
- S-02 precedent (required field NOT NULL + lockstep fixtures): `context/archive/2026-06-16-profile-with-city/plan.md`
- Change identity: `context/changes/owner-manages-dog/change.md`

## Progress

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles. See `references/progress-format.md`.

### Phase 1: Schema, model fields, and fixtures

#### Automated

- [x] 1.1 Migration applies cleanly: `docker compose exec web bin/rails db:migrate` — 7ea42b6
- [x] 1.2 Full suite passes: `docker compose exec web bin/rails test` — 7ea42b6
- [x] 1.3 Linting passes: `docker compose exec web bundle exec rubocop` — 7ea42b6

#### Manual

- [x] 1.4 Console: name+breed saves; missing breed invalid; weight 0/-1/12.5/999 rejected, nil/12 accepted — 7ea42b6
- [x] 1.5 Existing (backfilled) dogs still load without error — 7ea42b6

### Phase 2: Owner-scoped /dogs CRUD + nav/home

#### Automated

- [x] 2.1 Dogs tests pass: `docker compose exec web bin/rails test test/integration/dogs_test.rb` — 68a9dbd
- [x] 2.2 Full suite passes: `docker compose exec web bin/rails test` — 68a9dbd
- [x] 2.3 Linting passes: `docker compose exec web bundle exec rubocop` — 68a9dbd
- [x] 2.4 Security scan clean: `docker compose exec web bundle exec brakeman --no-pager` — 68a9dbd

#### Manual

- [x] 2.5 Owner: "My dogs" in nav; add dog (name+breed) lists; edit works; missing breed errors — 68a9dbd
- [x] 2.6 Walker: no "My dogs" link; `/dogs` redirects with alert — 68a9dbd
- [x] 2.7 Owner A cannot edit Owner B's dog (404) — 68a9dbd
- [x] 2.8 Signed out, `/dogs` redirects to sign-in — 68a9dbd
