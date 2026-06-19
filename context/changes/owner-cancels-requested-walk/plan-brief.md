# Owner Cancels a Requested Walk — Plan Brief

> Full plan: `context/changes/owner-cancels-requested-walk/plan.md`

## What & Why

Wire the HTTP layer for Owner-initiated walk cancellation (FR-010): a route, controller action, view button, and integration tests. The hard parts — the `Walk#cancel!` model method, the `cancelled` DB state, and the atomic race-handling via `swap_state` — are already built in F-02. This slice makes the capability user-accessible.

## Starting Point

`WalksController` exists and is already Owner-gated. The walks index lists all owned walks with no state filter. There is no cancel route, no controller action, and no UI affordance for cancellation.

## Desired End State

An Owner sees a "Cancel" button next to each REQUESTED walk in their list. Confirming the browser dialog removes the walk from the list with a success notice. If a Walker accepted the walk in the window between page load and cancel, the Owner gets a clear "already accepted" message and the walk stays visible in its new state.

## Key Decisions Made

| Decision | Choice | Why (1 sentence) | Source |
|---|---|---|---|
| Cancelled walks in history | Hide from index | Cleaner list; no audit trail needed in v1 | Plan |
| Confirmation dialog | `data-turbo-confirm` | One attribute, no Stimulus controller, prevents accidental cancellation | Plan |
| Route verb | `POST :cancel` member action | Mirrors `post :accept` on `open_requests`; cancellation is not deletion | Plan |
| Race outcome message | "This request was already accepted by a walker." | Specific; Owner immediately understands what happened | Plan |

## Scope

**In scope:** cancel route + controller action + view button + index filter (hide cancelled) + integration tests

**Out of scope:** cancellation after ACCEPTED state (PRD §Open Q #5, explicit post-v1); walk show/detail page; real-time UI update

## Architecture / Approach

Exact mirror of the `accept!` pattern in `OpenRequestsController#accept`. Scoped lookup on `current_user.owned_walks` for automatic 404 on foreign walks. Boolean return from `cancel!` drives the flash branch. Index query extended with `.where.not(state: :cancelled)`.

## Phases at a Glance

| Phase | What it delivers | Key risk |
|---|---|---|
| 1. Route + Controller | Cancel route + action + index filter | None — model method exists; pattern is direct copy of accept |
| 2. View + Tests | Cancel button + integration test suite | Ensuring the race scenario test correctly simulates ACCEPTED state before the cancel POST |

**Prerequisites:** S-04 (owner-creates-walk-request) complete — done.
**Estimated effort:** ~1 session across 2 phases

## Open Risks & Assumptions

- `current_user.owned_walks` association assumed to exist on `User` model (used in existing controller index — confirmed); if the association name differs, scoped lookup in cancel action must match.

## Success Criteria (Summary)

- Owner can cancel a REQUESTED walk; it disappears from their list
- Owner attempting to cancel an already-accepted walk sees "This request was already accepted by a walker."
- Integration tests pass; full suite green; rubocop clean
