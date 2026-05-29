# F-01: Rails 8 Auth + Role-Typed Accounts — Implementation Plan

## Overview

Stand up the authentication foundation for Walkie: a `User` model with bcrypt-hashed passwords, session-based sign-in/sign-out, a thin sign-up (registration) path, and a **binding `role`** (Owner XOR Walker) chosen at registration and immutable thereafter. This is roadmap item **F-01** — the first foundation on the critical path; it unlocks S-01 and transitively every other slice (each needs an authenticated user with a role). The work leans on Rails 8.1's built-in `bin/rails generate authentication`, then layers role typing, a registration controller, and core auth tests on top.

## Current State Analysis

The repo is a bare Rails 8.1.3 / Ruby 3.4.9 skeleton (confirmed by direct inspection):

- `app/models/` — only `application_record.rb`. No `User`, no domain models.
- `app/controllers/` — only `application_controller.rb` (includes `allow_browser` + `stale_when_importmap_changes`; **does not** include any auth concern).
- `config/routes.rb` — only the `/up` healthcheck.
- `db/` — only `seeds.rb`. **No `db/migrate/`, no `db/schema.rb`.** The Solid stack tables exist in the live DB via `db:prepare`, but there is no checked-in migration history yet.
- `test/` — **does not exist** (CLAUDE.md tripwire). `bin/rails generate authentication` will create it as a side effect.
- `Gemfile` — `bcrypt` is present but **commented out**. (`bcrypt_pbkdf` in `Gemfile.lock` is Kamal's SSH dependency, not the password hasher.)

Dev runs inside Docker (`docker-compose.yml`: services `web` + `db`). One-off Rails commands must be `docker compose exec web …` — there is no Ruby toolchain on the host.

**Rails 8.1 `bin/rails generate authentication` produces** (verified against the Rails 8 generator contract): `app/models/user.rb` (`has_secure_password`, `has_many :sessions`, normalizes `email_address`), `app/models/session.rb`, `app/models/current.rb` (`Current.session`, `Current.user`), `app/controllers/concerns/authentication.rb` (`require_authentication`, `allow_unauthenticated_access`, `start_new_session_for`, `terminate_session`, `resume_session`), `app/controllers/sessions_controller.rb` (with rate limiting), `app/controllers/passwords_controller.rb` + `app/mailers/passwords_mailer.rb` + views, `app/views/sessions/new.html.erb`, routes (`resource :session`, `resources :passwords, param: :token`), a migration creating `users` (`email_address`, `password_digest`) and `sessions` (`user` ref, `ip_address`, `user_agent`), and it uncomments `gem "bcrypt"` and includes `Authentication` in `ApplicationController`. **It does NOT generate a sign-up / registration path** and it exposes the current user as `Current.user`, not `current_user`.

## Desired End State

A visitor can sign up choosing Owner or Walker, sign in, and sign out; the chosen role is persisted, required, and immutable after creation; `current_user` and `require_authentication` are available to all controllers; and a core Minitest suite covers the security-load-bearing behavior. Verifiable by: `docker compose exec web bin/rails test` is green, rubocop + brakeman + bundler-audit are clean, and a manual sign-up → sign-out → sign-in round-trip works in the browser at `:3000`.

### Key Discoveries:

- `bcrypt` is commented out in `Gemfile:24` — the generator uncomments it; a `bundle install` (and Docker layer rebuild) is required before the app boots with `has_secure_password`.
- `ApplicationController` (`app/controllers/application_controller.rb:1`) has no auth wiring — the generator adds `include Authentication`; confirm it landed.
- The generator names the email column `email_address` and exposes `Current.user` — both are kept (decision) and a `current_user` helper is added so the roadmap's named hook exists.
- No `test/` dir exists — the generator creates it; do not claim tests pass before then (CLAUDE.md tripwire).
- DB name is still `bootstrap_scaffold_*` in `docker-compose.yml` + `config/database.yml` — **left as-is for this change** (see Open Risks).

## What We're NOT Doing

- **No polished sign-up/sign-in UX** — F-01 ships a minimal working registration form; styling, role-radio layout, friendly validation copy, and post-auth redirects are **S-01** (`signup-and-signin-with-role`).
- **No working password-reset email** — the generated PasswordsController/mailer/routes are kept but left inert (no SMTP, not linked in the UI). Real email wiring is a later task.
- **No domain models** — `Dog`, `Walk`, the state machine, and any role→capability authorization beyond authentication are **F-02 / the slices**.
- **No SimpleCov / coverage tooling / CI** — that is **F-03** (`test-infrastructure-scaffold`). F-01 writes plain Minitest tests; F-03 later measures them.
- **No DB rename** (`bootstrap_scaffold_*` → `walkie_*`) — orthogonal to auth; noted as a risk.
- **No STI, no dual-role, no role switching** — `enum`-typed role, one role per user (PRD §Access Control).

## Implementation Approach

Use the generator to get the golden-path auth scaffold, then make three additive changes: (1) type the account with a string-backed `role` enum and lock it after create, (2) add a thin RegistrationsController for sign-up, (3) write core auth tests. Keep every generator default that becomes a downstream contract surface (`email_address`, `Current.user`) and add only the named hook the roadmap promised (`current_user`). Phases are ordered so each ends at a verifiable, bootable state.

## Critical Implementation Details

- **Generator ordering & bundle.** The generator uncomments `bcrypt` but the running container's `bundle_cache` volume won't have it until `bundle install` runs. After generating, run `bundle install` inside the container; if the app still won't boot with `has_secure_password`, a `make reset` (rebuild) refreshes the bundle layer. Run the generator before writing the role migration so the `users` table migration exists first and the role migration stacks cleanly on top.
- **Role immutability.** Enforce at the model with a validation on update (reject a changed `role` on a persisted record) rather than `attr_readonly` alone — `attr_readonly` silently ignores the change, whereas a validation surfaces it and is unit-testable. `role` must be set at creation (NOT NULL, no DB default) so the choice is always explicit.
- **`current_user` helper.** Add a `current_user` method (delegating to `Current.user`) and expose it as a `helper_method` so both controllers and views can use the roadmap-named hook without rewriting the generator's `Current.user` internals.

## Phase 1: Auth foundation scaffold

### Overview

Generate the Rails 8 authentication scaffold, get the app booting with bcrypt, wire the auth concern and the `current_user` hook, and neutralize the password-reset mailer so it ships inert.

### Changes Required:

#### 1. Run the authentication generator

**File**: generated set (`app/models/{user,session,current}.rb`, `app/controllers/concerns/authentication.rb`, `app/controllers/{sessions,passwords}_controller.rb`, `app/mailers/passwords_mailer.rb`, `app/views/sessions/*`, `app/views/passwords/*`, `db/migrate/*_create_users.rb` + `*_create_sessions.rb`, `config/routes.rb`, `Gemfile`)

**Intent**: Produce the standard Rails 8 session-auth scaffold rather than hand-rolling it, so the app gets `has_secure_password`, the `Authentication` concern, sign-in/out, and the session model on the framework's golden path.

**Contract**: Run `docker compose exec web bin/rails generate authentication`, then `docker compose exec web bundle install`. Outcome: `gem "bcrypt"` uncommented in `Gemfile`; `include Authentication` present in `ApplicationController`; routes gain `resource :session` and `resources :passwords, param: :token`; `test/` directory now exists.

#### 2. Add the `current_user` hook

**File**: `app/controllers/concerns/authentication.rb` (or `app/controllers/application_controller.rb`)

**Intent**: Expose the roadmap-named `current_user` accessor that every later slice will call, delegating to the generator's `Current.user`.

**Contract**: A `current_user` method returning `Current.user`, registered via `helper_method :current_user` so views can use it too. Do not remove or rename `Current.user`.

#### 3. Neutralize password-reset email delivery

**File**: `config/environments/development.rb` (and confirm `config/environments/production.rb`)

**Intent**: Keep the generated password-reset code present (per §Access Control) but inert, avoiding any SMTP/email-provider dependency in v1 (FR-003 rationale).

**Contract**: Development mail delivery set so a reset attempt does not raise (e.g. `:test` delivery method or equivalent); no reset link is added to any view. No production SMTP credentials introduced.

### Success Criteria:

#### Automated Verification:

- Bundle installs cleanly: `docker compose exec web bundle install`
- Generator migrations apply: `docker compose exec web bin/rails db:migrate`
- Generated suite passes: `docker compose exec web bin/rails test`
- Linting passes: `docker compose exec web bundle exec rubocop`

#### Manual Verification:

- App boots at `http://localhost:3000` with no exceptions (`/up` returns 200).
- `/session/new` renders the sign-in form.
- A reset attempt via `/passwords/new` does not raise (delivery is inert).

**Implementation Note**: After this phase and all automated verification passes, pause for manual confirmation before proceeding.

---

## Phase 2: Role-typed User model

### Overview

Add the binding `role` to `User`: a string-backed enum, NOT NULL with no default, immutable after creation — the load-bearing typing every slice depends on.

### Changes Required:

#### 1. Migration adding `role`

**File**: `db/migrate/*_add_role_to_users.rb`

**Intent**: Add a required `role` column so every user is explicitly Owner or Walker, enforced at the DB level.

**Contract**: `role` column, type `string`, `null: false`, **no default** (forces explicit choice). Generate via `docker compose exec web bin/rails generate migration AddRoleToUsers role:string`, then edit to add `null: false`. (No existing rows to backfill — `users` was just created in Phase 1.)

#### 2. Role enum + immutability on User

**File**: `app/models/user.rb`

**Intent**: Give role string-enum semantics (scopes + predicates) and make it immutable after create, enforcing PRD §Access Control "a user is one or the other… no role switching" outside the UI.

**Contract**: `enum role: { owner: "owner", walker: "walker" }`; presence validation on `role`; and a validation that rejects changing `role` on a persisted record (added to `errors` on update if `role_changed?` && `persisted?`). Yields `user.owner?` / `user.walker?` predicates and `User.owner` / `User.walker` scopes.

### Success Criteria:

#### Automated Verification:

- Migration applies: `docker compose exec web bin/rails db:migrate`
- Model tests pass: `docker compose exec web bin/rails test test/models/user_test.rb`
- Linting passes: `docker compose exec web bundle exec rubocop`

#### Manual Verification:

- In console, `User.create!(email_address: "x@y.z", password: "secret123", role: "owner")` succeeds; creating without a role raises a validation error.
- In console, loading that user, setting `role = "walker"` and saving is rejected.

**Implementation Note**: After this phase and all automated verification passes, pause for manual confirmation before proceeding.

---

## Phase 3: Sign-up (registration) path

### Overview

Add the thin registration flow the generator omits: a controller + route + minimal form that creates a user with a chosen role and signs them in. UX polish is deferred to S-01.

### Changes Required:

#### 1. RegistrationsController

**File**: `app/controllers/registrations_controller.rb`

**Intent**: Let an unauthenticated visitor create an account with email, password, and a role, then start an authenticated session.

**Contract**: `new` (renders the form) and `create` (permits `email_address`, `password`, `password_confirmation`, `role`; on success calls the concern's `start_new_session_for(user)` and redirects to root; on failure re-renders `new`). Marked `allow_unauthenticated_access`. Strong params must whitelist `role` only here (registration) — it is never permitted on any update path (immutability).

#### 2. Route + minimal view

**File**: `config/routes.rb`, `app/views/registrations/new.html.erb`, and a `root` route

**Intent**: Expose sign-up at a stable path and give signed-in users a landing page.

**Contract**: `resource :registration, only: [:new, :create]` (or `get "sign_up"` + `post`); a `root` route pointing at a minimal authenticated placeholder (e.g. a simple "signed in as …" page or reuse an existing controller) so post-registration redirect resolves. View: email, password, password_confirmation, and a role selector (plain `select`/radios — styling is S-01).

### Success Criteria:

#### Automated Verification:

- Integration test passes: `docker compose exec web bin/rails test test/integration/registration_test.rb`
- Full suite passes: `docker compose exec web bin/rails test`
- Linting passes: `docker compose exec web bundle exec rubocop`

#### Manual Verification:

- Visiting the sign-up page, submitting email + password + role "Walker" creates the user, signs them in, and lands on root.
- The created user has `role == "walker"` (verify in console or via the landing page).
- Submitting without choosing a role re-renders the form with an error.

**Implementation Note**: After this phase and all automated verification passes, pause for manual confirmation before proceeding.

---

## Phase 4: Guardrail verification & hardening

### Overview

Prove the auth guard works end-to-end, ensure the whole suite is green, and clear the security/lint gates.

### Changes Required:

#### 1. Authentication-required integration test

**File**: `test/integration/authentication_test.rb`

**Intent**: Verify that the default `require_authentication` before-action redirects an anonymous request away from a protected route to sign-in — the binding that all role-separation guardrails later build on.

**Contract**: A protected action (the `root`/placeholder from Phase 3, which is NOT marked `allow_unauthenticated_access`) requested without a session redirects to `/session/new`; the sign-up, sign-in, and (inert) password routes remain reachable while unauthenticated.

#### 2. Sign-in / sign-out round-trip test

**File**: `test/integration/sessions_test.rb` (extend generator's if present)

**Intent**: Lock the core session lifecycle: a registered user signs in, reaches a protected page, signs out, and is gated again.

**Contract**: Create a user via fixture/factory, POST credentials to `/session`, assert access to the protected route, DELETE `/session`, assert redirect-to-sign-in on the protected route afterward.

### Success Criteria:

#### Automated Verification:

- Full suite passes: `docker compose exec web bin/rails test`
- Linting passes: `docker compose exec web bundle exec rubocop`
- Security scan clean: `docker compose exec web bundle exec brakeman --no-pager`
- Dependency audit clean: `docker compose exec web bundle exec bundler-audit check --update`

#### Manual Verification:

- Visiting any protected route while signed out redirects to the sign-in page.
- Full manual round-trip: sign up (Owner) → land on root → sign out → sign in → land on root again.

**Implementation Note**: After this phase and all automated verification passes, pause for manual confirmation. This completes F-01.

---

## Testing Strategy

### Unit Tests:

- `role` enum yields predicates/scopes; presence validation rejects a missing role.
- `role` is immutable after create (update with a changed role fails validation).
- `has_secure_password` authenticates correct credentials and rejects wrong ones.

### Integration Tests:

- Sign-up creates a user with the chosen role and starts a session.
- `require_authentication` redirects anonymous users from a protected route to sign-in.
- Sign-in → protected access → sign-out → gated-again round-trip.

### Manual Testing Steps:

1. Sign up as Owner; confirm landing on root and `role == "owner"`.
2. Sign out; confirm protected routes redirect to sign-in.
3. Sign in with the same credentials; confirm access restored.
4. Attempt `/passwords/new`; confirm no exception (inert delivery).

## Performance Considerations

Negligible for v1 (small scale per PRD). bcrypt cost is the only notable cost and is standard. The free-tier Postgres cold-start caveat (deploy-plan Risk Register) is an infra concern, not introduced by this change.

## Migration Notes

Two migration steps: the generator's `create_users` + `create_sessions`, then `add_role_to_users` (`null: false`, no default). No existing data to backfill — `users` is created in the same change. This change also establishes the first checked-in `db/schema.rb`.

## References

- Roadmap item: `context/foundation/roadmap.md` §F-01
- PRD: `context/foundation/prd.md` — FR-001..FR-004, §Access Control, §Non-Functional (role separation)
- Change identity: `context/changes/auth-and-role-typing/change.md`
- CLAUDE.md tripwires: no `test/` dir yet; stale `bootstrap_scaffold_*` DB name; no bundler on host

## Progress

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles. See `references/progress-format.md`.

### Phase 1: Auth foundation scaffold

#### Automated

- [x] 1.1 Bundle installs cleanly: `docker compose exec web bundle install` — 34e3349
- [x] 1.2 Generator migrations apply: `docker compose exec web bin/rails db:migrate` — 34e3349
- [x] 1.3 Generated suite passes: `docker compose exec web bin/rails test` — 34e3349
- [x] 1.4 Linting passes: `docker compose exec web bundle exec rubocop` — 34e3349

#### Manual

- [x] 1.5 App boots at `http://localhost:3000` with no exceptions (`/up` returns 200) — 34e3349
- [x] 1.6 `/session/new` renders the sign-in form — 34e3349
- [x] 1.7 A reset attempt via `/passwords/new` does not raise (delivery is inert) — 34e3349

### Phase 2: Role-typed User model

#### Automated

- [x] 2.1 Migration applies: `docker compose exec web bin/rails db:migrate` — eed77d6
- [x] 2.2 Model tests pass: `docker compose exec web bin/rails test test/models/user_test.rb` — eed77d6
- [x] 2.3 Linting passes: `docker compose exec web bundle exec rubocop` — eed77d6

#### Manual

- [x] 2.4 Console: create with role succeeds; create without role raises validation error — eed77d6
- [x] 2.5 Console: changing role on a persisted user is rejected — eed77d6

### Phase 3: Sign-up (registration) path

#### Automated

- [x] 3.1 Integration test passes: `docker compose exec web bin/rails test test/integration/registration_test.rb` — 8d847f1
- [x] 3.2 Full suite passes: `docker compose exec web bin/rails test` — 8d847f1
- [x] 3.3 Linting passes: `docker compose exec web bundle exec rubocop` — 8d847f1

#### Manual

- [x] 3.4 Sign-up with role "Walker" creates user, signs in, lands on root — 8d847f1
- [x] 3.5 Created user has `role == "walker"` — 8d847f1
- [x] 3.6 Submitting without a role re-renders the form with an error — 8d847f1

### Phase 4: Guardrail verification & hardening

#### Automated

- [x] 4.1 Full suite passes: `docker compose exec web bin/rails test` — 3fad848
- [x] 4.2 Linting passes: `docker compose exec web bundle exec rubocop` — 3fad848
- [x] 4.3 Security scan clean: `docker compose exec web bundle exec brakeman --no-pager` — 3fad848
- [x] 4.4 Dependency audit clean: `docker compose exec web bundle exec bundler-audit check --update` — 3fad848

#### Manual

- [x] 4.5 Protected route while signed out redirects to sign-in — 3fad848
- [x] 4.6 Full round-trip: sign up (Owner) → root → sign out → sign in → root — 3fad848
