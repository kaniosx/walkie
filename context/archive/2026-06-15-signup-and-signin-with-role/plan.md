# S-01: Sign-up + Sign-in with Role Choice — Implementation Plan

## Overview

Add the user-facing UI layer on top of the auth mechanics F-01 built. A visitor can already sign up, sign in, and sign out at a functional level — S-01 makes those flows navigable and presentable: a persistent nav bar, layout-level flash messages, improved sign-up copy (role radios with friendly labels), a role-aware home page, a v1 notice on the password-reset form, minimal CSS, and integration tests covering the new UX behaviour.

## Current State Analysis

F-01 (archived at `context/archive/2026-05-29-auth-and-role-typing/`) produced:
- `User` model with `has_secure_password`, string-backed role enum, immutability validation
- `SessionsController` (sign-in/sign-out, rate limited) and `RegistrationsController` (sign-up, rate limited)
- `app/controllers/concerns/authentication.rb` — `require_authentication`, `current_user` (`helper_method`), `authenticated?`, `start_new_session_for`, `terminate_session`
- `app/views/sessions/new.html.erb` — sign-in form with inline flash rendering
- `app/views/registrations/new.html.erb` — sign-up form with inline flash + role radio buttons (unlabelled: `owner` / `walker` raw enum values)
- `app/views/home/index.html.erb` — "Signed in as X (role)" + sign-out button
- `config/routes.rb` — `resource :session`, `resource :registration`, `resources :passwords`, `root "home#index"`

Functional gaps S-01 closes:
- Application layout (`application.html.erb`) title still reads "Bootstrap Scaffold"; no flash block; no nav element
- Flash is only rendered inline on individual auth views — the home page and any future view silently swallows flash
- Sign-out is only reachable from the home page; no persistent navigation
- Role radios show raw enum strings ("owner" / "walker") instead of user-friendly labels
- `passwords/new` accepts a reset request but email is inert in v1 — no explanation visible

## Desired End State

A visitor opens the app, sees the "Walkie" brand, and can navigate the full sign-up / sign-in / sign-out cycle without typing any URLs. The application layout:
- Shows "Walkie" in the browser tab
- Renders flash alerts and notices globally (no per-view duplication)
- Displays a thin nav bar (visible always) with a "Sign out" action when signed in

The home page shows the signed-in user's email and role plus a one-line role-specific hint ("As a Dog Owner, you'll be able to post walk requests for your dogs" / "As a Dog Walker, you'll be able to see and accept walk requests in your area").

The sign-up form labels the role choice as "I'm a Dog Owner" / "I'm a Dog Walker". The password-reset page carries a visible notice that email reset isn't available in v1. Forms are centred and readable; flash messages are visually distinct.

Verifiable by: `docker compose exec web bin/rails test` green; `rubocop` + `brakeman` clean; manual sign-up → home → sign-out → sign-in round-trip works with readable flash and nav.

### Key Discoveries:

- `Current.user` (via the Rails 8 generator) is exposed as `current_user` helper_method in `authentication.rb:10` — views can call `current_user.owner?` / `current_user.walker?` directly
- `authenticated?` is also a `helper_method` (exposed at `authentication.rb:7`) — safe to use in the layout without a controller call
- The sign-in failure flash is currently set as `alert:` on redirect to `new_session_path`; once flash moves to the layout the inline rendering in `sessions/new.html.erb` must be removed or it will double-render
- F-01 tests exist in `test/integration/` (registration, authentication, sessions) and must stay green throughout

## What We're NOT Doing

- **No Tailwind or CSS framework** — no new build dependency; minimal custom CSS in `application.css` only
- **No role-based routing split** — Owner and Walker land on the same `root_url` (role-specific dashboards are S-02+ territory)
- **No password-reset email wiring** — inert by design in v1; only a user-visible notice is added
- **No Capybara / system tests** — F-03 didn't wire system test infrastructure; integration tests (ActionDispatch) only
- **No SimpleCov gate flip** — the dormant 80% gate is owned by S-04/S-05/S-07 per F-03 plan
- **No changes to the User model, controllers, or routes** — all mechanics are correct from F-01

