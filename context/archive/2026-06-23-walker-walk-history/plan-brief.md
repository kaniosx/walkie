# Walker Walk History — Plan Brief

> Full plan: `context/changes/walker-walk-history/plan.md`

## What & Why

Add a Past walks section to the Walker's `/walker_walks` page (FR-016). S-07 built the active-walk view; this slice adds the history section showing all walks this Walker accepted and completed, with context about who and what they walked.

## Starting Point

`WalkerWalksController#index` assigns only `@walk` (the active walk, or nil) and the view renders a single "My active walk" block. There is no history section. S-07 explicitly deferred history to S-09.

## Desired End State

A Walker visiting `/walker_walks` sees their active walk (unchanged) and below it a "Past walks" section listing completed walks (newest first, up to 50 rows). Each row shows dog name, breed, completed_at, and the owner's display name. Empty state: "No past walks yet." Cross-walker isolation is enforced by the `accepted_by_walker_id` scope.

## Key Decisions Made

| Decision | Choice | Why (1 sentence) |
|---|---|---|
| History location | Extend /walker_walks (not a new route) | Mirrors S-08 pattern; no new nav or route needed. |
| History scope | All terminal states via `.where.not(accepted/in_progress)` | Future-proof; effectively only completed in v1 since walkers can't cancel. |
| Owner identity in history | Yes — owner.display_label | Symmetric with S-08 showing walker name to owner; both parties made visible during the walk. |
| Query limit | .limit(50) | Consistent with S-08's F2 review fix; prevents unbounded queries. |

## Scope

**In scope:** `@past_walks` query added to WalkerWalksController#index, Past section in view, 3 integration tests (history visibility, empty state, cross-walker isolation)

**Out of scope:** New routes; pagination UI; walk detail page; real-time update; owner walk history (S-08, done)

## Architecture / Approach

Single controller extension + view extension. `@past_walks` scoped strictly to `accepted_by_walker_id: current_user.id` — this is the PRD §NFR load-bearing invariant. Owner eager-loaded for display. Pattern identical to S-08's @past_walks.

## Phases at a Glance

| Phase | What it delivers | Key risk |
|---|---|---|
| 1. Controller + Tests | @past_walks query, 3 new integration tests | Scope must use accepted_by_walker_id not a broader walk scope |
| 2. View Past Section | Past section with dog, completed_at, owner name | nil-guard on completed_at (&.) per S-08 lesson |

**Prerequisites:** S-05 (walker-accepts-request) + S-07 (walker-starts-and-completes-walk) archived — both done.
**Estimated effort:** ~1 session across 2 phases

## Open Risks & Assumptions

- Walker B's completed walks must not appear for Walker A — enforced by the `accepted_by_walker_id` scope at the controller level (same mechanism as S-07).
- `completed_at` may be nil in edge cases (data repair); use `&.to_fs(:short)` per S-08's F1 fix.

## Success Criteria (Summary)

- Walker sees their completed walks in the Past section with dog, owner, and date
- Cross-walker isolation verified by integration test
- Active walk section unchanged and still functional
