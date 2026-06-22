# Walker Starts + Completes a Walk — Implementation Plan

## Overview

Wire the start and complete transitions for S-07: the Walker who accepted a walk can start it (ACCEPTED → IN_PROGRESS) and end it (IN_PROGRESS → COMPLETED). Both model methods exist from F-02; this plan adds a new `WalkerWalksController`, routes, a "My active walk" view, a nav link, and integration tests.

## Current State Analysis

- `Walk#start!(walker)` at `app/models/walk.rb:58-62` — atomic `swap_state` ACCEPTED → IN_PROGRESS, guard `accepted_by_walker_id: walker.id`, sets `started_at`.
- `Walk#complete!(walker)` at `app/models/walk.rb:64-68` — atomic `swap_state` IN_PROGRESS → COMPLETED, guard `accepted_by_walker_id: walker.id`, sets `completed_at`.
- Both return `true` on success, `false` if wrong state or wrong walker.
- `WalkerOnly` concern exists at `app/controllers/concerns/walker_only.rb` — gates all walker-facing controllers.
- After accepting, a walk disappears from the open_requests list (filtered to `requested` only). There is currently **no UI surface** where the Walker can see their accepted/in-progress walk or advance its state.
- **Missing:** `WalkerWalksController`, start/complete routes, "My active walk" view, nav link, integration tests.

## Desired End State

A signed-in Walker sees a "My walk" nav link. Visiting `/walker_walks` shows their current accepted or in-progress walk with a "Start walk" or "End walk" button (whichever is appropriate to the current state). Clicking either triggers the corresponding transition. If no active walk exists, the page shows "You have no active walk right now." with a link back to open requests. After completing a walk, the Walker is redirected to open_requests with a success notice.

### Key Discoveries:

- `Walk#start!` and `Walk#complete!`: `app/models/walk.rb:58-68` — exist, tested, race-safe via `swap_state`
- Controller pattern to mirror: `app/controllers/open_requests_controller.rb:10-22` — boolean → notice/alert
- WalkerOnly concern: `app/controllers/concerns/walker_only.rb` — include and gate automatically applies
- Nav pattern: `app/views/layouts/application.html.erb` — walker branch adds `link_to` for open_requests; add "My walk" link the same way
- Scoped lookup for start/complete: `Walk.where(accepted_by_walker_id: current_user.id, state: %w[accepted in_progress]).find(params[:id])` — 404s on foreign or completed walks

## What We're NOT Doing

