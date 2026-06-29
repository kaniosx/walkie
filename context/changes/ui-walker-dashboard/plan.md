# Walker Dashboard Screens — Tailwind Styling

## Overview

Style the two Walker-facing views (`open_requests/index`, `walker_walks/index`) with Tailwind CSS. No behaviour changes — only CSS classes are added to ERB views. All views become visually consistent with the U-02 navbar, U-03 auth/profile screens, and U-04 Owner dashboard.

## Current State Analysis

Two views exist, each wrapped in `div.form-container` (the CSS rule was removed in U-03, so these wrappers have no visual effect today). Walk state is displayed as plain `.humanize` text with no colour differentiation. The Tailwind design token layer, card/table/button class strings, and `walk_state_badge_classes` helper are fully established in U-03/U-04 and are ready to reuse without modification.

- `app/views/open_requests/index.html.erb` — `div.form-container` + unstyled `<ul>/<li>` per request; shows dog name, breed, city, postcode, Accept button
- `app/views/walker_walks/index.html.erb` — `div.form-container`; two unstyled sections: (1) active walk (single `@walk` or nil) with conditional Start/End buttons; (2) past walks as `<ul>/<li>`

## Desired End State

- `open_requests/index` renders one card per open request (dog name + breed as headline; city + relative time as secondary line; full-width "Accept" primary CTA at the bottom). Empty state: centred white card with city-aware message.
- `walker_walks/index` page heading is "My walk" (matching the nav label). Active walk section: a primary-tinted card (`bg-primary-50`, `ring-2 ring-primary-300`) showing dog name + breed, state badge, and Start walk / End walk button. Empty state: white card with link to open requests. History section: `<table>` inside `overflow-x-auto` wrapper with columns Dog / State / Date / Owner; state badges via `walk_state_badge_classes`.

### Key Discoveries

- `app/helpers/application_helper.rb` — `walk_state_badge_classes(state)` already covers all five states with static Tailwind class literals; no changes needed to this file
- `config/tailwind.config.js` — content already includes `app/helpers/**/*.rb` so the helper's class strings are scanned
- U-03 card pattern: `max-w-sm mx-auto mt-10 px-8 py-10 bg-white rounded-xl shadow-sm ring-1 ring-stone-200`
- U-04 page container: `max-w-2xl mx-auto px-4 py-8`; section heading: `text-lg font-medium text-stone-900 mb-3`; table/card shell: `bg-white rounded-xl shadow-sm ring-1 ring-stone-200 overflow-hidden mb-6`
- U-04 primary button: `rounded-md bg-primary-600 px-4 py-2 text-sm font-medium text-white hover:bg-primary-700 focus:outline-none focus:ring-2 focus:ring-primary-500`
- `walker_walks_controller.rb` already eager-loads `:dog` and `:owner`, so `past.owner.display_label` is N+1-safe
- `open_requests_controller.rb` eager-loads `:dog`; `walk.created_at` is available for `time_ago_in_words`

## What We're NOT Doing

- No controller, route, or model changes
- No Stimulus controllers added
- No changes to `application_helper.rb` or `application.css`
- No styling of `home/index.html.erb`
- No change to the state machine, flash messages, or turbo behaviours (turbo_confirm on "End walk" stays as-is)
- No postcode display on open-request cards (city only, as decided)

## Implementation Approach

Three phases in dependency order: open requests first (self-contained), then the active walk card (top half of `walker_walks/index`), then the history table (bottom half of the same file). The two-phase split on `walker_walks/index` lets each section be verified independently before the full page is complete.

## Critical Implementation Details

- **`button_to` wraps in a `<form>`**. To apply a class to the submit button (not the form), pass `class:` directly to `button_to`. For a full-width button on the open-request cards, also pass `form_class: "block w-full"` so the wrapping `<form>` stretches full-width and the button inside can use `w-full`.
- **`time_ago_in_words` is a view helper, not a model method.** Call it directly in the ERB: `<%= time_ago_in_words(walk.created_at) %> ago`. No helper extraction needed.

---

## Phase 1: Open Requests Cards

### Overview

Style `open_requests/index.html.erb`: replace the unstyled list with a card-per-request layout in a `max-w-2xl` container. Each card shows dog name + breed as the headline, city + relative time as secondary metadata, and a full-width "Accept" primary CTA at the bottom.

### Changes Required:

#### 1. Open requests page

**File:** `app/views/open_requests/index.html.erb`

**Intent:** Replace `div.form-container` and the `<ul>/<li>` list with a `max-w-2xl` page container. Render one white card per open request. Each card: dog name (large/bold) + breed (secondary text) in the card body; a metadata line with city and `time_ago_in_words(walk.created_at)`; a full-width "Accept" `button_to` at the bottom using the primary button class. Empty state: centred white card with the existing city-aware message and a subdued empty-state text style.

