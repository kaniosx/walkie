# Owner Walk History — Implementation Plan

## Overview

Enrich the Owner's walk list into a proper history: include cancelled walks, split the view into Active (REQUESTED / ACCEPTED / IN_PROGRESS) and Past (COMPLETED / CANCELLED) sections, and show lifecycle timestamps + walker display name on Past rows. No new routes, no controller actions, no migrations — this is a controller query adjustment and a view rewrite.

## Current State Analysis

- `WalksController#index` at `app/controllers/walks_controller.rb:4-6`: queries `current_user.owned_walks.where.not(state: :cancelled).includes(:dog).order(created_at: :desc)`, assigns to `@walks`.
- `app/views/walks/index.html.erb`: single flat list showing dog name, humanized state, created_at, Cancel button for REQUESTED walks. Bare and unsplit.
- COMPLETED walks already appear (only cancelled are filtered). The current view mixes active and past walks in one list, contrary to the PRD NFR that completed walks "no longer appear as active items" but stay in history.
- `Walk` schema: `accepted_at`, `started_at`, `completed_at`, `cancelled_at` columns all exist. `accepted_by_walker` association (`belongs_to :accepted_by_walker, class_name: "User", optional: true`) exists on the Walk model. User model has `display_label` method.
- **Missing:** cancelled walks in the list; Active/Past split; lifecycle timestamps; walker identity for Past rows.

## Desired End State

An Owner visiting `/walks` sees two clearly separated sections:
- **Active** — walks in REQUESTED, ACCEPTED, or IN_PROGRESS state, newest first. Cancel button present for REQUESTED. Shows the walk's current state and created_at.
- **Past** — walks in COMPLETED or CANCELLED state, newest first. Shows state, the key timestamp for that state (completed_at or cancelled_at), and the walker's display_label for COMPLETED walks.

If either section is empty, a helpful message is shown for that section. PRD §NFR ("role separation never leaks") is maintained — only the current user's own walks appear.

### Key Discoveries:

- Active scope: `app/models/walk.rb:18` — `scope :active, -> { where(state: %w[requested accepted in_progress]) }` — reuse directly for `@active_walks`
- Past query: `Walk.where(state: %w[completed cancelled])` — no existing scope; declare inline
- Walker association: `app/models/walk.rb:4` — `belongs_to :accepted_by_walker, class_name: "User", optional: true` — eager-load for N+1 prevention
- User display name: `app/models/user.rb` — `display_label` method returns `display_name || email_address`
- Timestamps in schema: `completed_at`, `cancelled_at` — use `walk.completed_at` / `walk.cancelled_at` directly
- Security invariant: both queries are scoped to `current_user.owned_walks` — no cross-Owner leakage possible

## What We're NOT Doing

- No new routes, actions, or controller (WalksController already has index)
- No walker identity for ACCEPTED or IN_PROGRESS active walks (only Past/COMPLETED walks show the walker — limiting the privacy surface to the completed case where the walk is over)
- No pagination (walk counts are small in v1)
- No real-time update (PRD §Non-Goals)
- No walker walk history (S-09)

## Implementation Approach

