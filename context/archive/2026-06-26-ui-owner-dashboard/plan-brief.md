# Owner Dashboard Screens — Plan Brief

> Full plan: `context/changes/ui-owner-dashboard/plan.md`

## What & Why

Style the five Owner-facing views (`dogs/index`, `dogs/new`, `dogs/edit`, `dogs/_form`, `walks/index`) with Tailwind CSS. The auth/profile screens (U-03) are now fully Tailwind-styled; the dog-management and walk-history pages still wrap their content in `div.form-container` whose CSS was removed in U-03, leaving them visually unstyled. This change closes that gap.

## Starting Point

All five views use a stale `div.form-container` wrapper (no CSS effect since U-03 removed the rule). Walk state is displayed as plain `.humanize` text — no colour differentiation. The Tailwind design tokens (emerald = `primary`, stone = `neutral`) and the card/input/button/error-banner class strings are fully established by U-03 and ready to reuse.

## Desired End State

Dog list at `/dogs` renders per-dog cards (compact: name + breed headline, optional weight/notes as secondary text, full-width emerald "Walk my dog" CTA, small "Edit" link). Dog add/edit pages render as centred white cards matching the U-03 auth-form style. Walk history at `/walks` renders active and past walks as tables with traffic-light status badges; the table scrolls horizontally on mobile. `home/index.html.erb` stays out of scope.

## Key Decisions Made

| Decision | Choice | Why (1 sentence) | Source |
| --- | --- | --- | --- |
| Status badge palette | Semantic traffic-light (blue/yellow/orange/green/stone) | Scannable at a glance without a legend; shared with U-05 walker views | Plan |
| Walk history layout | HTML `<table>` + `overflow-x: auto` | Roadmap explicitly says "walk-history table"; correct semantic HTML for comparative tabular data | Plan |
| Dog card detail | Compact — name + breed, optional fields shown if present | Cards stay uniform when weight/notes are absent; avoids dash-heavy empty fields | Plan |
| "Walk my dog" CTA | Full-width primary button at card bottom; "Edit" as small secondary link | Primary reason an Owner visits `/dogs` is to post a walk — PRD under-30-seconds secondary success criterion | Plan |
| Container width | `max-w-sm` for form pages; `max-w-2xl` for list pages | Narrow card follows U-03 auth-form pattern; wider container needed for cards/table layout | Plan |
| Badge class placement | `application_helper.rb` with static string literals | `tailwind.config.js` already scans `app/helpers/**/*.rb`; helper is reusable for U-05 without duplication | Plan |
| `home/index.html.erb` | Out of scope | Interim landing page likely to be refactored; `/dogs` and `/walks` are the real Owner surfaces | Plan |

## Scope

**In scope:** `dogs/index.html.erb`, `dogs/new.html.erb`, `dogs/edit.html.erb`, `dogs/_form.html.erb`, `walks/index.html.erb`, `app/helpers/application_helper.rb` (badge helper only)

**Out of scope:** Any controller, route, or model change; walker-facing views (U-05); `home/index.html.erb`; flash message migration; inline per-field validation errors

## Architecture / Approach

Pure view-layer change plus one helper method. Phase 1 styles the dog form pages (three files, follow U-03 card pattern verbatim). Phase 2 styles the dog index (card-list layout with primary CTA hierarchy). Phase 3 adds the badge helper and styles the walk history as a table. No new Stimulus controllers; no JS changes; no CSS file changes.

## Phases at a Glance

| Phase | What it delivers | Key risk |
| --- | --- | --- |
| 1. Dog form pages | Styled add/edit dog forms matching U-03 auth-form card | None significant — direct pattern reuse from U-03 |
| 2. Dog index | Dog card list with full-width "Walk my dog" CTA | `button_to` class application — must apply to the submit button inside the generated `<form>`, not the form itself |
| 3. Walk history + badges | Table layout, traffic-light badges, badge helper | Tailwind JIT purge: badge class strings must be static literals in the helper file, not interpolated |

**Prerequisites:** U-01 (Tailwind pipeline) and U-02 (layout shell) — both archived. U-03 (auth/profile styling) — archived.
**Estimated effort:** ~1 session across 3 phases (all are small view edits; Phase 2 is the most structural).

## Open Risks & Assumptions

- Badge class strings in the helper must be written as complete static literals (e.g. `"bg-blue-100 text-blue-700"`) — string interpolation like `"bg-#{colour}-100"` will be purged by Tailwind JIT. The plan's contract section calls this out explicitly.
- `button_to` renders a `<form>` around a submit button; the `class:` option applies to the button, not the form — test manually that the "Walk my dog" and "Cancel" buttons render correctly.

## Success Criteria (Summary)

- Dog index renders per-dog cards with the "Walk my dog" CTA visually dominant; empty state guides owner to add a dog
- Dog add/edit forms match the U-03 white-card style; validation errors show as a red banner
- Walk history renders as a table with traffic-light status badges; the table scrolls horizontally at 375 px without page overflow