**Contract:** Page container: `max-w-2xl mx-auto px-4 py-8`. Page heading: `text-2xl font-semibold text-stone-900 mb-6`. Cards container: `space-y-4`. Card: `bg-white rounded-xl shadow-sm ring-1 ring-stone-200 p-6`. Dog name: `text-lg font-semibold text-stone-900`. Breed: `text-sm text-stone-600 mt-0.5`. Metadata line (city + time): `text-sm text-stone-500 mt-2`. Accept `button_to`: `form_class: "block w-full mt-4"`, `class: "w-full rounded-md bg-primary-600 px-4 py-2 text-sm font-medium text-white hover:bg-primary-700 focus:outline-none focus:ring-2 focus:ring-primary-500"`. Empty state card: same card shell, `text-center`, message in `text-stone-500`.

### Success Criteria:

#### Automated Verification:

- Tailwind pipeline compiles without error: `docker compose exec web bin/rails assets:precompile`
- RuboCop passes: `docker compose exec web bundle exec rubocop app/views/open_requests/`

#### Manual Verification:

- Open requests page renders one card per request at desktop and 375 px; no horizontal scroll
- Each card shows dog name (prominent) + breed (subdued), city, and relative time ("5 minutes ago")
- "Accept" button is full-width, primary green, visually dominant at the bottom of each card
- Empty state shows the city-aware message in a white card

**Implementation Note:** After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase. Phase blocks use plain bullets — the corresponding `- [ ]` checkboxes for these items live in the `## Progress` section at the bottom of the plan.

---

## Phase 2: Active Walk Card

### Overview

Style the active walk section (top half) of `walker_walks/index.html.erb`. Establish the page container, "My walk" heading, and a primary-tinted card for the active walk. The history section (Phase 3) is added below in the same file.

### Changes Required:

#### 1. Walker walks page — active walk section

**File:** `app/views/walker_walks/index.html.erb`

**Intent:** Replace `div.form-container` and the existing active walk markup with a `max-w-2xl` page container and a "My walk" page heading. When `@walk` exists: render a primary-tinted card (`bg-primary-50`) with dog name + breed, state badge via `walk_state_badge_classes`, and the conditional Start walk / End walk button. When `@walk` is nil: render a white empty-state card with a link to open requests. Leave a `<!-- Phase 3: history -->` comment placeholder at the bottom of the container where the history section will be added in Phase 3.

**Contract:** Page container: `max-w-2xl mx-auto px-4 py-8`. Page heading: `text-2xl font-semibold text-stone-900 mb-6`. Active walk card: `bg-primary-50 rounded-xl shadow-sm ring-2 ring-primary-300 p-6 mb-6`. Dog name: `text-xl font-semibold text-stone-900`. Breed: `text-sm text-stone-600 mt-0.5`. State badge: `<span class="<%= walk_state_badge_classes(@walk.state) %> mt-3 inline-block">`. Start walk button (`button_to`, method: `:post`): `rounded-md bg-primary-600 px-4 py-2 text-sm font-medium text-white hover:bg-primary-700 focus:outline-none focus:ring-2 focus:ring-primary-500 mt-4`. End walk button (same but with `turbo_confirm` already present): same primary class string (the confirm dialog carries the weight of the destructive signal; no colour change needed). Empty state card: `bg-white rounded-xl shadow-sm ring-1 ring-stone-200 p-6 mb-6 text-center`, message in `text-stone-500`, link to open requests in `text-primary-600 hover:text-primary-700 font-medium`.

### Success Criteria:

#### Automated Verification:

- Tailwind pipeline compiles without error: `docker compose exec web bin/rails assets:precompile`
- RuboCop passes: `docker compose exec web bundle exec rubocop app/views/walker_walks/`

#### Manual Verification:

- Active walk card renders with a visible primary-tinted background, distinct from the white history section below
- State badge renders with correct traffic-light colour (yellow for ACCEPTED, orange for IN_PROGRESS)
- "Start walk" button renders in primary green when walk is ACCEPTED
- "End walk" button renders in primary green when walk is IN_PROGRESS; turbo_confirm dialog fires on click
- Empty state card renders with a link to open requests when no active walk exists

**Implementation Note:** After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 3: Walk History Table

### Overview

Add the history section (bottom half) of `walker_walks/index.html.erb`: a "Walk history" section heading and a `<table>` inside an `overflow-x-auto` wrapper. Removes the `<!-- Phase 3: history -->` placeholder from Phase 2.

### Changes Required:

#### 1. Walker walks page — history section

**File:** `app/views/walker_walks/index.html.erb`

**Intent:** Replace the `<!-- Phase 3: history -->` placeholder with the history section: a `text-lg` section heading "Walk history", then a white card shell containing an `overflow-x-auto` wrapper and a `<table>`. Rows come from `@past_walks`. Columns: Dog (name), State (badge), Date, Owner (display_label). Empty state: single `<td colspan="4">` row. Apply badge classes via `walk_state_badge_classes(past.state)`. For Date: show `completed_at&.to_fs(:short)` when `completed?`, otherwise `cancelled_at&.to_fs(:short)`.

