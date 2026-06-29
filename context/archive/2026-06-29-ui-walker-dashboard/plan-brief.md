# Walker Dashboard Screens — Plan Brief

> Full plan: `context/changes/ui-walker-dashboard/plan.md`

## What & Why

Style the two Walker-facing views (`open_requests/index`, `walker_walks/index`) with Tailwind CSS. This is the final UI polish slice (U-05) — the Walker's journey currently works functionally but renders as unstyled markup. The goal is visual parity with the Owner dashboard (U-04) so the full two-sided MVP is presentable for real-user smoke testing.

## Starting Point

Two views exist with `div.form-container` wrappers (a stale CSS class with no visual effect since U-03) and plain `<ul>/<li>` lists. The `walk_state_badge_classes` helper, all design tokens, card/table/button patterns, and the Tailwind JIT scanner config were established in U-03/U-04 and require no changes here.

## Desired End State

A Walker visiting `/open_requests` sees a card list — one card per open request showing dog name, breed, city, and how long ago the request was posted, with a full-width green "Accept" button. Visiting `/walker_walks` ("My walk"), they see a primary-tinted card for their active walk with state badge and Start/End walk actions, and a history table below with Dog / State / Date / Owner columns — both sections consistent with the Owner history table from U-04.

## Key Decisions Made

| Decision | Choice | Why (1 sentence) | Source |
|---|---|---|---|
| Accept button style | Full-width at card bottom | Matches "Walk my dog" CTA in U-04; maximises mobile tap target and makes accepting unmissable — consistent with "prominent" in roadmap. | Plan |
| Active walk visual treatment | Primary-tinted card (`bg-primary-50` + `ring-2 ring-primary-300`) | Signals an active obligation at a glance; white card alone lets it blend into the history section. | Plan |
| Past walks layout | Table with `overflow-x-auto` | Consistent with owner history table from U-04; Dog/State/Date/Owner columns mirror the owner's Walked-by column. | Plan |
| City/postcode on open-request cards | City only (no postcode) | Postcode is always the walker's own (filtered); city confirms locality without redundancy. | Plan |
| Time display on open requests | `time_ago_in_words` (relative) | Reinforces the "available right now" product signal — core to the Walkie hypothesis. | Plan |
| Past walk table columns | Dog / State / Date / Owner | Symmetric with owner history; owner `display_label` is already eager-loaded by the controller. | Plan |
| `walker_walks` page heading | "My walk" | Matches the nav link label — eliminates the mismatch between "My walk" (nav) and "My active walk" (old heading). | Plan |
| Badge helper | Reuse as-is | All five states covered with static Tailwind literals; no changes needed. | Research (U-04) |

## Scope

**In scope:**
- `app/views/open_requests/index.html.erb` — full restyle
- `app/views/walker_walks/index.html.erb` — full restyle (active walk + history sections)

**Out of scope:**
- No controller, route, or model changes
- No changes to `application_helper.rb` or `application.css`
- No Stimulus controllers
- No `home/index.html.erb` styling
- No postcode display on request cards

## Architecture / Approach

Pure ERB/Tailwind — add class strings to existing markup, remove the stale `div.form-container` wrappers, replace `<ul>/<li>` with card and table layouts. Three phases let each section be verified independently before the next is added.

## Phases at a Glance

| Phase | What it delivers | Key risk |
|---|---|---|
| 1. Open Requests Cards | `open_requests/index.html.erb` fully styled | `button_to` full-width requires `form_class: "block w-full"` on the wrapper form — easy to miss |
| 2. Active Walk Card | Active walk section of `walker_walks/index.html.erb` styled; primary-tinted card + state badge | Primary-tinted background uses `ring-2 ring-primary-300` — verify these JIT classes aren't purged |
| 3. Walk History Table | History section of `walker_walks/index.html.erb` styled; page heading "My walk" | `display_label` on `past.owner` must not N+1 — controller already eager-loads `:owner`, verify |

**Prerequisites:** U-01 (Tailwind), U-02 (layout shell) — both done.
**Estimated effort:** ~1 session across 3 phases (pure view styling, no logic changes).

## Open Risks & Assumptions

- `walk.owner.display_label` is safe from N+1 only because `WalkerWalksController#index` already includes `:owner`. If the include is ever removed, this silently regresses.
- `time_ago_in_words` produces stale text if the walker leaves the page open for a long time. Acceptable for MVP — no JS refresh.

## Success Criteria (Summary)

- Open requests page renders one styled card per request with prominent Accept CTA; empty state is visible when the walker's city has no open requests
- Active walk card is visually distinct (primary tint) with correct state badge and functional Start/End walk buttons
- Walk history table matches Owner history table structure; scrolls on mobile without breaking layout
