# Auth + Profile Screens — Tailwind Styling

## Overview

Style the four existing auth and profile views (sign-in, sign-up, profile show, profile edit) with Tailwind CSS. No behaviour changes — only CSS classes are added or swapped in ERB views and one rule-set is removed from `application.css`. All views become visually consistent with the Tailwind-styled navbar delivered in U-02.

## Current State Analysis

Four views exist, each wrapped in `div.form-container` (vanilla CSS, max-width 400px centred). Validation errors render in `div.form-errors` (vanilla CSS red box). Form inputs have stub padding rules in `application.css`. The navbar (U-02) is 100% Tailwind; these forms are the only remaining vanilla-CSS-heavy surfaces. The design token layer (emerald = `primary`, stone = `neutral`) is established in `config/tailwind.config.js`.

## Desired End State

Sign-in, sign-up, profile show, and profile edit each render as a centred white card, visually consistent with each other and with the navbar's design language. Inputs have stone borders and primary-coloured focus rings. The primary action button uses `bg-primary-600`. Validation error banners are red (Tailwind, not vanilla CSS). Profile show uses a clean definition-list layout. All four pages work on mobile without horizontal scroll. `application.css` no longer contains `.form-container`, `.form-errors`, or stub input rules.

### Key Discoveries

- `app/assets/stylesheets/application.css` — contains `.form-container`, `.form-errors`, and input stub rules to be removed; `.flash-alert`, `.flash-notice`, `.notice-v1` stay
- `app/views/sessions/new.html.erb` — sign-in; `.form-container` wrapper, no validation errors block
- `app/views/registrations/new.html.erb` — sign-up; `.form-container` + `.form-errors` + `<fieldset>` for role radio buttons
- `app/views/profiles/show.html.erb` — `.form-container` + `<dl>` for key/value display + "Edit profile" link
- `app/views/profiles/edit.html.erb` — `.form-container` + `.form-errors` + three fields + Cancel link
- `config/tailwind.config.js` — emerald as `primary`, stone as `neutral`, system font stack
- `app/views/layouts/_nav.html.erb` — established Tailwind patterns to match: `text-stone-700`, `bg-primary-600`, `hover:bg-primary-700`, `rounded-md`, `text-sm`

## What We're NOT Doing

- No controller, route, or model changes
- No JS or Stimulus additions
- No inline per-field validation error layout — banner pattern retained
- No `.flash-alert` / `.flash-notice` / `.notice-v1` migration
- No `dogs/` views — those are U-04 scope
- No walk-related views

## Implementation Approach

Three phases: remove the vanilla CSS rules so there are no conflicts, then style the auth views (sign-in, sign-up), then the profile views (show, edit). Each view replaces its `class="form-container"` wrapper with a Tailwind card and adds classes to every interactive element. The card, input, button, and error-banner class sets are defined once in Phase 2 and applied consistently across all four views.

## Critical Implementation Details

All four views share the same card, label, input, button, and error-banner shape. Mismatched class strings across views produce an inconsistent UI that is hard to spot without a side-by-side comparison — use the class sets defined in Phase 2 §sign-in verbatim on every subsequent view.

---

## Phase 1: CSS Cleanup

### Overview

Remove the vanilla CSS rule groups from `application.css` that will be replaced by Tailwind utilities in Phases 2 and 3.

### Changes Required:

#### 1. Remove form-related vanilla CSS

**File:** `app/assets/stylesheets/application.css`

**Intent:** Delete the `.form-container {}`, `.form-container input[type="email"]`, `.form-container input[type="password"]`, and `.form-errors {}` rule groups. They become dead code once the views carry Tailwind classes.

**Contract:** Remove every rule whose selector begins with `.form-container` or `.form-errors`. Do not touch `.flash-alert`, `.flash-notice`, or `.notice-v1`.

### Success Criteria:

#### Automated Verification:

- `application.css` no longer contains the strings `form-container` or `form-errors`
- Tailwind pipeline compiles without error: `docker compose exec web bin/rails assets:precompile`

#### Manual Verification:

- Application loads and the navbar and layout remain intact after the CSS removal

---

## Phase 2: Style Auth Views

### Overview

Apply Tailwind classes to the sign-in and sign-up views, replacing the `.form-container` wrapper and adding classes to every element. Each label+input pair is wrapped in `<div class="mb-4">` to replace the current `<br>` separators.

### Changes Required:

#### 1. Sign-in view

**File:** `app/views/sessions/new.html.erb`

**Intent:** Replace `class="form-container"` on the outer `<div>` with the Tailwind card. Wrap each label+input pair in a `<div class="mb-4">`. Add label, input, primary button, and link classes.

**Contract:** Use these class sets — the same strings apply to every view in this change:
- Card: `max-w-sm mx-auto mt-10 px-8 py-10 bg-white rounded-xl shadow-sm ring-1 ring-stone-200`
- `<h1>`: `text-2xl font-semibold text-stone-900 mb-6`
- Label: `block text-sm font-medium text-stone-700 mb-1`
- Text/email/password input: `block w-full rounded-md border border-stone-300 px-3 py-2 text-sm placeholder-stone-400 focus:outline-none focus:ring-2 focus:ring-primary-500 focus:border-primary-500`
- Submit: `mt-4 w-full rounded-md bg-primary-600 px-4 py-2 text-sm font-medium text-white hover:bg-primary-700 focus:outline-none focus:ring-2 focus:ring-primary-500`
- Inline link: `text-sm text-primary-600 hover:text-primary-700`
- Link wrapper `<div>`: `mt-4 space-y-2` (wraps the two link_to helpers at the bottom)

