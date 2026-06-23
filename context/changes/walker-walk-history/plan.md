# Walker Walk History — Implementation Plan

## Overview

Add a Past walks section to the Walker's `/walker_walks` page (S-09). S-07 built the active walk view; this slice extends it with a history section showing all terminal-state walks accepted by this Walker, with dog name, breed, completed_at, and owner display_label.

## Current State Analysis

- `WalkerWalksController#index` at `app/controllers/walker_walks_controller.rb:4-10`: assigns `@walk` (single active walk — accepted or in_progress, or nil). No history query.
- `app/views/walker_walks/index.html.erb`: renders `@walk` with "My active walk" heading and Start/End buttons. No Past section.
- **Critical scoping constraint** (roadmap §S-09 Risk): the history query must use `Walk.where(accepted_by_walker_id: current_user.id)`. A broader scope (e.g. all walks a walker can *see*) would leak open requests from other Owners into history.
- Walk `owner` association: `belongs_to :owner, class_name: "User"` — must eager-load for view display.
- User `display_label`: `app/models/user.rb` — returns display_name or email_address.
- **Missing:** `@past_walks` query; Past section in view.

## Desired End State

A signed-in Walker visiting `/walker_walks` sees their active walk (unchanged) and below it a "Past walks" section listing their completed walks (up to 50), newest first. Each past row shows: dog name, breed, humanized state, completed_at, and "Walked for: owner.display_label". Empty state: "No past walks yet." The PRD §NFR role-separation invariant holds — only walks where `accepted_by_walker_id = current_user.id` appear.

### Key Discoveries:

