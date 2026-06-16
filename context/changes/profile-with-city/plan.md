# S-02: User Profile with City/Postcode Implementation Plan

## Overview

Add three fields to the user — `display_name` (optional), `city` and `postcode` (both required) — collected at sign-up and editable through a dedicated profile screen. This is roadmap item **S-02** (FR-005). It builds on S-01's auth UI and the locality shape F-02 already established on `walks` (`city` NOT NULL + `postcode`). Per the planning interview, city/postcode are stored `NOT NULL` and captured during registration, so every user always has a locality — which lets S-04 copy the owner's city/postcode straight onto a new walk and lets S-05 filter without a "is city set?" guard.

## Current State Analysis

- **`users` table** (`db/schema.rb:35`) has only `email_address`, `password_digest`, `role` (+ timestamps). No `display_name`, `city`, or `postcode`.
- **`User` model** (`app/models/user.rb`) has the role enum, role immutability, email normalization, and the `dogs` / `owned_walks` / `accepted_walks` associations. No profile fields or validations.
- **`walks` table** (`db/schema.rb:44`) already models locality as `city` (string, NOT NULL) + `postcode` (string, nullable), with a `[state, city]` index for open-request filtering. `Walk` validates `city` presence (`app/models/walk.rb:17`). The user's fields mirror this so S-04 can copy them onto the walk.
- **Registration** (`app/controllers/registrations_controller.rb`) permits `email_address, password, password_confirmation, role` and calls `start_new_session_for`. The form (`app/views/registrations/new.html.erb`) collects those fields + a role radio, wrapped in `.form-container`.
- **No profile controller / routes / views exist.** Routes (`config/routes.rb`) have `resource :session`, `resource :registration`, `resources :passwords`, `root "home#index"`.
- **S-01 nav** (`app/views/layouts/application.html.erb`) renders an `authenticated?`-gated nav with a sign-out button; **home** (`app/views/home/index.html.erb`) shows `email_address (role)` + a role hint.
- **Tests that create users without locality** (will break once city/postcode are required): `test/models/user_test.rb` (`build_user` helper), `test/integration/sessions_test.rb` (setup), `test/integration/navigation_test.rb` (setup), `test/integration/registration_test.rb` (POST params).

### Key Discoveries:

- F-02 fixed the locality vocabulary: `city` required, `postcode` optional **on the walk** (`db/schema.rb:48,53`). On the user, the interview chose **both required** — this is a deliberate divergence (a user must declare a full locality; a walk's postcode can still be blank if ever created without one, though in practice it's copied from the owner).
- The `state` column on `walks` is the **walk lifecycle state**, not a geographic region — do not confuse it with locality.
- Making `city`/`postcode` `NOT NULL` on a populated table requires the **add → backfill → change-null** sequence; existing rows are dev/test data only (no real users yet per roadmap baseline).
- `current_user` is a `helper_method` (S-01) available in views; `authenticated?` likewise — the nav and home already use them.

## Desired End State

A signed-in user sees a "Profile" link in the nav, opens it to a read-only profile (display name, city, postcode, email, role), and can edit display name + city + postcode. New sign-ups must supply city + postcode (required radio/fields on the registration form). Every user row has non-null city/postcode. Where a name is shown (home, profile), `display_name` is used if present, otherwise `email_address`.

Verifiable by: `docker compose exec web bin/rails test` green (including new model + profile integration tests and updated registration test); `rubocop` + `brakeman` clean; manual round-trip — sign up with city/postcode → open Profile → edit display name + city → see it reflected on home and profile.

## What We're NOT Doing

