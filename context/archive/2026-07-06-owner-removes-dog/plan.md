# Owner Removes Dog — Implementation Plan

## Overview

Wire the final piece of FR-008: an Owner can deactivate their dog via a "Remove" button.
The soft-delete model infrastructure (`deactivated_at` column, `Dog.active` scope,
`deactivate!` method) was already delivered in F-02/S-03. This plan adds the route,
controller action, view button, and integration tests — nothing touches the DB schema or
the model layer.

## Current State Analysis

The soft-delete stack is complete at the model level:

- `deactivated_at :datetime` column on `dogs` table — `schema.rb:20`
- `scope :active, -> { where(deactivated_at: nil) }` — `app/models/dog.rb:22`
- `deactivate!` method (stamps `deactivated_at: Time.current`) — `app/models/dog.rb:26-28`
- `active?` predicate — `app/models/dog.rb:30-32`
- `has_many :walks, dependent: :restrict_with_exception` prevents accidental hard-delete — `app/models/dog.rb:6`
- `current_user.dogs.active` already used in `DogsController#index` — controller:7
- `current_user.dogs.active.find(params[:dog_id])` already in `WalksController#create` — walks_controller:31
- `current_user.dogs.active` already in `home/index.html.erb` — home:6
- Dog model tests for soft-delete lifecycle — `test/models/dog_test.rb:60-83`

The `:destroy` route, controller action, view entry-point, and integration test coverage
are the only missing pieces.

## Desired End State

1. `DELETE /dogs/:id` route exists and is owner-authenticated.
2. Clicking "Remove" on a dog with **no** active walks soft-deletes it (`deactivated_at` set),
   redirects to `dogs_path` with a success flash, and the dog disappears from the index.
3. Clicking "Remove" on a dog with **any** active walk (REQUESTED / ACCEPTED / IN_PROGRESS)
   redirects back with an error flash; the dog record is unchanged.
4. Walk history for both Owner and Walker still shows the dog name/breed (soft-delete
   preserves the `Dog` row; `Walk#dog` association still resolves).
5. Another Owner's dog, or a Walker trying to call the route, receives 404 or redirect
   (enforced by `OwnerOnly` concern + `current_user.dogs` scoping in `set_dog`).

### Key Discoveries

- `config/routes.rb:5` — `resources :dogs, only: %i[ index new create edit update ]` — `:destroy` explicitly excluded (leftover from S-03 pending this slice).
- `app/controllers/dogs_controller.rb:4` — `before_action :set_dog, only: %i[edit update]` — needs `:destroy` added.
- `app/controllers/dogs_controller.rb:37-39` — `set_dog` uses `current_user.dogs.find` (all dogs, not only active) — intentional; destroy action can idempotently deactivate an already-deactivated dog with no harm.
- `app/views/dogs/index.html.erb` — currently only "Edit" link per dog card; "Remove" button is the new addition.
- `test/integration/dogs_test.rb` (99 lines) — no destroy coverage; integration test style follows existing patterns in the file (sign-in helpers, flash assertions, DB state checks).

## What We're NOT Doing

- No schema migration — `deactivated_at` already exists.
- No model changes — `deactivate!`, `Dog.active`, `active?` already exist; tests already pass.
- No changes to `open_requests`, `walker_walks`, or walk history views — deactivated-dog walks
  are already filtered at the Walk creation layer; a deactivated dog with no active walks has
  nothing pending to show.
- No soft-delete for walks — walks are never deleted; history is always preserved.
- No post-deactivation "undo" / reactivation flow — out of scope for v1.

## Implementation Approach

Three sequential changes, each independently verifiable:

1. **Route + Controller** — add `:destroy` to `resources :dogs` and implement the `destroy`
   action with the active-walk guard.
2. **View** — add a "Remove" `button_to` with Turbo confirm to `dogs/index.html.erb`.
3. **Tests** — add integration tests to `test/integration/dogs_test.rb` covering the happy
   path, the guard, and the authorization boundary.

## Critical Implementation Details

**Active-walk guard uses `Walk.active` scope, not a DB constraint.** The guard is a Rails-layer
check (`@dog.walks.active.exists?`), not a DB-level check. This is intentional — the DB FK
is `on_delete: :restrict` which only fires on hard `DELETE`; `deactivate!` does a soft-delete
(`UPDATE dogs SET deactivated_at = ?`) that the FK never sees. The Rails guard is sufficient
because the state machine already prevents concurrent invalid transitions at the DB level.

**`deactivate!` is unconditional.** It always sets `deactivated_at = Time.current` with no
guard of its own. The controller is responsible for the active-walk check *before* calling it.
Do not add a guard inside `deactivate!` — that method is used by F-02 tests that expect it to
be a simple stamp.

**Turbo confirm on `button_to`.** Use `data: { turbo_confirm: "..." }` — this delegates the
confirmation to Turbo's built-in dialog (no custom JS). The existing `tailwindcss-rails`
pipeline is already set up; no additional asset work needed.

