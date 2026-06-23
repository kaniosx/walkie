# Owner Walk History — Plan Brief

> Full plan: `context/changes/owner-walk-history/plan.md`

## What & Why

Enrich the existing Owner walk list into a proper history page (FR-015). The current view is a minimal flat list that mixes active and past walks and omits cancelled walks entirely. This slice splits it into Active / Past sections, adds cancelled walk visibility, shows lifecycle timestamps, and surfaces the walker's name on completed walks.

## Starting Point

`WalksController#index` returns all non-cancelled owned walks as a flat `@walks` list; `app/views/walks/index.html.erb` shows dog name, state, created_at, and a Cancel button for REQUESTED walks. COMPLETED walks appear but look identical to active ones. CANCELLED walks are invisible.

## Desired End State

An Owner visiting `/walks` sees two sections: **Active** (REQUESTED / ACCEPTED / IN_PROGRESS, with Cancel button where applicable) and **Past** (COMPLETED / CANCELLED, with the relevant terminal timestamp and the walker's name for COMPLETED walks). Both sections show an empty-state message if they have no rows. Cross-owner isolation is maintained by the controller-level scope.

## Key Decisions Made

| Decision | Choice | Why (1 sentence) |
|---|---|---|
| Cancelled walks in history | Include | FR-015 covers "past walks"; hiding them removes the Owner's audit trail. |
| Layout | Active / Past split | PRD NFR: completed walks "no longer appear as active items but remain in history." |
| Walker identity | Show for COMPLETED (Past section only) | Limits privacy surface to the case where the walk is definitively over. |
| Walker identity for ACCEPTED/IN_PROGRESS | Hide | Active walks are ongoing; surfacing walker identity mid-walk is out of scope. |
| Timestamps | terminal timestamp per row | completed_at or cancelled_at gives the most useful "when did this end" signal. |

## Scope

**In scope:** WalksController#index query split into @active_walks + @past_walks; `:accepted_by_walker` eager-load added; view rewritten into two sections with timestamps and walker name; integration tests updated

**Out of scope:** New routes, controller actions, migrations; pagination; walker walk history (S-09); real-time update; walker identity on active walks

## Architecture / Approach

Two scoped AR queries (one reusing the existing `active` scope, one querying `completed | cancelled`), both scoped to `current_user.owned_walks`. View iterates each collection independently. No new controller methods, no new routes.

## Phases at a Glance

| Phase | What it delivers | Key risk |
|---|---|---|
| 1. Controller + Tests | Two-query split, :accepted_by_walker include, updated integration tests | Phase 1 temporarily breaks the view (it references `@walks`); implement or stub Phase 2 quickly |
| 2. View Rewrite | Active / Past sections with timestamps and walker name | Display logic for the terminal timestamp (completed_at vs cancelled_at) must handle nil for ACCEPTED/IN_PROGRESS rows in Active section |

**Prerequisites:** S-04 (owner-creates-walk-request) and S-06 (owner-cancels-requested-walk) archived — both done.
**Estimated effort:** ~1 session across 2 phases

## Open Risks & Assumptions

- Phase 1 + Phase 2 should be implemented back-to-back (or Phase 2 first, then Phase 1) to avoid leaving the view broken mid-session. The manual verification gate for Phase 1 is lightweight for this reason.
- Walker display_label for COMPLETED walks relies on `accepted_by_walker` not being nil — guaranteed by the DB `walks_walker_presence` CHECK constraint for completed state.

## Success Criteria (Summary)

- Active and Past sections each show the correct walks and are empty-stated independently
- COMPLETED Past rows show walker name and completed_at
- CANCELLED Past rows show cancelled_at and no walker name
- Owner B's walks never appear to Owner A in either section
