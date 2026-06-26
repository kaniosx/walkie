# Owner Dashboard Screens — Tailwind Styling

## Overview

Style the five Owner-facing views (`dogs/index`, `dogs/new`, `dogs/edit`, `dogs/_form`, `walks/index`) with Tailwind CSS. No behaviour changes — only CSS classes are added or swapped in ERB views and a shared badge helper is added to `application_helper.rb`. All views become visually consistent with the U-02 navbar and U-03 auth/profile screens.

## Current State Analysis

Five views exist, each wrapped in `div.form-container` (the CSS rule was removed in U-03, so these wrappers have no visual effect today). Walk state is displayed as plain `.humanize` text with no colour differentiation. The Tailwind design token layer (emerald = `primary`, stone = `neutral`) and the card/input/button class strings are fully established in U-03.

## Desired End State

- `dogs/index` renders dog cards (compact: name + breed headline, optional weight/notes as secondary text, full-width "Walk my dog" primary CTA, small "Edit" link in card header) inside a `max-w-2xl` page container. Empty state guides the owner to add a dog.
- `dogs/new` and `dogs/edit` render as centred `max-w-sm` white cards, matching the auth-form pattern from U-03.
- `dogs/_form` uses `<div class="mb-4">` wrappers, styled labels, inputs, textarea, and a primary submit button, with a red error banner above the form.
- `walks/index` renders active and past walks as `<table>` elements inside an `overflow-x: auto` wrapper, with traffic-light status badges (REQUESTED=blue, ACCEPTED=yellow, IN_PROGRESS=orange, COMPLETED=green, CANCELLED=stone). Cancel button uses red/destructive styling.
- `application_helper.rb` provides `walk_state_badge_classes(state)` returning static Tailwind class strings (scanned by JIT via `app/helpers/**/*.rb` in `tailwind.config.js`).

### Key Discoveries

- `app/views/dogs/index.html.erb` — `div.form-container` wrapper, plain `<ul>` list; no Tailwind
- `app/views/dogs/new.html.erb` — `div.form-container` + renders `_form`; no Tailwind
- `app/views/dogs/edit.html.erb` — same structure as `new`; no Tailwind
- `app/views/dogs/_form.html.erb` — `form_with`, `<br>` separators, `div.form-errors`, unstyled `form.submit`; no Tailwind
- `app/views/walks/index.html.erb` — `div.form-container`, two `<ul>` sections (active/past); no Tailwind
- `config/tailwind.config.js` — content includes `app/helpers/**/*.rb`, so helper-defined badge class strings ARE seen by JIT
- U-03 card pattern: `max-w-sm mx-auto mt-10 px-8 py-10 bg-white rounded-xl shadow-sm ring-1 ring-stone-200`
- U-03 input: `block w-full rounded-md border border-stone-300 px-3 py-2 text-sm placeholder-stone-400 focus:outline-none focus:ring-2 focus:ring-primary-500 focus:border-primary-500`
- U-03 label: `block text-sm font-medium text-stone-700 mb-1`
- U-03 primary button: `rounded-md bg-primary-600 px-4 py-2 text-sm font-medium text-white hover:bg-primary-700 focus:outline-none focus:ring-2 focus:ring-primary-500`
- U-03 error banner: `mb-4 rounded-md border border-red-300 bg-red-50 p-4 text-sm text-red-700`
- `app/views/home/index.html.erb` — out of scope for this change

## What We're NOT Doing

- No controller, route, or model changes
- No Stimulus controllers added
- No `home/index.html.erb` styling — deferred to a future home/dashboard slice
- No walker-facing views (`open_requests/`, `walker_walks/`) — that is U-05 scope
- No inline per-field validation error layout — banner pattern retained (matches U-03)
- No changes to `.flash-alert`, `.flash-notice`, or `.notice-v1` in `application.css`
- No removal of the stale `div.form-container` wrapper from `home/index.html.erb`
- No `overflow-x: auto` or table on the active walks section if active walks are always few; the wrapper is added regardless as a safety measure

## Implementation Approach

Three phases: dog form pages first (they follow the exact U-03 auth pattern — fastest to style), then dog index (card layout with the primary CTA hierarchy), then walk history (table layout + badge helper). The badge helper is introduced in Phase 3 since it's only consumed by the walk history view in this change; U-05 will extend it or adopt it for walker views.

## Critical Implementation Details