---

## Phase 1: Route + Controller

### Overview

Add `:destroy` to the dogs routes and implement a `destroy` action in `DogsController`
that calls `deactivate!` if no active walks exist, or rejects with a flash error if they do.

### Changes Required

#### 1. `config/routes.rb`

**File:** `config/routes.rb`

**Intent:** Add `:destroy` to the explicit `only:` list on `resources :dogs` so the
`DELETE /dogs/:id` path is routable.

**Contract:** Change `only: %i[ index new create edit update ]` to include `:destroy`.
Result: `resources :dogs, only: %i[ index new create edit update destroy ]`.

#### 2. `app/controllers/dogs_controller.rb` — before_action

**File:** `app/controllers/dogs_controller.rb`

**Intent:** Include `:destroy` in the `set_dog` before_action so `@dog` is populated and
owner-scoped before the action fires.

**Contract:** Change `before_action :set_dog, only: %i[edit update]` to
`before_action :set_dog, only: %i[edit update destroy]`.

#### 3. `app/controllers/dogs_controller.rb` — destroy action

**File:** `app/controllers/dogs_controller.rb`

**Intent:** Implement the `destroy` action. Guard against active walks; call `deactivate!`
on the happy path. Both paths redirect to `dogs_path`.

**Contract:** New public method `destroy` after the existing `update` action. Uses
`@dog.walks.active.exists?` (the `Walk.active` scope covers `requested, accepted,
in_progress`). On guard failure: `redirect_to dogs_path, alert: "..."`. On success:
`@dog.deactivate!` then `redirect_to dogs_path, notice: "..."`.

Flash messages should reference the dog's name (`@dog.name`) so the Owner knows which dog
was affected:

```ruby
# alert path
redirect_to dogs_path,
  alert: "#{@dog.name} has an active walk — cancel or wait for it to complete before removing."

# notice path
redirect_to dogs_path, notice: "#{@dog.name} was removed."
```

### Success Criteria

#### Automated Verification

- `docker compose exec web bin/rails test test/models/dog_test.rb` — all existing model tests still pass (no regression).
- `docker compose exec web bundle exec rubocop app/controllers/dogs_controller.rb config/routes.rb` — no offences.

#### Manual Verification

- `docker compose exec web bin/rails routes | grep dogs` — `destroy dogs DELETE /dogs/:id` appears in output.
- Rails console: create a dog, call `dog.deactivate!` — confirm `dog.deactivated_at` is set and `Dog.active` excludes it.

**Pause here after manual verification passes before proceeding to Phase 2.**

---

## Phase 2: View — Remove Button

### Overview

Add a "Remove" button to each dog card in `dogs/index.html.erb`. The button uses
`button_to` with `method: :delete` and a Turbo confirm dialog.

### Changes Required

#### 1. `app/views/dogs/index.html.erb`

**File:** `app/views/dogs/index.html.erb`

**Intent:** Add a destructive "Remove" action alongside the existing "Edit" link for each
dog card. The Turbo confirm dialog gives the Owner a chance to cancel. No server-side
availability check in the view — the guard lives exclusively in the controller.

**Contract:** Add a `button_to` after the existing "Edit" link at line 14. Method `:delete`,
path `dog_path(dog)`, Turbo confirm text should mention that walk history is preserved
("Your walk history will be kept.") to reduce anxiety about data loss. Style with a red /
destructive Tailwind class consistent with the existing badge/button conventions in the
stylesheet (e.g., `bg-red-600 hover:bg-red-700 text-white`).

### Success Criteria

#### Automated Verification

- `docker compose exec web bundle exec rubocop app/views/dogs/index.html.erb` — no offences (if ERB rubocop is active).

#### Manual Verification

