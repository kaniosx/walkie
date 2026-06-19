# Owner Cancels a Requested Walk — Implementation Plan

## Overview

Wire the cancel flow for S-06: the Owner who created a walk request can cancel it while it is still in REQUESTED state. `Walk#cancel!` and the `cancelled` DB state already exist from F-02; this plan adds the route, controller action, view button, and integration tests.

## Current State Analysis

- `Walk#cancel!(owner)` exists at `app/models/walk.rb:70-74` — atomic `swap_state` REQUESTED → CANCELLED, guards `owner_id`, sets `cancelled_at`. Returns `true` on success, `false` if wrong state or wrong owner (covers the race with a simultaneous accept).
- `cancelled` enum value and `cancelled_at` column are in the schema; DB `walks_walker_presence` CHECK constraint permits NULL `accepted_by_walker_id` in cancelled state.
- `WalksController` (`app/controllers/walks_controller.rb`) already includes `OwnerOnly` — all actions are Owner-gated by default.
- Index query (`walks_controller.rb:5`) shows all owned walks; cancelled walks must be filtered out (user decision).
- **Missing:** cancel route, controller action, view cancel button, integration tests.

## Desired End State

An Owner viewing `/walks` sees a "Cancel" button next to each REQUESTED walk. Clicking triggers a browser confirm dialog; confirming POSTs to `cancel_walk_path`. On success: the walk disappears from the list and a notice "Walk request cancelled." is shown. If a Walker accepted the walk between page load and the cancel submit, the Owner sees "This request was already accepted by a walker." and the walk remains in the list (now in Accepted state).

### Key Discoveries:

- `Walk#cancel!`: `app/models/walk.rb:70-74` — already handles the race via `swap_state`
- Index query to extend: `app/controllers/walks_controller.rb:5` — add `.where.not(state: :cancelled)`
- Route pattern: `config/routes.rb:7-9` — member `post :accept` on `open_requests`
- Controller pattern: `app/controllers/open_requests_controller.rb:10-22` — boolean → notice/alert branch

## What We're NOT Doing