#### 2. Sign-up view

**File:** `app/views/registrations/new.html.erb`

**Intent:** Same card + label + input + primary button treatment as sign-in. Style the error banner block and the role `<fieldset>`.

**Contract:**
- Card, labels, inputs, submit, links: same class sets as Phase 2 §sign-in
- Error banner `<div>`: `mb-4 rounded-md border border-red-300 bg-red-50 p-4 text-sm text-red-700`; inner `<ul>`: `list-disc list-inside space-y-1`
- `<fieldset>`: `mt-2 rounded-md border border-stone-200 p-4`
- `<legend>`: `text-sm font-medium text-stone-700 px-1`
- Each radio `<label>`: `flex items-center gap-2 text-sm text-stone-700 cursor-pointer`

### Success Criteria:

#### Automated Verification:

- Rubocop passes: `docker compose exec web bundle exec rubocop`
- Brakeman clean: `docker compose exec web bundle exec brakeman --no-pager`

#### Manual Verification:

- Sign-in renders as a centred white card on desktop and at 375 px mobile width (no horizontal scroll)
- Sign-up renders the same card with the role fieldset visually distinct
- Submitting the sign-up form with all fields blank shows the red error banner
- Selecting a role radio button and submitting creates a user with the correct role
- Tabbing through all inputs follows DOM order with visible primary-coloured focus rings

**Implementation Note:** Pause here after manual checks pass before proceeding to Phase 3.

---

## Phase 3: Style Profile Views

### Overview

Apply the same Tailwind card and form treatment to profile show and profile edit.

### Changes Required:

#### 1. Profile show view

**File:** `app/views/profiles/show.html.erb`

**Intent:** Replace `class="form-container"` with the Tailwind card. Style the `<dl>` as a spaced list with muted term labels and bold values. Style the "Edit profile" link.

**Contract:**
- Card: same class set as Phase 2
- `<h1>`: same class set as Phase 2
- `<dl>`: `mt-4 space-y-4`
- `<dt>`: `text-xs font-medium uppercase tracking-wide text-stone-500`
- `<dd>`: `mt-0.5 text-sm text-stone-900`
- "Edit profile" `link_to`: `inline-block mt-6 text-sm font-medium text-primary-600 hover:text-primary-700`

#### 2. Profile edit view

**File:** `app/views/profiles/edit.html.erb`

**Intent:** Same card + error banner + label + input + primary submit button treatment as sign-up. The "Cancel" link is styled as a subordinate text link, not a button.

**Contract:**
- Card, error banner, labels, inputs, submit: same class sets as Phase 2
- "Cancel" `link_to`: `ml-4 text-sm text-stone-500 hover:text-stone-700` (next to the submit button, not on its own line — wrap submit + Cancel in `<div class="mt-4 flex items-center">`)

### Success Criteria:

#### Automated Verification:

- Rubocop passes: `docker compose exec web bundle exec rubocop`
- Brakeman clean: `docker compose exec web bundle exec brakeman --no-pager`

#### Manual Verification:

- Profile show: card renders, definition list displays cleanly, "Edit profile" link goes to edit form
- Profile edit: card renders, leaving city/postcode blank shows red error banner, saving valid values redirects to profile show with a flash notice
- All four pages have no horizontal scroll at 375 px viewport width

---

## Testing Strategy

### Automated Tests:

No new tests required — this is a view-only styling change. Existing model and controller tests cover the business logic. Rubocop and Brakeman serve as the automated gate.

### Manual Testing Steps:

1. Sign up as a new Owner — card renders, role radio works, error banner appears on blank submit
2. Sign in — card renders, success redirects home with flash notice
3. Visit `/profile` — definition list renders cleanly with muted labels and bold values
4. Click "Edit profile" — card renders, blank city triggers red banner, valid save shows flash notice
5. Verify all four pages at 375 px width in browser dev tools — no horizontal scroll anywhere

## References

- Roadmap slice U-03: `context/foundation/roadmap.md`
- Tailwind config: `config/tailwind.config.js`
- application.css: `app/assets/stylesheets/application.css`
- Navbar pattern reference: `app/views/layouts/_nav.html.erb`

## Progress

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles.

### Phase 1: CSS Cleanup

#### Automated

- [x] 1.1 `application.css` contains no `form-container` or `form-errors` strings — bdf5b3d
- [x] 1.2 Tailwind pipeline compiles without error — bdf5b3d

#### Manual

- [x] 1.3 Application loads and layout remains intact after CSS removal — bdf5b3d

### Phase 2: Style Auth Views

#### Automated

- [x] 2.1 Rubocop passes
- [x] 2.2 Brakeman clean

#### Manual

- [x] 2.3 Sign-in card renders on desktop and 375 px mobile (no horizontal scroll)
- [x] 2.4 Sign-up card renders with visible role fieldset
- [x] 2.5 Sign-up error banner appears in red on blank submit
- [x] 2.6 Role radio selection produces the correct role after sign-up
- [x] 2.7 Focus ring visible on all inputs (tab navigation)

### Phase 3: Style Profile Views

#### Automated

- [ ] 3.1 Rubocop passes
- [ ] 3.2 Brakeman clean

#### Manual

- [ ] 3.3 Profile show card renders with clean definition list
- [ ] 3.4 Profile edit card renders; blank city shows red error banner
- [ ] 3.5 Valid profile save redirects with flash notice
- [ ] 3.6 All four pages no horizontal scroll at 375 px