## Implementation Approach

Three phases in dependency order. Phase 1 changes the layout (the structural foundation all views share) and must land first to avoid double-flash rendering when Phase 2 removes inline flash from views. Phase 2 polishes individual views and adds CSS. Phase 3 writes the integration tests and runs all gates.

## Phase 1: Application layout — title, flash, nav bar

### Overview

Fix the application layout's three gaps: the stale title, missing flash rendering, and missing navigation. These changes are purely additive to the layout; they do not touch any controller or model.

### Changes Required:

#### 1. Fix the application title and app name

**File**: `app/views/layouts/application.html.erb`

**Intent**: Replace the bootstrapper-era "Bootstrap Scaffold" brand with "Walkie" in both the `<title>` tag and the `<meta name="application-name">` tag.

**Contract**: `<title>` becomes `<%= content_for(:title) || "Walkie" %>`; `<meta name="application-name" content="Walkie">`.

#### 2. Add layout-level flash rendering

**File**: `app/views/layouts/application.html.erb`

**Intent**: Render flash alerts and notices once in the layout so every page (home, future owner/walker pages) displays flash without per-view duplication.

**Contract**: Inside `<body>`, before `<%= yield %>`, add conditional divs for `flash[:alert]` and `flash[:notice]`. Use distinct CSS classes (`flash-alert`, `flash-notice`) so Phase 2's CSS can style them differently. Do not use `flash.each` — render the two keys explicitly to keep styling separate.

#### 3. Add a thin nav bar

**File**: `app/views/layouts/application.html.erb`

**Intent**: Give every page a persistent "Walkie" brand link (→ root) and a sign-out action that is always reachable when the user is authenticated.

**Contract**: Add a `<nav>` element inside `<body>` above the flash block. The nav always contains `link_to "Walkie", root_path`. Inside a `<% if authenticated? %>` guard, add `button_to "Sign out", session_path, method: :delete` — this matches the existing route and uses Turbo's form submission natively. The `authenticated?` helper is already a `helper_method` in the `Authentication` concern; no additional controller change needed.

### Success Criteria:

#### Automated Verification:

- Full suite stays green: `docker compose exec web bin/rails test`
- Linting passes: `docker compose exec web bundle exec rubocop`

#### Manual Verification:

- Browser tab title reads "Walkie" on all pages (sign-in, home, etc.)
- Signing in with wrong credentials shows the "Try another email address or password" alert visibly on the sign-in page (flash rendered by layout, not inline)
- The nav bar appears on the home page with the "Sign out" button; "Walkie" brand is clickable
- The nav bar on the sign-in page shows only "Walkie" (no "Sign out" since not authenticated)

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation before proceeding to Phase 2.

---

## Phase 2: Auth view polish + home page + minimal CSS

### Overview

Remove now-redundant inline flash from auth views, improve sign-up copy, add a v1 notice to the password-reset form, update the home page with role-specific hints, and add minimal CSS.

### Changes Required:

#### 1. Remove inline flash from sessions/new

**File**: `app/views/sessions/new.html.erb`

**Intent**: Flash is now rendered by the layout — the inline `tag.div(flash[:alert])` and `tag.div(flash[:notice])` at the top of this view will double-render. Remove them.

**Contract**: Delete the two inline flash `tag.div` calls at the top of the file. Leave the form, the "Forgot password?" link, and all other content unchanged.

#### 2. Remove inline flash and improve role labels in registrations/new

**File**: `app/views/registrations/new.html.erb`

**Intent**: Remove the inline `flash[:alert]` div (layout now handles it), and replace the raw role enum strings with user-friendly labels.

**Contract**: Remove the `flash[:alert]` div at the top. Inside the role `<fieldset>`, replace the `User.roles.keys.each` loop (which renders "owner" / "walker" as label text) with explicit radio inputs labelled "I'm a Dog Owner" and "I'm a Dog Walker" — one `form.radio_button :role, "owner"` + label "I'm a Dog Owner", one for "walker". Keep the `<legend>` text ("I am signing up as a…" or rephrase to "Choose your role"), keep the `checked:` pre-selection logic, and keep all other form fields unchanged.