Split the single `@walks` assignment into `@active_walks` and `@past_walks`, each scoped and eager-loaded. Rewrite the view into two sections. Integration tests verify both sections independently, including the role-separation invariant (Owner B cannot see Owner A's walks).

## Phase 1: Controller Split + Integration Tests

### Overview

Replace the single `@walks` query with two: `@active_walks` and `@past_walks`. Add `:accepted_by_walker` to the includes chain so the view can render walker names without N+1. Extend the integration test to verify both sections.

### Changes Required:

#### 1. WalksController#index

**File**: `app/controllers/walks_controller.rb`

**Intent**: Replace the single `@walks` assignment with two scoped queries so the view can render Active and Past sections independently.

**Contract**:
- `@active_walks`: `current_user.owned_walks.active.includes(:dog).order(created_at: :desc)`
- `@past_walks`: `current_user.owned_walks.where(state: %w[completed cancelled]).includes(:dog, :accepted_by_walker).order(created_at: :desc)`
- Remove the old `@walks` assignment entirely.

#### 2. Integration tests

**File**: `test/integration/walks_test.rb`

**Intent**: Update and extend the integration tests to cover the two-section layout, cancelled walk visibility, and the role-separation NFR for history.

**Contract**: Adjust or add test cases —
1. Owner with one REQUESTED walk sees it in the Active section, not Past
2. Owner with one COMPLETED walk sees it in the Past section, not Active
3. Owner with one CANCELLED walk sees it in the Past section
4. Owner B cannot see Owner A's walks (existing scoping invariant — update any assertion that used `@walks` to use the new section structure)
5. Unauthenticated access still redirects to sign-in (existing test, no change needed)

### Success Criteria:

#### Automated Verification:

- Integration tests pass: `docker compose exec web bin/rails test test/integration/walks_test.rb`
- Full suite passes: `docker compose exec web bin/rails test`
- Rubocop passes: `docker compose exec web bundle exec rubocop app/controllers/walks_controller.rb test/integration/walks_test.rb`

#### Manual Verification:

- `/walks` page loads without error with the controller change in place (view will be temporarily broken until Phase 2 — accept a render error or stub the view if needed, or implement both phases together)

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase. Phase blocks use plain bullets — the corresponding `- [ ]` checkboxes for these items live in the `## Progress` section at the bottom of the plan.

---

## Phase 2: View Rewrite

### Overview

Replace the flat walk list with two sections (Active / Past), add lifecycle timestamps to Past rows, and show the walker's display name for COMPLETED Past walks.

### Changes Required:

#### 1. Walks index view

**File**: `app/views/walks/index.html.erb`

**Intent**: Rewrite the view to render two distinct sections using `@active_walks` and `@past_walks`, with enriched display for the Past section.

**Contract**:

Active section:
- Heading: "Active" (or "My active walk requests")
- Each row: dog name (strong), state humanized, created_at short, Cancel button if `walk.requested?`
- Empty state: "No active walk requests."

Past section:
- Heading: "Past" (or "Walk history")
- Each row: dog name (strong), state humanized, the relevant terminal timestamp (`walk.completed_at` for completed, `walk.cancelled_at` for cancelled, both formatted short), and for COMPLETED walks: walker display name via `walk.accepted_by_walker&.display_label`
- Empty state: "No past walks yet."

### Success Criteria:

#### Automated Verification:

- Full suite passes: `docker compose exec web bin/rails test`
- Rubocop passes: `docker compose exec web bundle exec rubocop app/views/walks/index.html.erb`

#### Manual Verification:

- Owner with an active REQUESTED walk sees it in "Active" section with Cancel button
- Owner with a COMPLETED walk sees it in "Past" section with the walker's name and completed_at
- Owner with a CANCELLED walk sees it in "Past" section with cancelled_at (no walker name — walk never reached ACCEPTED)
- Owner with no past walks sees "No past walks yet." in the Past section
- Owner B cannot see Owner A's walks in either section

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase. Phase blocks use plain bullets — the corresponding `- [ ]` checkboxes for these items live in the `## Progress` section at the bottom of the plan.

---

## Testing Strategy

### Integration Tests:

- `test/integration/walks_test.rb` — existing tests updated + new section-specific tests

### Manual Testing Steps:

1. Sign in as Owner with a REQUESTED walk → verify it appears in Active, not Past
2. Accept the walk as a Walker, then complete it → sign in as Owner → verify it moves to Past with walker name + completed_at
3. Sign in as Owner → create a new walk → cancel it → verify it appears in Past with cancelled_at
4. Sign in as a second Owner → verify only their own walks appear in both sections

## References

- WalksController: `app/controllers/walks_controller.rb`
- Walk model active scope: `app/models/walk.rb:18`
- Walker display label: `app/models/user.rb` — `display_label` method
- PRD: FR-015, §NFR (role separation, history immutability)
- S-04 archived plan: `context/archive/2026-06-16-owner-creates-walk-request/plan.md`
- S-06 archived plan: `context/archive/2026-06-19-owner-cancels-requested-walk/plan.md`

## Progress

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles. See `references/progress-format.md`.

### Phase 1: Controller Split + Integration Tests

#### Automated

- [x] 1.1 Integration tests pass: walks_test.rb — 8d5ced2
- [x] 1.2 Full suite passes: bin/rails test — 8d5ced2
- [x] 1.3 Rubocop passes on walks_controller.rb and walks_test.rb — 8d5ced2

#### Manual

- [x] 1.4 /walks page loads without error with controller change in place

### Phase 2: View Rewrite

#### Automated

- [x] 2.1 Full suite passes: bin/rails test — 12e8349
- [x] 2.2 Rubocop passes on walks/index.html.erb — 12e8349

#### Manual

- [x] 2.3 REQUESTED walk appears in Active section with Cancel button — 12e8349
- [x] 2.4 COMPLETED walk appears in Past section with walker name and completed_at — 12e8349
- [x] 2.5 CANCELLED walk appears in Past section with cancelled_at, no walker name — 12e8349
- [x] 2.6 Cross-owner isolation: Owner B cannot see Owner A's walks — 12e8349