- **Static badge class strings in the helper.** Tailwind JIT purges classes it cannot find as static literals. The `walk_state_badge_classes` helper must contain the full class strings written out verbatim (not built by string concatenation) so the `app/helpers/**/*.rb` scanner picks them up. Example: `"bg-blue-100 text-blue-700"` is fine; `"bg-#{colour}-100"` is not.
- **`button_to` and `form.submit` class application.** Rails `button_to` wraps its content in a `<form>` — the `class:` param applies to the submit button inside, not the form. `form.submit` similarly accepts `class:`. Both accept the same class string as a `link_to` button would; no special treatment needed.
- **`overflow-x: auto` placement.** The wrapper `<div class="overflow-x-auto">` must wrap the `<table>`, not the outer page container, so that only the table scrolls horizontally on small screens while the page header and section titles stay in place.

---

## Phase 1: Dog Form Pages

### Overview

Style `dogs/_form.html.erb` (the shared form partial) and its two wrappers `dogs/new.html.erb` and `dogs/edit.html.erb`. Follows the U-03 auth-form card pattern verbatim.

### Changes Required:

#### 1. Dog form partial

**File:** `app/views/dogs/_form.html.erb`

**Intent:** Replace `<br>` separators with `<div class="mb-4">` wrappers, add U-03 label and input class strings to each field, style the textarea consistently, add the U-03 error banner above the form, and apply the primary button class to `form.submit`.

**Contract:** Error banner: `mb-4 rounded-md border border-red-300 bg-red-50 p-4 text-sm text-red-700` with `list-disc list-inside space-y-1` list. Label class: `block text-sm font-medium text-stone-700 mb-1`. Text/number inputs: `block w-full rounded-md border border-stone-300 px-3 py-2 text-sm placeholder-stone-400 focus:outline-none focus:ring-2 focus:ring-primary-500 focus:border-primary-500`. Textarea: same class string plus `resize-none`. Submit: `rounded-md bg-primary-600 px-4 py-2 text-sm font-medium text-white hover:bg-primary-700 focus:outline-none focus:ring-2 focus:ring-primary-500`.

#### 2. New dog page wrapper

**File:** `app/views/dogs/new.html.erb`

**Intent:** Replace `div.form-container` with the U-03 card container; style the heading; replace `<br>` before the back link with a Tailwind margin.

**Contract:** Card: `max-w-sm mx-auto mt-10 px-8 py-10 bg-white rounded-xl shadow-sm ring-1 ring-stone-200`. Heading: `text-2xl font-semibold text-stone-900 mb-6`. Back link: `inline-block mt-6 text-sm font-medium text-primary-600 hover:text-primary-700`.

#### 3. Edit dog page wrapper

**File:** `app/views/dogs/edit.html.erb`

**Intent:** Same transformation as `new.html.erb`.

**Contract:** Identical card, heading, and back-link classes as `new.html.erb`.

### Success Criteria:

#### Automated Verification:

- Tailwind pipeline compiles without error: `docker compose exec web bin/rails assets:precompile`
- RuboCop passes: `docker compose exec web bundle exec rubocop app/views/dogs/`

#### Manual Verification:

- "Add a dog" form renders as a centred white card on mobile (375 px) and desktop; no horizontal scroll
- "Edit dog" form renders identically to "Add a dog"
- Submitting with missing required fields shows the red error banner above the form
- `form.submit` button renders in primary-600 green

**Implementation Note:** After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 2: Dog Index (Dog Cards)

### Overview

Style `dogs/index.html.erb`: replace the unstyled list with a card-per-dog layout in a wide `max-w-2xl` container. Dog cards: compact name + breed headline, optional secondary lines for weight/notes, full-width primary "Walk my dog" CTA, small "Edit" secondary link in the card header.

### Changes Required:

#### 1. Dog index page

**File:** `app/views/dogs/index.html.erb`

**Intent:** Replace `div.form-container` with a `max-w-2xl` page container. Add a page header row with the "My dogs" heading and a right-aligned "Add a dog" primary button. Replace the `<ul>/<li>` dog list with a flex column of white cards. Inside each card: a flex header row with dog name (large, bold) + "Edit" link (small, right-aligned), then breed as secondary text, then optional weight and notes lines, then a full-width "Walk my dog" primary button at the bottom. Empty state: centred card with "You haven't added any dogs yet." text and a prominent "Add a dog" CTA.