- Scoping invariant: `Walk.where(accepted_by_walker_id: current_user.id)` — `app/models/walk.rb:4` confirms `accepted_by_walker` is the accepting walker
- Owner association to eager-load: `belongs_to :owner, class_name: "User"` at `app/models/walk.rb:3`
- Pattern to follow: `app/controllers/walks_controller.rb:6-10` (S-08's `@past_walks` query with `.limit(50)`)
- View pattern: `app/views/walks/index.html.erb` (Active/Past two-section layout from S-08)
- S-07 "What We're NOT Doing": "No walker walk history (S-09 is the next slice for that; the index action here shows only the active walk, not full history)"

## What We're NOT Doing

- No new routes or controller actions (WalkerWalksController#index serves both active + history)
- No pagination UI (`.limit(50)` bounds the query)
- No walk detail/show page
- No real-time update (PRD §Non-Goals)
- No owner walk history (S-08, done)

## Implementation Approach

Exact mirror of the S-08 controller extension pattern. Add `@past_walks` to `WalkerWalksController#index`, using `.where.not(state: %w[accepted in_progress])` scoped to `accepted_by_walker_id` to capture all terminal states (effectively completed in v1, future-proof for any new terminal states). Eager-load `:dog` and `:owner`. Extend the view with a Past section.

## Phase 1: Controller Extension + Integration Tests

### Overview

Add `@past_walks` to `WalkerWalksController#index` and write integration tests verifying the history section, role-separation invariant, and empty state.

### Changes Required:

#### 1. WalkerWalksController#index

**File**: `app/controllers/walker_walks_controller.rb`

**Intent**: Extend the index action with a second query that loads all terminal-state walks accepted by this walker.

**Contract**:
- Add alongside the existing `@walk` assignment:
  `@past_walks = Walk.where(accepted_by_walker_id: current_user.id).where.not(state: %w[accepted in_progress]).includes(:dog, :owner).order(created_at: :desc).limit(50)`
- `@walk` assignment is unchanged.

#### 2. Integration tests

**File**: `test/integration/walker_walks_test.rb`

**Intent**: Extend the existing test suite to cover the history section.

**Contract**: Add test cases —
1. Walker with a completed walk sees it in the Past section (dog name + "Completed" present, "No past walks yet." absent)
2. Walker with no completed walks sees "No past walks yet." in the Past section
3. Walker B cannot see Walker A's completed walk in the history (cross-walker role-separation invariant — PRD §NFR "role separation never leaks")

### Success Criteria:

#### Automated Verification:

- Integration tests pass: `docker compose exec web bin/rails test test/integration/walker_walks_test.rb`
- Full suite passes: `docker compose exec web bin/rails test`
- Rubocop passes: `docker compose exec web bundle exec rubocop app/controllers/walker_walks_controller.rb test/integration/walker_walks_test.rb`

#### Manual Verification:

- `/walker_walks` loads without error (view ignores `@past_walks` until Phase 2)

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase. Phase blocks use plain bullets — the corresponding `- [ ]` checkboxes for these items live in the `## Progress` section at the bottom of the plan.

---

## Phase 2: View Past Section

### Overview

Add the Past walks section to the walker walks view, showing dog name, breed, completed_at, and owner display_label.

### Changes Required:

#### 1. Walker walks index view

**File**: `app/views/walker_walks/index.html.erb`

**Intent**: Add a Past walks section below the Active section, displaying each past walk's dog, state, terminal timestamp, and who the walk was for.

**Contract**: Below the existing active walk block, add a "Past walks" section:
- Heading: "Past walks" (or "Walk history")
- If `@past_walks.any?`: `ul` with `li` per walk showing dog name (strong), breed in parens, state humanized, `walk.completed_at&.to_fs(:short)` (nil-guarded per S-08 lesson), "Walked for: walk.owner.display_label"
- Empty state: "No past walks yet."

### Success Criteria:

#### Automated Verification:

- Full suite passes: `docker compose exec web bin/rails test`
- Rubocop passes: `docker compose exec web bundle exec rubocop test/integration/walker_walks_test.rb`

#### Manual Verification:

- Walker with a completed walk sees it in the Past section with dog name, breed, completed_at, and "Walked for: [owner name]"
- Walker with no completed walks sees "No past walks yet."
- Cross-walker isolation: Walker B cannot see Walker A's completed walks
- Active walk (if present) still shows correctly above the Past section

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase. Phase blocks use plain bullets — the corresponding `- [ ]` checkboxes for these items live in the `## Progress` section at the bottom of the plan.

---

## Testing Strategy

### Integration Tests:

- `test/integration/walker_walks_test.rb` — extend existing suite with 3 new test cases

### Manual Testing Steps:

1. Sign in as a Walker who completed a walk → visit /walker_walks → verify Past section shows the dog name and completed_at
2. Sign in as a Walker with no completed walks → verify "No past walks yet." appears
3. Complete a walk as Walker A, then sign in as Walker B → visit /walker_walks → verify Walker A's walk doesn't appear

## References

- WalkerWalksController: `app/controllers/walker_walks_controller.rb`
- S-08 controller pattern (Past section, .limit(50)): `context/archive/2026-06-23-owner-walk-history/`
- Walk owner association: `app/models/walk.rb:3`
- PRD: FR-016, §NFR (role separation)
- Roadmap §S-09 Risk: scope must be `accepted_by_walker_id` only

## Progress

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles. See `references/progress-format.md`.

### Phase 1: Controller Extension + Integration Tests

#### Automated

- [x] 1.1 Integration tests pass: walker_walks_test.rb
- [x] 1.2 Full suite passes: bin/rails test
- [x] 1.3 Rubocop passes on walker_walks_controller.rb and walker_walks_test.rb

#### Manual

- [x] 1.4 /walker_walks loads without error with @past_walks added

### Phase 2: View Past Section

#### Automated

- [ ] 2.1 Full suite passes: bin/rails test
- [ ] 2.2 Rubocop passes on walker_walks_test.rb

#### Manual

- [ ] 2.3 Completed walk appears in Past section with dog name, breed, completed_at, and owner name
- [ ] 2.4 No completed walks → "No past walks yet." shown
- [ ] 2.5 Walker B cannot see Walker A's completed walks
- [ ] 2.6 Active walk still displays correctly above Past section
