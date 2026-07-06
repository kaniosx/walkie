# Owner Removes Dog — Plan Brief

> Full plan: `context/changes/owner-removes-dog/plan.md`

## What & Why

Wire FR-008: an Owner can remove a dog from their account. The model soft-delete
infrastructure (`deactivated_at` column, `deactivate!`, `Dog.active` scope) was built
in F-02/S-03 and already tested. This slice adds the missing controller action, route,
view button, and integration tests — the last must-have FR to close the PRD backlog.

## Starting Point

`resources :dogs, only: %i[ index new create edit update ]` explicitly excludes `:destroy`
(routes.rb:5). The model layer is complete; no DB migration is needed. Walk history views
already reference `walk.dog` associations, which survive soft-delete because the `Dog` row
is never physically removed.

## Desired End State

An Owner sees a "Remove" button on each dog card in `/dogs`. Clicking it (with a Turbo
confirm) deactivates the dog — it disappears from active lists and can no longer receive
new walk requests. Walk history for both Owner and Walker still shows the dog's name/breed.
Attempting to remove a dog with any active walk (REQUESTED / ACCEPTED / IN_PROGRESS)
returns a flash error; the dog is unchanged.

## Key Decisions Made

| Decision | Choice | Why (1 sentence) | Source |
| -------- | ------ | ----------------- | ------ |
| Removal mechanism | Soft-delete (`deactivated_at`) | Preserves walk history for both sides; model infrastructure already exists | Roadmap Q#4 resolved 2026-07-06 |
| Active-walk guard | Block if ANY active walk exists (REQUESTED / ACCEPTED / IN_PROGRESS) | Simplest invariant; no hidden side-effects (no auto-cancel logic needed) | Plan |
| Button UX on blocked dog | Always visible; server returns flash error | Zero conditional view logic; consistent with Rails flash pattern | Plan |
| Confirmation UX | Turbo confirm dialog (`data-turbo-confirm`) | No custom JS; Turbo handles it natively | Plan |

## Scope

**In scope:**
- Route `:destroy` on `resources :dogs`
- `DogsController#destroy` with active-walk guard
- "Remove" `button_to` in `dogs/index.html.erb`
- Integration tests (happy path, guard, cross-owner, walker rejection)

**Out of scope:**
- Schema migration (column already exists)
- Model changes (`deactivate!`, `Dog.active` already exist)
- Reactivation / undo flow
- Changes to open_requests or walk history views (already work correctly after soft-delete)

## Architecture / Approach

Single-layer change: route → controller → view → tests. No new services, jobs, or
associations. The active-walk guard is a Rails-layer `EXISTS` query (`@dog.walks.active.exists?`);
the DB FK `on_delete: :restrict` on `walks.dog_id` is a backstop for any accidental hard-delete
(which `has_many :walks, dependent: :restrict_with_exception` also prevents at the AR layer).

## Phases at a Glance

| Phase | What it delivers | Key risk |
| ----- | ---------------- | -------- |
| 1. Route + Controller | `:destroy` route + action with active-walk guard | Guard must use `Walk.active` scope (not a hand-rolled state check) |
| 2. View | "Remove" button with Turbo confirm | Turbo confirm text should mention history preservation to reduce Owner anxiety |
| 3. Integration tests | 4 new test cases in `dogs_test.rb` | Cross-owner 404 relies on `set_dog` scoping — test must verify the scope, not just the status code |

**Prerequisites:** App running (`make start`); existing dog model tests passing.
**Estimated effort:** ~1 session (3 phases, mostly mechanical wiring).

## Open Risks & Assumptions

- `set_dog` in DogsController scopes via `current_user.dogs` (all dogs, not just active). An already-deactivated dog can be re-sent to `destroy` — `deactivate!` is idempotent so this is harmless, but no test covers this edge case (not added to keep scope tight).
- `Walk.active` scope must stay consistent with what `WalksController` and `OpenRequestsController` use — currently `[requested, accepted, in_progress]`. If that scope ever changes, the guard here breaks silently.

## Success Criteria (Summary)

- `bin/rails test` full suite green including 4 new integration tests.
- Owner can remove a dog with no active walks; walk history preserved; dog gone from index.
- Flash error shown when attempting to remove a dog with any active walk.