- No cancellation or reversal from IN_PROGRESS or COMPLETED (PRD §NFR: linear state machine, no reverse)
- No Owner confirmation of completion (PRD §Open Q #7, explicit post-v1)
- No walker walk history (S-09 is the next slice for that; the index action here shows only the active walk, not full history)
- No real-time UI update (PRD §Non-Goals)
- No walk show/detail page separate from the index

## Implementation Approach

Mirrors the `accept!` pattern in `OpenRequestsController`. A new `WalkerWalksController` includes `WalkerOnly`, exposes an `index` action that finds the Walker's active walk (accepted or in_progress), and `start` + `complete` member actions that call the corresponding model method and branch on the boolean return. The view is a single page with conditional button rendering based on `walk.accepted?` vs `walk.in_progress?`. Nav gets a "My walk" link in the walker branch.

## Critical Implementation Details

**Active walk scope**: A Walker has at most one active walk at a time (a Walk in `accepted` or `in_progress` state with their `accepted_by_walker_id`). The index action uses `Walk.where(accepted_by_walker_id: current_user.id, state: %w[accepted in_progress]).first` — not `find`, because the Walker doesn't know the ID upfront. The start/complete actions use a scoped `find(params[:id])` restricted to that same walker + state window to produce 404s on stale or foreign requests.

## Phase 1: WalkerWalksController + Routes

### Overview

Create the controller with index, start, and complete actions. Add routes. No view yet — manual verification for this phase is done via curl or the Rails console.

### Changes Required:

#### 1. Routes

**File**: `config/routes.rb`

**Intent**: Add a `walker_walks` resource with start and complete member actions, under WalkerOnly.

**Contract**: `GET /walker_walks` → `walker_walks#index`, `POST /walker_walks/:id/start` → `walker_walks#start`, `POST /walker_walks/:id/complete` → `walker_walks#complete`. Named helpers: `walker_walks_path`, `start_walker_walk_path(walk)`, `complete_walker_walk_path(walk)`.

```ruby
resources :walker_walks, only: %i[index] do
  member do
    post :start
    post :complete
  end
end
```

#### 2. WalkerWalksController

**File**: `app/controllers/walker_walks_controller.rb`

**Intent**: Walker-only controller exposing the active walk (index) and the two state-advance actions (start, complete).

**Contract**:
- Include `WalkerOnly`.
- `index`: find `Walk.where(accepted_by_walker_id: current_user.id, state: %w[accepted in_progress]).includes(:dog).first` → assign to `@walk` (may be nil).
- `start`: scoped `Walk.where(accepted_by_walker_id: current_user.id, state: :accepted).find(params[:id])`. On `walk.start!(current_user)` returning true → `redirect_to walker_walks_path, notice: "Walk started — you're on your way!"`. On false → `redirect_to walker_walks_path, alert: "This walk can no longer be updated."`.
- `complete`: scoped `Walk.where(accepted_by_walker_id: current_user.id, state: :in_progress).find(params[:id])`. On `walk.complete!(current_user)` returning true → `redirect_to open_requests_path, notice: "Walk completed. Well done!"`. On false → `redirect_to walker_walks_path, alert: "This walk can no longer be updated."`.

### Success Criteria:

#### Automated Verification:

- Rubocop passes: `docker compose exec web bundle exec rubocop app/controllers/walker_walks_controller.rb config/routes.rb`

#### Manual Verification:

- `GET /walker_walks` with an accepted walk → 200 (no view yet, but no 500)
- `POST /walker_walks/:id/start` on an ACCEPTED walk → redirect, notice "Walk started — you're on your way!"
- `POST /walker_walks/:id/start` on an IN_PROGRESS walk → redirect, alert "This walk can no longer be updated."
- `POST /walker_walks/:id/complete` on an IN_PROGRESS walk → redirect to open_requests, notice "Walk completed. Well done!"
- `POST /walker_walks/:id/complete` on another walker's walk → 404

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase. Phase blocks use plain bullets — the corresponding `- [ ]` checkboxes for these items live in the `## Progress` section at the bottom of the plan.

---

## Phase 2: View + Nav Link + Integration Tests

### Overview

Add the "My active walk" view with conditional Start/End buttons, add the "My walk" nav link for walkers, and write integration tests covering all observable HTTP scenarios.

### Changes Required:

#### 1. Walker walks index view

**File**: `app/views/walker_walks/index.html.erb`

**Intent**: Show the Walker's active walk with the appropriate action button. Handle the nil case with a helpful empty state.

**Contract**: If `@walk` is nil → show "You have no active walk right now." and a `link_to "See open walk requests", open_requests_path`. If `@walk` present → show dog name, state humanized, and conditionally:
- If `@walk.accepted?` → `button_to "Start walk", start_walker_walk_path(@walk), method: :post`
- If `@walk.in_progress?` → `button_to "End walk", complete_walker_walk_path(@walk), method: :post, data: { turbo_confirm: "End walk? This cannot be undone." }`

#### 2. Nav link for walkers

**File**: `app/views/layouts/application.html.erb`

**Intent**: Add a "My walk" link in the walker branch of the authenticated nav so walkers can reach their active walk without knowing the URL.

**Contract**: In the `elsif current_user.walker?` branch, after the existing `link_to "Open requests", open_requests_path`, add `link_to "My walk", walker_walks_path`.

#### 3. Integration tests

**File**: `test/integration/walker_walks_test.rb`

**Intent**: Cover six observable HTTP scenarios for the start/complete flow.

**Contract**: Six test cases —
1. Walker with accepted walk visits index → 200, sees dog name + "Start walk" button
2. Walker with no active walk visits index → 200, sees empty state message
3. Walker starts an accepted walk → 302 to walker_walks_path, flash notice, walk is in_progress
4. Walker completes an in_progress walk → 302 to open_requests_path, flash notice, walk is completed
5. Walker attempts start on another walker's walk → 404
6. Owner attempts to reach walker_walks index → 302 to root_path (WalkerOnly)

### Success Criteria:

#### Automated Verification:

- Integration tests pass: `docker compose exec web bin/rails test test/integration/walker_walks_test.rb`
- Full suite passes: `docker compose exec web bin/rails test`
- Rubocop passes: `docker compose exec web bundle exec rubocop test/integration/walker_walks_test.rb`

#### Manual Verification:

- Walker with an accepted walk sees the "Start walk" button on /walker_walks
- Walker with an in-progress walk sees the "End walk" button (with confirm dialog) on /walker_walks
- Walker with no active walk sees the empty state + link to open requests
- "My walk" nav link is visible for walkers, absent for owners
- Full start → complete flow works end to end without errors

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase. Phase blocks use plain bullets — the corresponding `- [ ]` checkboxes for these items live in the `## Progress` section at the bottom of the plan.

---

## Testing Strategy

### Integration Tests:

- `test/integration/walker_walks_test.rb` — six test cases above

### Manual Testing Steps:

1. Accept a walk as a Walker → navigate to "My walk" in the nav → confirm "Start walk" button is visible
2. Click "Start walk" → confirm redirect to /walker_walks with notice, walk state is in_progress, "End walk" button now shown
3. Click "End walk" → confirm browser dialog appears, confirm → redirect to /open_requests with "Walk completed" notice
4. Sign in as a different Walker → attempt `POST /walker_walks/:id/start` with the first walker's walk ID → confirm 404
5. Sign in as an Owner → visit /walker_walks → confirm redirect to root with "Only Walkers can do that."

## References

- Walk model start/complete methods: `app/models/walk.rb:58-68`
- Controller pattern: `app/controllers/open_requests_controller.rb`
- WalkerOnly concern: `app/controllers/concerns/walker_only.rb`
- Archived S-05 plan (accept! pattern): `context/archive/2026-06-17-walker-accepts-request/plan.md`
- PRD: FR-013, FR-014, US-03, §NFR (linear state machine), §Open Q #7 (no Owner confirmation, post-v1)

## Progress

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles. See `references/progress-format.md`.

### Phase 1: WalkerWalksController + Routes

#### Automated

- [x] 1.1 Rubocop passes on walker_walks_controller.rb and routes.rb — f282576

#### Manual

- [x] 1.2 GET /walker_walks with accepted walk → 200
- [x] 1.3 POST /walker_walks/:id/start on ACCEPTED walk → notice "Walk started — you're on your way!"
- [x] 1.4 POST /walker_walks/:id/start on IN_PROGRESS walk → alert "This walk can no longer be updated."
- [x] 1.5 POST /walker_walks/:id/complete on IN_PROGRESS walk → redirect to open_requests, notice "Walk completed. Well done!"
- [x] 1.6 POST /walker_walks/:id/complete on another walker's walk → 404

### Phase 2: View + Nav Link + Integration Tests

#### Automated

- [x] 2.1 Integration tests pass: walker_walks_test.rb
- [x] 2.2 Full suite passes: bin/rails test
- [x] 2.3 Rubocop passes on walker_walks_test.rb

#### Manual

- [x] 2.4 Walker with accepted walk sees "Start walk" button on /walker_walks
- [x] 2.5 Walker with in-progress walk sees "End walk" button with confirm dialog
- [x] 2.6 Walker with no active walk sees empty state + link to open requests
- [x] 2.7 "My walk" nav link visible for walkers, absent for owners
- [x] 2.8 Full start → complete flow works end to end