**Contract:** Section heading: `text-lg font-medium text-stone-900 mb-3`. Card shell: `bg-white rounded-xl shadow-sm ring-1 ring-stone-200 overflow-hidden`. Overflow wrapper: `overflow-x-auto`. Table: `min-w-full divide-y divide-stone-200`. `<thead>`: `bg-stone-50`. `<th>`: `px-4 py-3 text-left text-xs font-medium uppercase tracking-wide text-stone-500`. `<tbody>`: `divide-y divide-stone-100`. `<td>`: `px-4 py-3 text-sm text-stone-700 whitespace-nowrap`. Badge `<span>`: `<%= walk_state_badge_classes(past.state) %>`. Empty state `<td>`: `text-sm text-stone-400 italic py-4 text-center`.

### Success Criteria:

#### Automated Verification:

- Tailwind pipeline compiles without error: `docker compose exec web bin/rails assets:precompile`
- RuboCop passes: `docker compose exec web bundle exec rubocop app/views/walker_walks/`

#### Manual Verification:

- Walk history table renders with Dog / State / Date / Owner columns at desktop
- At 375 px the table scrolls horizontally without page overflow
- State badges render with correct traffic-light colours
- Owner name column shows the owner's `display_label`
- Empty state row appears when `@past_walks` is empty
- Page heading is "My walk" (consistent with the nav link label)

**Implementation Note:** After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Testing Strategy

### Manual Testing Steps:

1. Sign in as a Walker with city set → open `/open_requests` → verify card layout with dog name, breed, city, relative time, and green full-width Accept button
2. Verify empty state on `/open_requests` when no open requests exist in the walker's city
3. Accept a walk → verify it disappears from open requests list
4. Navigate to "My walk" (`/walker_walks`) → verify primary-tinted active walk card with ACCEPTED (yellow) badge and "Start walk" button
5. Click "Start walk" → verify card updates to IN_PROGRESS (orange) badge and "End walk" button
6. Click "End walk" → verify turbo_confirm dialog fires; confirm it → verify walk moves to history table with COMPLETED (green) badge and completion date
7. Verify "Owner" column in history table shows the owner's display name
8. Resize to 375 px → verify history table scrolls horizontally without page overflow
9. Verify empty state on "My walk" page when no active walk; link to open requests is present
10. Sign in as an Owner → accept a walk as that Owner's dog → sign back as Walker → verify ACCEPTED badge is yellow in the active walk card

## Performance Considerations

None beyond standard Tailwind JIT purging — all class strings are static literals. `time_ago_in_words` is a server-side Rails helper with negligible overhead.

## References

- Roadmap U-05: `context/foundation/roadmap.md`
- U-04 plan (established patterns): `context/archive/2026-06-26-ui-owner-dashboard/plan.md`
- Badge helper: `app/helpers/application_helper.rb`

## Progress

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles. See `references/progress-format.md`.

### Phase 1: Open Requests Cards

#### Automated

- [x] 1.1 Tailwind pipeline compiles without error: `docker compose exec web bin/rails assets:precompile`
- [x] 1.2 RuboCop passes: `docker compose exec web bundle exec rubocop app/views/open_requests/`

#### Manual

- [x] 1.3 Open requests page renders one card per request at desktop and 375 px; no horizontal scroll
- [x] 1.4 Each card shows dog name (prominent) + breed (subdued), city, and relative time ("5 minutes ago")
- [x] 1.5 "Accept" button is full-width, primary green, visually dominant at the bottom of each card
- [x] 1.6 Empty state shows the city-aware message in a white card

### Phase 2: Active Walk Card

#### Automated

- [ ] 2.1 Tailwind pipeline compiles without error: `docker compose exec web bin/rails assets:precompile`
- [ ] 2.2 RuboCop passes: `docker compose exec web bundle exec rubocop app/views/walker_walks/`

#### Manual

- [ ] 2.3 Active walk card renders with a visible primary-tinted background, distinct from the white history section below
- [ ] 2.4 State badge renders with correct traffic-light colour (yellow for ACCEPTED, orange for IN_PROGRESS)
- [ ] 2.5 "Start walk" button renders in primary green when walk is ACCEPTED
- [ ] 2.6 "End walk" button renders in primary green when walk is IN_PROGRESS; turbo_confirm dialog fires on click
- [ ] 2.7 Empty state card renders with a link to open requests when no active walk exists

### Phase 3: Walk History Table

#### Automated

- [ ] 3.1 Tailwind pipeline compiles without error: `docker compose exec web bin/rails assets:precompile`
- [ ] 3.2 RuboCop passes: `docker compose exec web bundle exec rubocop app/views/walker_walks/`

#### Manual

- [ ] 3.3 Walk history table renders with Dog / State / Date / Owner columns at desktop
- [ ] 3.4 At 375 px the table scrolls horizontally without page overflow
- [ ] 3.5 State badges render with correct traffic-light colours
- [ ] 3.6 Owner name column shows the owner's `display_label`
- [ ] 3.7 Empty state row appears when `@past_walks` is empty
- [ ] 3.8 Page heading is "My walk" (consistent with the nav link label)