**Contract:** Page container: `max-w-2xl mx-auto px-4 py-8`. Page header row: `flex items-center justify-between mb-6`. Heading: `text-2xl font-semibold text-stone-900`. "Add a dog" header button: `rounded-md bg-primary-600 px-4 py-2 text-sm font-medium text-white hover:bg-primary-700`. Cards container: `space-y-4`. Dog card: `bg-white rounded-xl shadow-sm ring-1 ring-stone-200 p-6`. Card header row: `flex items-center justify-between mb-2`. Dog name: `text-lg font-semibold text-stone-900`. "Edit" link: `text-sm text-primary-600 hover:text-primary-700 font-medium`. Breed: `text-sm text-stone-600 mb-1`. Optional weight/notes lines: `text-sm text-stone-500`. "Walk my dog" button: `mt-4 w-full rounded-md bg-primary-600 px-4 py-2 text-sm font-medium text-white hover:bg-primary-700 focus:outline-none focus:ring-2 focus:ring-primary-500`. Empty state card: same card shell as dog card, `text-center`, empty-state message in `text-stone-500`, "Add a dog" link styled as primary button.

### Success Criteria:

#### Automated Verification:

- Tailwind pipeline compiles without error: `docker compose exec web bin/rails assets:precompile`
- RuboCop passes: `docker compose exec web bundle exec rubocop app/views/dogs/index.html.erb`

#### Manual Verification:

- Dog cards render correctly on desktop and at 375 px; name + breed prominent; optional weight/notes appear only when populated
- "Walk my dog" full-width primary CTA is visually dominant on each card
- "Edit" sits in the card header as a small secondary link
- Empty state shows the "You haven't added any dogs yet." message with an "Add a dog" CTA
- "Add a dog" button in the page header navigates to the add dog form

**Implementation Note:** After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 3: Walk History + Status Badges

### Overview

Add a `walk_state_badge_classes(state)` helper to `application_helper.rb`, then style `walks/index.html.erb` as a two-section page (active / past) where each section uses a `<table>` inside an `overflow-x: auto` wrapper. Status badges are applied via the helper. The "Cancel" button uses destructive (red) styling.

### Changes Required:

#### 1. Walk state badge helper

**File:** `app/helpers/application_helper.rb`

**Intent:** Add a `walk_state_badge_classes` method returning static Tailwind badge class strings for each walk state. The method is used in the walk history table and will be reusable in U-05 walker views.

**Contract:** Method signature: `def walk_state_badge_classes(state)`. Returns `"inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium …"` with colour suffix per state:
- `"requested"` → `bg-blue-100 text-blue-700`
- `"accepted"` → `bg-yellow-100 text-yellow-700`
- `"in_progress"` → `bg-orange-100 text-orange-700`
- `"completed"` → `bg-green-100 text-green-700`
- `"cancelled"` → `bg-stone-100 text-stone-600`
- default (unknown state) → `bg-stone-100 text-stone-500`

All class strings must be written out as complete static literals (not interpolated) so Tailwind JIT's scanner picks them up from `app/helpers/**/*.rb`.

#### 2. Walk history page

**File:** `app/views/walks/index.html.erb`

**Intent:** Replace `div.form-container` and the two `<ul>` lists with a `max-w-2xl` page container, two labelled sections ("Active" and "Past"), each containing a white card with an `overflow-x: auto` wrapper around a `<table>`. Apply badge classes via `walk_state_badge_classes`. The "Cancel" button uses destructive styling. Empty states shown inline when each list is empty.

**Contract:** Page container: `max-w-2xl mx-auto px-4 py-8`. Page heading: `text-2xl font-semibold text-stone-900 mb-6`. Section heading: `text-lg font-medium text-stone-900 mb-3`. Card shell: `bg-white rounded-xl shadow-sm ring-1 ring-stone-200 overflow-hidden mb-6`. Overflow wrapper: `overflow-x-auto`. Table: `min-w-full divide-y divide-stone-200`. `<thead>`: `bg-stone-50`. `<th>`: `px-4 py-3 text-left text-xs font-medium uppercase tracking-wide text-stone-500`. `<tbody>`: `divide-y divide-stone-100`. `<td>`: `px-4 py-3 text-sm text-stone-700 whitespace-nowrap`. Badge: `<span class="<%= walk_state_badge_classes(walk.state) %>"><%= walk.state.humanize %></span>`. Cancel button: `rounded-md bg-red-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-500`. Empty state row: single `<td colspan="N">` with `text-sm text-stone-400 italic py-4` and the message centred.