- **No geolocation / radius / map / proximity** — v1 locality stays coarse free-text (PRD §Open Q #6).
- **No postcode format / country validation** — presence + length cap only (interview decision).
- **No city normalization for matching** — that belongs to S-05's filtering logic, not S-02.
- **No avatar, bio, phone, or other profile fields** — only display_name, city, postcode (FR-005 scope).
- **No password change / email change on the profile screen** — out of scope; profile edits only the three new fields.
- **No role display-editing** — role remains immutable (F-01); profile shows it read-only.

## Implementation Approach

Two phases. Phase 1 is the tightly-coupled data layer: the migration, model validations, and registration capture must land together because making city/postcode `NOT NULL` + presence-validated breaks any user-creation path that doesn't supply them — so the registration form, controller, and all user-creating test fixtures are updated in the same phase to keep the suite green. Phase 2 is the independent profile resource (controller + routes + views) plus the nav/home integration and profile-specific tests.

## Critical Implementation Details

- **Migration ordering for NOT NULL on a populated table.** Add `city`/`postcode` as nullable, backfill existing rows with a placeholder, then `change_column_null ..., false`. `display_name` is added nullable and stays nullable. Without the backfill step the `NOT NULL` change fails on existing dev/test rows.
- **Test fixtures break in lockstep.** Once presence validation lands, every `User.create!` / `User.new` without city+postcode fails. Update `build_user` (user_test.rb) and the setup/POST params in sessions_test, navigation_test, registration_test within Phase 1 — this is required for the phase to verify green, not optional cleanup.

## Phase 1: Schema, model validations, and sign-up capture

### Overview

Add the columns, validate them on the model, capture city/postcode at registration, and update every user-creating test so the suite stays green. End state: every user has non-null city/postcode; display_name optional.

### Changes Required:

#### 1. Migration adding profile fields

**File**: `db/migrate/*_add_profile_fields_to_users.rb`

**Intent**: Add `display_name` (nullable), `city` and `postcode` (required) to `users`, safely converting the populated table to `NOT NULL`.

**Contract**: New columns `display_name:string` (nullable), `city:string`, `postcode:string`. Sequence: add all three nullable → backfill existing rows' `city`/`postcode` with a documented placeholder (e.g. `"Unknown"` / `"00-000"`) → `change_column_null :users, :city, false` and same for `postcode`. `display_name` left nullable. Generate via `docker compose exec web bin/rails generate migration AddProfileFieldsToUsers` then edit. Run `bin/rails db:migrate`.

#### 2. User model validations + display-name fallback

**File**: `app/models/user.rb`

**Intent**: Require city and postcode, keep display_name optional, and expose a single accessor for "name to show" so views don't repeat the fallback.

**Contract**: `validates :city, presence: true, length: { maximum: 100 }`; `validates :postcode, presence: true, length: { maximum: 100 }`; no validation on `display_name` beyond an optional length cap. Add a method (e.g. `display_label`) returning `display_name` if present else `email_address`. Optionally `normalizes` for city/postcode stripping (whitespace only — no case/format change, per scope).

#### 3. Registration collects city + postcode

**File**: `app/controllers/registrations_controller.rb`, `app/views/registrations/new.html.erb`

**Intent**: Capture the now-required locality at sign-up so new users satisfy the NOT NULL/presence rules.

**Contract**: Controller `registration_params` permits `:city, :postcode` (in addition to the existing email/password/role; `display_name` may also be permitted but is not required at sign-up). View adds labelled, required `city` and `postcode` text fields inside the existing `.form-container`, following the S-01 label pattern (`form.label` + field). Role radios and other fields unchanged.

#### 4. Update user-creating test fixtures

**File**: `test/models/user_test.rb`, `test/integration/sessions_test.rb`, `test/integration/navigation_test.rb`, `test/integration/registration_test.rb`

**Intent**: Keep the suite green under the new required fields, and assert the new model rules.

**Contract**: Add `city`/`postcode` to `build_user` defaults and to each `User.create!` setup and registration POST params. Add model unit tests: city required, postcode required, length caps reject overlong values, `display_label` returns display_name when present and email when blank. Update `registration_test` so the happy-path POST includes city/postcode and asserts they persist; add a case asserting a sign-up missing city (or postcode) re-renders with an error and creates no user.

### Success Criteria:

#### Automated Verification:

- Migration applies cleanly: `docker compose exec web bin/rails db:migrate`
- Full suite passes: `docker compose exec web bin/rails test`
- Linting passes: `docker compose exec web bundle exec rubocop`

#### Manual Verification:

- Sign-up form shows required City and Postcode fields; submitting without them re-renders with errors and creates no user.
- A successful sign-up persists city/postcode (verify on the user in console or the next phase's profile screen).
- Existing (backfilled) users still load without error.

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation before proceeding to Phase 2.

---

## Phase 2: Profile resource + nav/home integration

### Overview

Add the singular `profile` resource (view + edit + update), link it from the nav, surface `display_name` on the home page, and test the profile flows. Full gate at the end.

### Changes Required:

#### 1. Profile route

**File**: `config/routes.rb`

**Intent**: Expose the current user's profile as a singular resource (each user edits only their own).

**Contract**: `resource :profile, only: %i[show edit update]` (singular — no `:id`; the controller always scopes to `current_user`).

#### 2. ProfilesController

**File**: `app/controllers/profiles_controller.rb`

**Intent**: Let a signed-in user view and edit their own profile, scoped to `current_user` so no other user's data is reachable.

**Contract**: `show` and `edit` assign `@user = current_user`. `update` permits `:display_name, :city, :postcode` only (never `:role`, never `:email_address`/password), updates `current_user`; on success redirect to the profile show page with a notice, on failure re-render `edit` with `:unprocessable_entity`. Inherits `require_authentication` (no `allow_unauthenticated_access`).

#### 3. Profile views

**File**: `app/views/profiles/show.html.erb`, `app/views/profiles/edit.html.erb`

**Intent**: A read-only profile summary and an edit form for the three fields.

**Contract**: `show` displays display name (via `display_label`), city, postcode, email, role (role read-only), and a link to `edit_profile_path`. `edit` is a `.form-container` form to `profile_path` (PATCH) with labelled fields for display_name (optional), city (required), postcode (required), an errors block mirroring registrations/new, and a cancel link back to `profile_path`.

#### 4. Nav link + home display name

**File**: `app/views/layouts/application.html.erb`, `app/views/home/index.html.erb`

**Intent**: Make the profile reachable and use display_name where a name is shown.

**Contract**: Add `link_to "Profile", profile_path` inside the `authenticated?` block in the nav (alongside sign-out). Home replaces the bare `email_address` with `current_user.display_label` ("Signed in as …") — role hint unchanged.

#### 5. Profile tests

**File**: `test/integration/profiles_test.rb`

**Intent**: Cover the profile happy path, validation failure, and auth gating.

**Contract**: Signed-in user can GET show and edit (`:success`); PATCH update with valid display_name/city/postcode persists and redirects to show; PATCH with blank city (or postcode) re-renders `edit` with `:unprocessable_entity` and does not change the record; unauthenticated GET of show/edit redirects to sign-in. Use the updated user-creation helper from Phase 1.

### Success Criteria:

#### Automated Verification:

- Profile tests pass: `docker compose exec web bin/rails test test/integration/profiles_test.rb`
- Full suite passes: `docker compose exec web bin/rails test`
- Linting passes: `docker compose exec web bundle exec rubocop`
- Security scan clean: `docker compose exec web bundle exec brakeman --no-pager`

#### Manual Verification:

- Nav shows a "Profile" link when signed in; it opens the profile show page.
- Editing display name + city + postcode saves and is reflected on the profile and on the home page ("Signed in as <display name>").
- Submitting the edit form with a blank city or postcode shows an error and does not save.
- Visiting the profile while signed out redirects to sign-in.

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation. This completes S-02.

---

## Testing Strategy

### Unit Tests:

- city required; postcode required; length caps reject overlong values.
- `display_label` returns display_name when present, email when blank.
- display_name optional (a user with city/postcode but no display_name is valid).

### Integration Tests:

- Registration (updated): happy path includes city/postcode and persists them; missing city/postcode re-renders with error, no user created.
- Profile: show/edit reachable when authenticated; update persists + redirects; blank city/postcode rejected; unauthenticated access redirects to sign-in.

### Manual Testing Steps:

1. Sign up supplying city + postcode; confirm it succeeds and lands on home.
2. Attempt sign-up leaving city blank; confirm error and no user created.
3. Open Profile from the nav; confirm city/postcode/email/role shown.
4. Edit display name + city; confirm reflected on profile and home.
5. Submit edit with blank postcode; confirm rejection.
6. Sign out; visit `/profile`; confirm redirect to sign-in.

## Performance Considerations

Negligible — three string columns and a singular CRUD resource at v1 scale. No new indexes needed (locality indexing lives on `walks`, not `users`, for S-05 filtering).

## Migration Notes

One migration adds `display_name` (nullable), `city`, `postcode`. The NOT-NULL conversion uses add → backfill → change-null; existing rows are dev/test only (no real users per roadmap baseline) and receive a documented placeholder. This is the slice where the user locality field "locks in" (PRD §Open Q #6) — a later geolocation model would require a new migration.

## References

- Roadmap item S-02: `context/foundation/roadmap.md`
- PRD: `context/foundation/prd.md` — FR-005, §Business Logic §Locality, §Open Q #6
- Locality precedent: `app/models/walk.rb:17`, `db/schema.rb:44` (walks `city`/`postcode`)
- S-01 patterns: `app/views/registrations/new.html.erb`, `app/views/layouts/application.html.erb` (nav), archived at `context/archive/2026-06-15-signup-and-signin-with-role/`
- Change identity: `context/changes/profile-with-city/change.md`

## Progress

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles. See `references/progress-format.md`.

### Phase 1: Schema, model validations, and sign-up capture

#### Automated

- [x] 1.1 Migration applies cleanly: `docker compose exec web bin/rails db:migrate`
- [x] 1.2 Full suite passes: `docker compose exec web bin/rails test`
- [x] 1.3 Linting passes: `docker compose exec web bundle exec rubocop`

#### Manual

- [x] 1.4 Sign-up form shows required City/Postcode; missing either re-renders with errors, no user created
- [x] 1.5 Successful sign-up persists city/postcode
- [x] 1.6 Existing (backfilled) users still load without error

### Phase 2: Profile resource + nav/home integration

#### Automated

- [ ] 2.1 Profile tests pass: `docker compose exec web bin/rails test test/integration/profiles_test.rb`
- [ ] 2.2 Full suite passes: `docker compose exec web bin/rails test`
- [ ] 2.3 Linting passes: `docker compose exec web bundle exec rubocop`
- [ ] 2.4 Security scan clean: `docker compose exec web bundle exec brakeman --no-pager`

#### Manual

- [ ] 2.5 Nav shows "Profile" link when signed in; opens the profile show page
- [ ] 2.6 Editing display name + city + postcode saves and reflects on profile + home
- [ ] 2.7 Blank city or postcode on edit shows an error and does not save
- [ ] 2.8 Visiting the profile while signed out redirects to sign-in
