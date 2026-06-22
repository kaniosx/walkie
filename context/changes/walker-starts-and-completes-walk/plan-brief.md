# Walker Starts + Completes a Walk — Plan Brief

> Full plan: `context/changes/walker-starts-and-completes-walk/plan.md`

## What & Why

Wire the HTTP layer for the Walker's start and complete transitions (FR-013, FR-014, US-03): a new "My active walk" page, two action routes, and integration tests. This closes the walk lifecycle loop — without it, a Walker who accepts a walk has no way to advance its state from the UI.

## Starting Point

`Walk#start!(walker)` and `Walk#complete!(walker)` exist at `app/models/walk.rb:58-68` with atomic `swap_state` guards. After accepting a walk, the Walker currently has no UI surface to see it or advance its state — the open_requests list filters to `requested` only, so accepted walks vanish from view.

## Desired End State

A Walker sees a "My walk" nav link. `/walker_walks` shows their current accepted or in-progress walk with a "Start walk" or "End walk" button. Completing a walk redirects to open_requests with a notice. If no active walk exists, a helpful empty state with a link to open requests is shown.

## Key Decisions Made

| Decision | Choice | Why (1 sentence) |
|---|---|---|
| Where start/complete live | New `/walker_walks` page | Clean separation from open-requests list; parallels how WalksController serves the Owner; extends naturally into S-09 walker history. |
| Post-completion landing | Redirect to open_requests | Natural "done, grab another walk" flow — no history page exists yet. |
| Empty state | Message + link to open requests | Guides the Walker to the next action without a confusing redirect bounce. |
| Flash copy | Explicit per-transition | "Walk started — you're on your way!" / "Walk completed. Well done!" / "This walk can no longer be updated." |
| End walk confirmation | `data-turbo-confirm` | Completion is irreversible (PRD §Open Q #7); one attribute prevents accidental taps. |

## Scope

**In scope:** `WalkerWalksController` (index + start + complete), routes, "My active walk" view, "My walk" nav link, 6 integration tests

**Out of scope:** Walker walk history (S-09); Owner confirmation of completion (PRD §Open Q #7, post-v1); reversal or cancellation of in-progress walks; real-time UI

## Architecture / Approach

Exact mirror of the `accept!` pattern. `WalkerWalksController` includes `WalkerOnly`. The index action queries `Walk.where(accepted_by_walker_id: current_user.id, state: %w[accepted in_progress])` — nil result → empty state. Start/complete use a scoped `find` (restricts by walker + expected state) to 404 on foreign or wrong-state requests. Boolean return drives the flash branch.

## Phases at a Glance

| Phase | What it delivers | Key risk |
|---|---|---|
| 1. Controller + Routes | `/walker_walks` index + start + complete actions + rubocop | Scoped find must restrict by both walker AND state to correctly 404 foreign walks |
| 2. View + Nav + Tests | "My active walk" view, "My walk" nav link, 6 integration tests | Confirm dialog on End walk must use `data-turbo-confirm`; test must verify walk is completed in DB |

**Prerequisites:** S-05 (`walker-accepts-request`) complete — done.
**Estimated effort:** ~1 session across 2 phases

## Open Risks & Assumptions

- A Walker has at most one active walk at a time — the index shows `.first`; if somehow two exist (data anomaly), only one is shown. The one-active-per-dog guard at creation prevents this in practice.
- PRD §Open Q #7: completion is irrevocable in v1 — "End walk = walk is finished, this cannot be undone" must be clear in UI copy.