- Start app (`make start`), sign in as an Owner, navigate to `/dogs`.
- Each dog card shows a "Remove" button next to "Edit".
- Clicking "Remove" triggers the browser confirm dialog with the expected text.
- Confirming on a dog with **no** active walks:
  - Dog disappears from the index.
  - Flash notice: "<dog_name> was removed."
  - Walk history (Owner's `/walks` view) still shows past walks for the removed dog.
- Clicking "Remove" on a dog with an active walk (create one first via "Walk my dog"):
  - Redirects back to `/dogs`, dog still listed.
  - Flash alert: "<dog_name> has an active walk — cancel or wait for it to complete before removing."

**Pause here after manual verification passes before proceeding to Phase 3.**

---

## Phase 3: Integration Tests

### Overview

Add test coverage for the new `destroy` action to `test/integration/dogs_test.rb`.
Follows the existing file's pattern: sign-in helpers, `assert_redirected_to`, flash
assertions, and DB state checks.

### Changes Required

#### 1. `test/integration/dogs_test.rb`

**File:** `test/integration/dogs_test.rb`

**Intent:** Cover the four meaningful paths through the destroy action: happy path
(deactivates, preserves walks, redirects with notice), active-walk guard (no deactivation,
redirects with alert), cross-owner rejection (another owner's dog returns 404 or 401/redirect),
walker rejection (already blocked by OwnerOnly concern).

**Contract:** Append four new test methods to the existing file. Each is standalone (creates
its own fixtures/records). Reference the existing file's `sign_in_as` / `post` / `delete`
helpers and `assert_response` / `assert_redirected_to` / `assert_match` patterns.

Test names and their assertion focus:
1. `test "owner can deactivate dog with no active walks"`:
   - After `delete dog_path(dog)`, `dog.reload.active?` returns `false`; `dog.walks.count` is unchanged; redirects to `dogs_path`; flash notice contains dog name.
2. `test "owner cannot deactivate dog with active walk"`:
   - Create a walk in `requested` state for the dog. After `delete dog_path(dog)`, `dog.reload.active?` returns `true`; redirects to `dogs_path`; flash alert contains dog name.
3. `test "owner cannot deactivate another owner's dog"`:
   - Use a second owner fixture. `delete dog_path(other_owners_dog)` → 404 (set_dog scopes via `current_user.dogs`).
4. `test "walker cannot deactivate a dog"`:
   - Sign in as walker. `delete dog_path(dog)` → redirect to root (OwnerOnly concern).

### Success Criteria

#### Automated Verification

- `docker compose exec web bin/rails test test/integration/dogs_test.rb` — all tests pass including the four new ones.
- `docker compose exec web bin/rails test` — full suite green.
- SimpleCov report (output after test run): `destroy` action lines covered.

#### Manual Verification

- Review coverage report (`coverage/index.html` if SimpleCov is wired) — `DogsController#destroy` branch for guard and happy path both covered.

---

## Testing Strategy

### Unit Tests

Existing `test/models/dog_test.rb` already covers `deactivate!` and `Dog.active` scope —
no additions needed at the model level.

### Integration Tests

Four new tests in `test/integration/dogs_test.rb` as specified in Phase 3.

### Manual Testing Steps

1. Sign in as Owner → `/dogs` → confirm "Remove" button visible on each dog card.
2. Click "Remove" on a dog without active walks → confirm dog disappears + flash notice.
3. Navigate to `/walks` → confirm walk history still shows the removed dog's name.
4. Create a new walk request ("Walk my dog") → confirm removed dog is NOT offered as an option (it's excluded by `Dog.active` scope in both the index and the walk creation path).
5. Click "Remove" on a dog with a REQUESTED walk → confirm error flash, dog still visible.
6. Sign in as Walker → try `DELETE /dogs/:id` directly → confirm redirect to root/sign-in.

## Performance Considerations

`@dog.walks.active.exists?` generates a single `EXISTS` query — no performance concern.
The `Dog.active` scope on the index is already in place; no additional queries from
this feature.

## Migration Notes

No migration required. `deactivated_at` column was added in `20260603072326_create_dogs.rb`.

## References

- Roadmap: `context/foundation/roadmap.md` — S-10, decision 2026-07-06 (soft-delete)
- Dog model: `app/models/dog.rb` — `deactivate!`, `Dog.active`
- Schema: `db/schema.rb:17-27` — dogs table; `:20` — `deactivated_at`
- Existing tests: `test/models/dog_test.rb:60-83` — soft-delete model coverage
- Existing controller: `app/controllers/dogs_controller.rb` — `set_dog`, `OwnerOnly`

---

## Progress

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles.

### Phase 1: Route + Controller

#### Automated

- [x] 1.1 Dog model tests pass — no regression (`bin/rails test test/models/dog_test.rb`) — 980f121
- [x] 1.2 Rubocop clean on controller + routes — 980f121

#### Manual

- [x] 1.3 `bin/rails routes` shows `destroy dogs DELETE /dogs/:id` — 980f121
- [x] 1.4 Rails console: `dog.deactivate!` stamps `deactivated_at`; `Dog.active` excludes it — 980f121

### Phase 2: View — Remove Button

#### Automated

- [x] 2.1 Rubocop clean on `dogs/index.html.erb` — 0f7d598

#### Manual

- [x] 2.2 "Remove" button visible on each dog card in `/dogs` — 0f7d598
- [x] 2.3 Turbo confirm dialog appears on click with expected text — 0f7d598
- [x] 2.4 Happy path: dog disappears + flash notice, walk history preserved — 0f7d598
- [x] 2.5 Guard path: flash alert when dog has active walk, dog stays in list — 0f7d598

### Phase 3: Integration Tests

#### Automated

- [x] 3.1 `bin/rails test test/integration/dogs_test.rb` — all 4 new tests pass — 2170b68
- [x] 3.2 Full suite green (`bin/rails test`) — 2170b68
- [x] 3.3 SimpleCov covers `DogsController#destroy` happy path + guard branch — 2170b68

#### Manual

- [x] 3.4 Coverage report confirms both destroy branches covered — 2170b68