- No cancellation of ACCEPTED / IN_PROGRESS / COMPLETED walks (FR-010 is REQUESTED-only; post-accept cancel is PRD §Open Q #5, explicit post-v1)
- No soft-delete of the Walk record — `cancelled` state is the permanent record
- No real-time UI update — Owner sees the result after the redirect (PRD §Non-Goals)
- No walk show/detail page — cancel lives on the index

## Implementation Approach

Mirrors the `accept!` wiring. The `cancel!` boolean return drives the flash branch; the view renders the button conditionally on `walk.requested?`; the index query filters cancelled walks at the controller level.

## Phase 1: Route + Controller

### Overview

Add the cancel member route to `walks` and the matching controller action. Extend the index query to exclude cancelled walks.

### Changes Required:

#### 1. Routes

**File**: `config/routes.rb`

**Intent**: Add a `cancel` POST member action to the `walks` resource.

**Contract**: `POST /walks/:id/cancel` → `walks#cancel`, named helper `cancel_walk_path(walk)`.

```ruby
resources :walks, only: %i[index create] do
  member { post :cancel }
end
```

#### 2. WalksController — index filter + cancel action

**File**: `app/controllers/walks_controller.rb`

**Intent**: Filter cancelled walks from the index and add a `cancel` action that finds the owner's own walk, calls `cancel!(current_user)`, and redirects with flash.

**Contract**:
- Index: chain `.where.not(state: :cancelled)` before `.includes(:dog)`.
- Cancel: scoped lookup `current_user.owned_walks.find(params[:id])` (raises `RecordNotFound` → 404 for another owner's walk). On `cancel!` returning true → `redirect_to walks_path, notice: "Walk request cancelled."`. On false → `redirect_to walks_path, alert: "This request was already accepted by a walker."`

### Success Criteria:

#### Automated Verification:

- Rubocop passes: `docker compose exec web bundle exec rubocop app/controllers/walks_controller.rb config/routes.rb`

#### Manual Verification:

- `POST /walks/:id/cancel` on a REQUESTED walk owned by `current_user` → redirect to `/walks`, notice "Walk request cancelled."
- `POST /walks/:id/cancel` on an ACCEPTED walk → redirect to `/walks`, alert "This request was already accepted by a walker."
- `POST /walks/:id/cancel` on another owner's walk → 404

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase. Phase blocks use plain bullets — the corresponding `- [ ]` checkboxes for these items live in the `## Progress` section at the bottom of the plan.

---

## Phase 2: View + Integration Tests

### Overview

Add the cancel button to the walks index view for REQUESTED-state walks. Write integration tests covering the happy path, race simulation, ownership guard, and role guard.

### Changes Required:

#### 1. Walks index view

**File**: `app/views/walks/index.html.erb`

**Intent**: Show a Cancel button inline with each REQUESTED walk. Use `data-turbo-confirm` so Turbo prompts before submitting.

**Contract**: Inside the `@walks.each` block, conditionally render a `button_to` for `walk.requested?` only:

```erb
<% if walk.requested? %>
  <%= button_to "Cancel", cancel_walk_path(walk), method: :post,
        data: { turbo_confirm: "Cancel this walk request?" } %>
<% end %>
```

#### 2. Integration tests

**File**: `test/integration/walks_cancel_test.rb`

**Intent**: Cover five observable HTTP scenarios at the controller boundary.

**Contract**: Five test cases —
1. Owner cancels own REQUESTED walk → 302 redirect to `walks_path`, flash notice present, walk state `cancelled` in DB
2. Owner cancels own ACCEPTED walk (race simulation — manually set state to accepted beforehand) → 302 redirect, flash alert "This request was already accepted by a walker."
3. Owner cancels another owner's walk → 404
4. Walker attempts cancel → 302 redirect (OwnerOnly concern fires)
5. Unauthenticated cancel attempt → 302 redirect to sign-in

### Success Criteria:

#### Automated Verification:

- Integration tests pass: `docker compose exec web bin/rails test test/integration/walks_cancel_test.rb`
- Full suite passes: `docker compose exec web bin/rails test`
- Rubocop passes: `docker compose exec web bundle exec rubocop app/views/walks/index.html.erb test/integration/walks_cancel_test.rb`

#### Manual Verification:

- Cancel button is visible next to REQUESTED walks and absent next to ACCEPTED / COMPLETED walks
- Clicking Cancel triggers the browser confirmation dialog ("Cancel this walk request?")
- Confirming: walk disappears from the list, notice "Walk request cancelled." appears
- Cancelled walks do not reappear on refresh
- Race scenario (accept in tab 1, cancel via tab 2) → tab 2 shows "This request was already accepted by a walker." and the walk stays in the list as Accepted

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase. Phase blocks use plain bullets — the corresponding `- [ ]` checkboxes for these items live in the `## Progress` section at the bottom of the plan.

---

## Testing Strategy

### Integration Tests:

- `test/integration/walks_cancel_test.rb` — five test cases above

### Manual Testing Steps:

1. Sign in as an Owner with at least one REQUESTED walk → confirm Cancel button is visible
2. Click Cancel → confirm browser dialog appears
3. Confirm dialog → confirm redirect, notice, walk gone from list
4. Create a second request, accept it as a Walker in another tab, then attempt Cancel as Owner → confirm "already accepted" alert
5. Sign in as a second Owner → attempt `POST /walks/:id/cancel` on first Owner's walk ID → confirm 404

## References

- Walk model cancel method: `app/models/walk.rb:70-74`
- Accept! controller pattern: `context/archive/2026-06-17-walker-accepts-request/plan.md`
- Route pattern: `config/routes.rb:7-9`
- PRD: FR-010; §Open Q #5 (post-accept cancellation explicitly post-v1)

## Progress

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles. See `references/progress-format.md`.

### Phase 1: Route + Controller

#### Automated

- [x] 1.1 Rubocop passes on walks_controller.rb and routes.rb

#### Manual

- [ ] 1.2 POST /walks/:id/cancel on REQUESTED walk → notice "Walk request cancelled."
- [ ] 1.3 POST /walks/:id/cancel on ACCEPTED walk → alert "This request was already accepted by a walker."
- [ ] 1.4 POST /walks/:id/cancel on another owner's walk → 404

### Phase 2: View + Integration Tests

#### Automated

- [ ] 2.1 Integration tests pass: walks_cancel_test.rb
- [ ] 2.2 Full suite passes: bin/rails test
- [ ] 2.3 Rubocop passes on index.html.erb and walks_cancel_test.rb

#### Manual

- [ ] 2.4 Cancel button present on REQUESTED walks, absent on other states
- [ ] 2.5 Browser confirmation dialog appears on click
- [ ] 2.6 Cancel succeeds: walk disappears from list, notice shown
- [ ] 2.7 Race simulation (accept in tab 1, cancel in tab 2) shows "This request was already accepted by a walker."