Active table columns: Dog / State / Requested / Action (cancel).
Past table columns: Dog / State / Date / Walked by (completed only).

### Success Criteria:

#### Automated Verification:

- Tailwind pipeline compiles without error: `docker compose exec web bin/rails assets:precompile`
- RuboCop passes: `docker compose exec web bundle exec rubocop app/views/walks/ app/helpers/application_helper.rb`

#### Manual Verification:

- Walk history page renders the active and past sections as tables on desktop
- At 375 px the tables scroll horizontally without breaking the page layout
- Status badges render with correct traffic-light colours for each state
- "Cancel" button on REQUESTED walks renders in red; the turbo-confirm dialog fires on click
- Empty state rows appear when active or past lists are empty

**Implementation Note:** After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Testing Strategy

### Manual Testing Steps:

1. Sign in as an Owner with no dogs → verify empty state on `/dogs`
2. Add a dog → verify card appears on `/dogs` with correct layout
3. Add weight and notes → verify they appear as secondary text on card; add another dog without them → verify card stays compact
4. Click "Walk my dog" → verify walk appears on `/walks` as REQUESTED in the Active section
5. Verify REQUESTED badge is blue on `/walks`
6. Click "Cancel" → verify turbo-confirm fires; after confirming, walk moves to Past section with CANCELLED badge (stone)
7. Sign in as a Walker → accept the walk → sign back in as Owner → verify ACCEPTED badge is yellow in Active
8. Complete the walk cycle → verify COMPLETED badge is green in Past section, walker name appears in "Walked by" column
9. Resize to 375 px → verify walk history tables scroll horizontally without page overflow
10. Test dog form validation: submit empty "Add a dog" form → verify red error banner above form

## Performance Considerations

None beyond standard Tailwind JIT purging — all class strings are static literals.

## References

- Roadmap U-04: `context/foundation/roadmap.md`
- U-03 plan (established patterns): `context/archive/2026-06-26-ui-auth-and-profile/plan.md`
- U-02 plan (nav pattern reference): `context/archive/2026-06-26-ui-layout-and-nav/plan.md`

## Progress

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles.

### Phase 1: Dog Form Pages

#### Automated

- [x] 1.1 Tailwind pipeline compiles without error: `docker compose exec web bin/rails assets:precompile` — 8dd0c50
- [x] 1.2 RuboCop passes: `docker compose exec web bundle exec rubocop app/views/dogs/` — 8dd0c50

#### Manual

- [x] 1.3 "Add a dog" form renders as a centred white card on mobile (375 px) and desktop; no horizontal scroll
- [x] 1.4 "Edit dog" form renders identically to "Add a dog"
- [x] 1.5 Submitting with missing required fields shows the red error banner above the form
- [x] 1.6 `form.submit` button renders in primary-600 green

### Phase 2: Dog Index (Dog Cards)

#### Automated

- [x] 2.1 Tailwind pipeline compiles without error: `docker compose exec web bin/rails assets:precompile` — 179ef93
- [x] 2.2 RuboCop passes: `docker compose exec web bundle exec rubocop app/views/dogs/index.html.erb` — 179ef93

#### Manual

- [x] 2.3 Dog cards render correctly on desktop and at 375 px; name + breed prominent; optional weight/notes appear only when populated
- [x] 2.4 "Walk my dog" full-width primary CTA is visually dominant on each card
- [x] 2.5 "Edit" sits in the card header as a small secondary link
- [x] 2.6 Empty state shows the "You haven't added any dogs yet." message with an "Add a dog" CTA
- [x] 2.7 "Add a dog" button in the page header navigates to the add dog form

### Phase 3: Walk History + Status Badges

#### Automated

- [x] 3.1 Tailwind pipeline compiles without error: `docker compose exec web bin/rails assets:precompile` — bd204b8
- [x] 3.2 RuboCop passes: `docker compose exec web bundle exec rubocop app/views/walks/ app/helpers/application_helper.rb` — bd204b8

#### Manual

- [x] 3.3 Walk history page renders the active and past sections as tables on desktop
- [x] 3.4 At 375 px the tables scroll horizontally without breaking the page layout
- [x] 3.5 Status badges render with correct traffic-light colours for each state
- [x] 3.6 "Cancel" button on REQUESTED walks renders in red; the turbo-confirm dialog fires on click
- [x] 3.7 Empty state rows appear when active or past lists are empty