#### 3. Add v1 notice to the password-reset request form

**File**: `app/views/passwords/new.html.erb`

**Intent**: A user who clicks "Forgot password?" submits the form but receives no email in v1 (delivery is inert). Add an explicit notice so they aren't confused.

**Contract**: Add a visible paragraph above the form explaining that email-based password reset is not available in v1 — e.g. "Password reset by email is not available in this version. If you've forgotten your password, please create a new account." Do not remove the form itself (the route and controller remain in place).

#### 4. Update the home page with role hint, remove sign-out

**File**: `app/views/home/index.html.erb`

**Intent**: Remove the sign-out button (now in the nav bar) and add a one-line role-specific hint so the signed-in user understands their role's purpose in Walkie.

**Contract**: Remove `button_to "Sign out", session_path, method: :delete`. Keep "Signed in as [email]" display. Add a conditional block: if `current_user.owner?`, show "As a Dog Owner, you'll be able to post walk requests for your dogs."; if `current_user.walker?`, show "As a Dog Walker, you'll be able to see and accept walk requests in your area." Both are `<p>` tags.

#### 5. Minimal CSS

**File**: `app/assets/stylesheets/application.css`

**Intent**: Make the auth forms and nav bar readable without introducing a CSS framework dependency.

**Contract**: Add rules for: a `nav` element (flex layout, space-between, with padding and a bottom border); a `.flash-alert` class (red text or background); a `.flash-notice` class (green text or background); a `.form-container` or centred form wrapper (max-width ~400px, margin auto, padding). Apply the form wrapper class to the sign-in and sign-up forms by wrapping their content in a `<div class="form-container">` in their respective views.

### Success Criteria:

#### Automated Verification:

- Full suite stays green: `docker compose exec web bin/rails test`
- Linting passes: `docker compose exec web bundle exec rubocop`

#### Manual Verification:

- Sign-up form shows "I'm a Dog Owner" / "I'm a Dog Walker" radio labels
- Signing up without choosing a role still shows validation errors (inline model errors block, unchanged)
- Password-reset page shows the v1 notice above the form
- Home page shows role-specific hint; no sign-out button visible in the page body (only in the nav)
- Forms are visually centered; flash messages are distinguishable (alert vs notice)

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation before proceeding to Phase 3.

---

## Phase 3: Navigation + flash integration tests, full gate

### Overview

Write integration tests for the new UX behaviour (nav bar auth state, flash visibility), then run all gates.

### Changes Required:

#### 1. Navigation and flash integration tests

**File**: `test/integration/navigation_test.rb`

**Intent**: Verify the three new UX behaviours Phase 1 and 2 introduced: (a) the nav sign-out button appears only when authenticated, (b) the nav sign-out button is absent on unauthenticated pages, and (c) a flash alert from a failed sign-in is rendered on the subsequent page.

**Contract**: Three tests:
1. `"nav bar shows sign-out when authenticated"` — create a user, POST session, GET /, assert response :success, assert response body includes "Sign out".
2. `"nav bar does not show sign-out when unauthenticated"` — GET /session/new (no session), assert response :success, assert response body does NOT include "Sign out" (or more precisely, does not include the sign-out form action).
3. `"flash alert is visible after a failed sign-in attempt"` — POST session with wrong password, follow_redirect!, assert response body includes "Try another email address or password".

These tests intentionally do NOT duplicate F-01's auth-flow assertions (role persistence, session lifecycle) — they test only the layout/UX behaviour S-01 added.

### Success Criteria:

#### Automated Verification:

- New navigation tests pass: `docker compose exec web bin/rails test test/integration/navigation_test.rb`
- Full suite passes: `docker compose exec web bin/rails test`
- Linting passes: `docker compose exec web bundle exec rubocop`
- Security scan clean: `docker compose exec web bundle exec brakeman --no-pager`

#### Manual Verification:

- Full manual round-trip: sign up as Owner → home page shows "Dog Owner" hint + nav sign-out → click sign-out → redirected to sign-in → sign in → back on home
- Full manual round-trip: sign up as Walker → home page shows "Dog Walker" hint
- Flash visible: attempt sign-in with wrong password → "Try another email address or password" appears on sign-in page

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation. This completes S-01.

---

## Testing Strategy

### Unit Tests:

None new — the User model is fully tested in F-01 (`test/models/user_test.rb`). No model changes in S-01.

### Integration Tests:

- `test/integration/navigation_test.rb` (new, Phase 3): nav sign-out auth/unauth states; flash rendered after failed sign-in
- Existing F-01 tests (`registration_test.rb`, `authentication_test.rb`, `sessions_test.rb`) must stay green throughout

### Manual Testing Steps:

1. Sign up as Owner; verify home page shows "Dog Owner" hint and nav has sign-out
2. Click sign-out; verify redirect to sign-in
3. Sign in as Owner; verify nav shows sign-out again
4. Sign up as Walker (new incognito window); verify home page shows "Dog Walker" hint
5. Attempt sign-in with wrong password; verify flash alert appears on the sign-in page
6. Visit `/passwords/new`; verify v1 notice is visible above the reset form

## Performance Considerations

No performance impact. CSS and view changes are static. No new database queries.

## Migration Notes

No migrations. All changes are to views, the application layout, and the CSS file.

## References

- Roadmap item S-01: `context/foundation/roadmap.md`
- PRD: `context/foundation/prd.md` — FR-001..FR-004, §Access Control
- Foundation: `context/archive/2026-05-29-auth-and-role-typing/plan.md` (F-01, done)
- Change identity: `context/changes/signup-and-signin-with-role/change.md`

## Progress

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles. See `references/progress-format.md`.

### Phase 1: Application layout — title, flash, nav bar

#### Automated

- [x] 1.1 Full suite stays green: `docker compose exec web bin/rails test` — 2262993
- [x] 1.2 Linting passes: `docker compose exec web bundle exec rubocop` — 2262993

#### Manual

- [x] 1.3 Browser tab title reads "Walkie" on all pages — 2262993
- [x] 1.4 Failed sign-in shows flash alert visibly on the sign-in page — 2262993
- [x] 1.5 Authenticated home page nav shows "Sign out" button — 2262993
- [x] 1.6 Unauthenticated sign-in page nav shows no "Sign out" — 2262993

### Phase 2: Auth view polish + home page + minimal CSS

#### Automated

- [x] 2.1 Full suite stays green: `docker compose exec web bin/rails test` — 7f9ecba
- [x] 2.2 Linting passes: `docker compose exec web bundle exec rubocop` — 7f9ecba

#### Manual

- [x] 2.3 Sign-up form shows "I'm a Dog Owner" / "I'm a Dog Walker" radio labels — 7f9ecba
- [x] 2.4 Submitting sign-up without a role still shows validation errors — 7f9ecba
- [x] 2.5 Password-reset page shows v1 notice above the form — 7f9ecba
- [x] 2.6 Home page shows role-specific hint; sign-out button absent from page body — 7f9ecba
- [x] 2.7 Forms are visually centered; flash alert and notice are visually distinct — 7f9ecba

### Phase 3: Navigation + flash integration tests, full gate

#### Automated

- [x] 3.1 New navigation tests pass: `docker compose exec web bin/rails test test/integration/navigation_test.rb` — b5c2270
- [x] 3.2 Full suite passes: `docker compose exec web bin/rails test` — b5c2270
- [x] 3.3 Linting passes: `docker compose exec web bundle exec rubocop` — b5c2270
- [x] 3.4 Security scan clean: `docker compose exec web bundle exec brakeman --no-pager` — b5c2270

#### Manual

- [x] 3.5 Full Owner round-trip: sign up → home (Dog Owner hint + nav) → sign out → sign in → home — b5c2270
- [x] 3.6 Full Walker round-trip: sign up → home (Dog Walker hint + nav) — b5c2270
- [x] 3.7 Flash visible after wrong-password sign-in attempt — b5c2270
