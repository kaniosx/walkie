# F-02: Domain Data Schema — Dog + Walk + State Machine + DB-level Invariants

## Overview

Stand up the domain data layer for Walkie: a `dogs` table (Owner-owned, soft-deletable) and a `walks` table carrying a linear state machine (`requested → accepted → in_progress → completed`, with a `cancelled` terminal branch off `requested`). The state machine and the single-Walker accept invariant are enforced **outside the UI** — by hand-rolled transition methods that do atomic compare-and-swap `UPDATE`s, backed by DB-level `CHECK` constraints and foreign keys. This is roadmap item **F-02**, the second foundation; it unlocks S-03 (manage dog), S-04 (create request), S-05 (accept — the north star), and S-07 (start/complete). Prerequisite F-01 (`auth-and-role-typing`) is complete — `users` and the role enum exist.

## Current State Analysis

F-01 landed and the repo's conventions are established (confirmed by direct inspection):

- `db/schema.rb` is at version `2026_05_29_132054` with only `users` + `sessions`. No `dogs`, no `walks`. New migrations stack cleanly on top.
- `app/models/user.rb` uses a **string-backed enum** (`enum :role, { owner: "owner", walker: "walker" }`), presence validation, and a private `role_is_immutable` validator with explanatory comments. F-02 mirrors this style.
- Migrations are plain `def change` with intent comments and explicit `null: false` (e.g. `db/migrate/20260529132054_add_role_to_users.rb`).
- Tests are Minitest with inline `build_*` helpers and **no fixtures** (`test/models/user_test.rb`); `test/fixtures/` does not exist. New tests follow the same builder pattern.
- Dev runs in Docker; all Rails commands run via `docker compose exec web …` (no host toolchain).
- The stale `bootstrap_scaffold_*` DB name persists in `config/database.yml` — left as-is (out of scope, same as F-01).

### Key Discoveries:

- **Singleness is structural, not an index.** A `walks` row has a single `accepted_by_walker_id`, so "≤1 Walker per walk" holds by column structure. The roadmap's "partial unique index enforcing Singleness" phrasing doesn't fit a single-FK column — the real invariant the PRD Guardrail names is the **accept race** (two Walkers accepting the same `requested` walk near-simultaneously). The DB backstop is an atomic conditional `UPDATE … WHERE state = 'requested'`, where exactly one transaction reports `affected_rows = 1`.
- **`update_all` bypasses AR validations/callbacks but NOT DB constraints.** The conditional-`UPDATE` transition methods rely on this: the `CHECK` constraints remain the binding backstop even on the raw-SQL write path, and `updated_at` must be set manually in the `update_all` hash.
- **No `default_scope` for soft-delete.** A `default_scope` on `Dog` is a well-known foot-gun (leaks into associations, `unscoped` surprises). Use an explicit `scope :active` instead (`app/models/user.rb` sets the no-magic-scoping precedent).
- **Roadmap settled framing & scope** (`context/foundation/roadmap.md` §F-02); all nine solution-design decisions were made during planning — see `plan-brief.md` Key Decisions table.

## Desired End State

A complete, tested domain schema with no UI: `dogs` and `walks` tables exist with FKs and `CHECK` constraints; `Dog` and `Walk` models carry associations, validations, and (on `Walk`) the four transition methods; the single-Walker accept race is proven correct under real thread contention. Verifiable by: `docker compose exec web bin/rails test` green (including a multi-thread race test), `db/schema.rb` regenerated, rubocop + brakeman + bundler-audit clean, and a console walk-through of the full `requested → accepted → in_progress → completed` lifecycle plus rejection of illegal transitions.

## What We're NOT Doing

- **No controllers, routes, or views** — dog management is S-03, request creation S-04, accept S-05, start/complete S-07, cancel S-06. F-02 is schema + models only.
- **No profile `city`/`postcode` field** — that's S-02 (`profile-with-city`). F-02 snapshots whatever locality string the caller passes onto the walk; S-04 wires it to the real profile field.
- **No request/accept/cancel UI or capability authorization in controllers** — F-02 enforces invariants at the model + DB; controller-level role gating lives in the slices.
- **No coverage tooling / SimpleCov / CI** — that is F-03 (`test-infrastructure-scaffold`). F-02 writes plain Minitest tests; F-03 later measures them.
- **No DB rename** (`bootstrap_scaffold_*` → `walkie_*`) — orthogonal; noted as a standing risk.
- **No state-machine gem (AASM/state_machine)** — hand-rolled methods, consistent with rubocop-rails-omakase.
- **No dog detail fields beyond `name`** — breed/weight/notes are deferred to S-03 (a trivial additive migration).
- **No HTTP-level concurrency test** — that's S-05's integration test. F-02 proves the invariant at the model layer.

## Implementation Approach

Build bottom-up in dependency order: `Dog` first (Walk references it), then the `walks` table with all its DB constraints (verified by raw inserts before any model behavior exists), then the `Walk` model and transition methods, then the concurrency proof and hardening. Each phase ends at a migrated, tested, bootable state. Mirror F-01's string-enum + private-validator + builder-test idioms throughout.

## Critical Implementation Details

- **Compare-and-swap transition methods.** Each transition is a single `UPDATE … WHERE id = ? AND state = <expected> [AND owner/walker guard]`. Implemented via `self.class.where(id: id, state: <expected>, <guard>).update_all(state: <next>, <timestamp>: Time.current, updated_at: Time.current)`. Affected-rows `== 1` → reload and return truthy; `== 0` → return falsy ("already moved" / not authorized). Because the guard (e.g. `accepted_by_walker_id: walker.id`, or `owner_id: owner.id`) is in the `WHERE` clause, authorization and the race guard are enforced in the same atomic write — no separate read-check-write window. `update_all` skips callbacks/validations, so `updated_at` is set explicitly and the DB `CHECK` constraints are the binding consistency backstop.
- **The `state ↔ walker` CHECK.** `accepted_by_walker_id` must be `NULL` exactly when `state IN ('requested','cancelled')` and `NOT NULL` otherwise. A single `CHECK` expresses both directions; it is what makes a buggy raw write impossible to persist in an inconsistent shape.
- **Concurrency test needs real connections.** Minitest wraps each test in a transaction by default, which serializes thread writes and hides the race. The race test must disable transactional fixtures for that test (`self.use_transactional_tests = false` on the test class, or a dedicated test class) and clean up rows manually, so the threads hit the real DB and contend on the row.
- **`owner_id` consistency.** `owner_id` is denormalized (= `dog.user_id`). Set it at creation; validate `owner_id == dog.user_id` in the model so a mismatch can't be persisted through AR.

## Phase 1: Dog model + soft-delete

### Overview

Create the `dogs` table and `Dog` model. Dogs belong to a User (the Owner) and are soft-deleted via `deactivated_at`, preserving walk history when an Owner removes a dog (resolves Open Q #4 toward soft-delete — closes none of S-10's later options).

### Changes Required:

#### 1. Migration creating `dogs`

**File**: `db/migrate/<ts>_create_dogs.rb`

**Intent**: Add the `dogs` table — the entity the marketplace orbits — owned by a User, with a soft-delete marker so removal never destroys history.

**Contract**: Columns: `name` (string, `null: false`), `user_id` (FK → `users`, `null: false`), `deactivated_at` (datetime, nullable), `timestamps`. Foreign key `dogs.user_id → users` with `on_delete: :restrict`. Index on `user_id`. Generate via `docker compose exec web bin/rails generate migration CreateDogs`, then edit to the contract above.

#### 2. `Dog` model

**File**: `app/models/dog.rb`

**Intent**: Give `Dog` its associations and an explicit active-only scope (no `default_scope`).

**Contract**: `belongs_to :user`; `has_many :walks, dependent: :restrict_with_exception` (history is never cascade-deleted); `validates :name, presence: true`; `scope :active, -> { where(deactivated_at: nil) }`; a `deactivate!`/`active?` helper pair (sets/reads `deactivated_at`). Add the inverse `has_many :dogs` on `User` (`app/models/user.rb`).

#### 3. Dog model tests

**File**: `test/models/dog_test.rb`

**Intent**: Cover the model's contract using the builder pattern from `user_test.rb`.

**Contract**: Tests for: valid dog saves; `name` required; `belongs_to :user` required; `scope :active` excludes deactivated dogs; `deactivate!` sets `deactivated_at` and flips `active?`. Use an inline `build_dog` helper that creates an Owner user.

### Success Criteria:

#### Automated Verification:

- Migration applies: `docker compose exec web bin/rails db:migrate`
- Dog model tests pass: `docker compose exec web bin/rails test test/models/dog_test.rb`
- Linting passes: `docker compose exec web bundle exec rubocop`

#### Manual Verification:

- In console, `User.owner.first` (or a freshly created Owner) can `dogs.create!(name: "Rex")`; the dog appears in `Dog.active`.
- Calling `deactivate!` removes it from `Dog.active` but the row still exists.

**Implementation Note**: After completing this phase and all automated verification passes, pause for manual confirmation before proceeding.

---

## Phase 2: Walk schema + DB invariants

### Overview

Create the `walks` table with every DB-level invariant in place — FKs, the enum-membership `CHECK`, and the `state ↔ accepted_by_walker_id` consistency `CHECK` — before any model behavior exists. Verify the constraints directly with raw inserts so the backstop is proven independent of Active Record.

### Changes Required:

#### 1. Migration creating `walks`

**File**: `db/migrate/<ts>_create_walks.rb`

**Intent**: Add the `walks` table with the linear state machine, denormalized owner scope, locality snapshot, per-transition timestamps, and all DB-level constraints that make the invariants binding outside the UI.

**Contract**: Columns:
- `dog_id` (FK → `dogs`, `null: false`, `on_delete: :restrict`)
- `owner_id` (FK → `users`, `null: false`, `on_delete: :restrict`) — denormalized `= dog.user_id`
- `accepted_by_walker_id` (FK → `users`, `null: true`, `on_delete: :restrict`)
- `state` (string, `null: false`, `default: "requested"`)
- `city` (string, `null: false`), `postcode` (string, nullable) — snapshot at creation
- `accepted_at`, `started_at`, `completed_at`, `cancelled_at` (datetime, all nullable)
- `timestamps`

Indexes: `owner_id`, `accepted_by_walker_id`, `dog_id`, and a composite `[:state, :city]` (serves S-05's open-requests-by-city filter).

`CHECK` constraints (added in the same migration via `add_check_constraint`):
- `walks_state_valid`: `state IN ('requested','accepted','in_progress','completed','cancelled')`
- `walks_walker_presence`: `(state IN ('requested','cancelled') AND accepted_by_walker_id IS NULL) OR (state IN ('accepted','in_progress','completed') AND accepted_by_walker_id IS NOT NULL)`

```ruby
add_check_constraint :walks,
  "(state IN ('requested','cancelled') AND accepted_by_walker_id IS NULL) " \
  "OR (state IN ('accepted','in_progress','completed') AND accepted_by_walker_id IS NOT NULL)",
  name: "walks_walker_presence"
```

#### 2. Constraint-level tests (raw inserts)

**File**: `test/models/walk_constraints_test.rb` (or a clearly-named section in `walk_test.rb`)

**Intent**: Prove the DB rejects inconsistent rows even when Active Record is bypassed — the Guardrail is "binding outside the UI, not advisory."

**Contract**: Using `ActiveRecord::Base.connection.execute` (or `insert_all` to skip validations), assert that: an invalid `state` value raises; an `accepted` row with `NULL accepted_by_walker_id` raises; a `requested` row with a non-null walker raises; a valid `requested` row inserts. Wrap raises in `assert_raises(ActiveRecord::StatementInvalid)`.

### Success Criteria:

#### Automated Verification:

- Migration applies: `docker compose exec web bin/rails db:migrate`
- Constraint tests pass: `docker compose exec web bin/rails test test/models/walk_constraints_test.rb`
- Schema regenerated and includes the check constraints: `docker compose exec web bin/rails db:migrate` leaves `db/schema.rb` with both `t.check_constraint` entries
- Linting passes: `docker compose exec web bundle exec rubocop`

#### Manual Verification:

- In console, a raw insert of an `accepted` walk with no walker raises `ActiveRecord::StatementInvalid`.
- `db/schema.rb` shows the `walks` table with both check constraints and the `[state, city]` index.

**Implementation Note**: After completing this phase and all automated verification passes, pause for manual confirmation before proceeding.

---

## Phase 3: Walk model + transition methods

### Overview

Add the `Walk` model: associations, enum, validations, and the four compare-and-swap transition methods (`accept!`, `start!`, `complete!`, `cancel!`) that set the matching timestamp and enforce ordering + authorization atomically in the `WHERE` clause.

### Changes Required:

#### 1. `Walk` model — associations, enum, validations

**File**: `app/models/walk.rb`

**Intent**: Give `Walk` its domain shape and the advisory AR layer that complements the DB constraints.

**Contract**:
- `belongs_to :dog`; `belongs_to :owner, class_name: "User"`; `belongs_to :accepted_by_walker, class_name: "User", optional: true`.
- `enum :state, { requested: "requested", accepted: "accepted", in_progress: "in_progress", completed: "completed", cancelled: "cancelled" }` (string-backed, mirrors `User#role`).
- Validations: presence of `state`, `city`, `dog`, `owner`; `validate :owner_matches_dog_owner` (private — `owner_id == dog.user_id`); a guard that `accepted_by_walker` is not the `owner`. Add inverse associations on `User` (`has_many :owned_walks, class_name: "Walk", foreign_key: :owner_id` and `has_many :accepted_walks, class_name: "Walk", foreign_key: :accepted_by_walker_id`).
- Optional role guards (cheap, supports the Guardrail): validate `owner` has role `owner` and, when present, `accepted_by_walker` has role `walker`.

#### 2. Transition methods

**File**: `app/models/walk.rb`

**Intent**: Implement the four lifecycle transitions as atomic compare-and-swap writes — the load-bearing mechanism for linear progression and the single-Walker accept race.

**Contract**: Four instance methods, each returning truthy on success / falsy when the transition didn't apply (wrong state or not authorized):
- `accept!(walker)` — `WHERE state = 'requested'` → `accepted`, sets `accepted_by_walker_id = walker.id`, `accepted_at`. (Guard: caller passes a Walker; the `requested` precondition also blocks self-accept indirectly, and the owner≠walker rule is validated.)
- `start!(walker)` — `WHERE state = 'accepted' AND accepted_by_walker_id = walker.id` → `in_progress`, sets `started_at`.
- `complete!(walker)` — `WHERE state = 'in_progress' AND accepted_by_walker_id = walker.id` → `completed`, sets `completed_at`.
- `cancel!(owner)` — `WHERE state = 'requested' AND owner_id = owner.id` → `cancelled`, sets `cancelled_at`. (Ships now; S-06 wires the UI.)

Each uses `self.class.where(id: id, state: <expected>, <guard>).update_all(state: <next>, <ts>: Time.current, updated_at: Time.current)`, checks `affected == 1`, and `reload`s on success. See **Critical Implementation Details**.

#### 3. Transition unit tests (single-threaded)

**File**: `test/models/walk_test.rb`

**Intent**: Cover the happy-path lifecycle and every illegal-transition rejection.

**Contract**: Inline `build_walk` helper (creates Owner + Dog + Walker). Tests: full `accept! → start! → complete!` lifecycle sets each timestamp and state; `cancel!` from `requested` works; rejections — `start!` before `accept!` returns falsy and leaves state unchanged; `complete!` before `start!` rejected; `accept!` on a non-`requested` walk rejected; `start!`/`complete!` by a Walker who isn't the bound walker rejected; `cancel!` after `accept!` rejected; `owner_matches_dog_owner` validation rejects a mismatched `owner_id`; an Owner cannot be the `accepted_by_walker`.

### Success Criteria:

#### Automated Verification:

- Walk model tests pass: `docker compose exec web bin/rails test test/models/walk_test.rb`
- Full suite passes: `docker compose exec web bin/rails test`
- Linting passes: `docker compose exec web bundle exec rubocop`

#### Manual Verification:

- In console, build an Owner+Dog+Walker, create a `requested` walk, and run `accept!`/`start!`/`complete!` in order — each succeeds and stamps its timestamp.
- Calling `start!` on a `requested` walk returns falsy and leaves `state == "requested"`.

**Implementation Note**: After completing this phase and all automated verification passes, pause for manual confirmation before proceeding.

---

## Phase 4: Concurrency invariant + hardening

### Overview

Prove the single-Walker accept invariant under real thread contention (the roadmap's "load-bearing concurrency test inside F-02"), then clear the full suite and the security/lint gates. This completes F-02.

### Changes Required:

#### 1. Multi-thread accept-race test

**File**: `test/models/walk_concurrency_test.rb`

**Intent**: Verify that when many Walkers call `accept!` on one `requested` walk simultaneously, exactly one succeeds and the row ends consistent — the PRD Guardrail's single-Walker invariant, proven at the model/DB layer before S-05's HTTP test exists.

**Contract**: A test class with `self.use_transactional_tests = false` (threads need real, separate connections — see Critical Implementation Details). Create one `requested` walk and N (e.g. 10) Walker users; spawn N threads each calling `walk.accept!(walker_i)` (use a latch/`Thread`s joined after a barrier so they contend); after joining, assert exactly one `accept!` returned truthy, the walk is `accepted` with a non-null `accepted_by_walker_id`, and the `walks_walker_presence` CHECK was never violated. Clean up created rows in `teardown` (no transactional rollback). Each thread should wrap its DB work so connections are returned to the pool.

#### 2. Final hardening pass

**File**: (no new file — verification only)

**Intent**: Ensure the whole foundation is green and clean before handing off to the slices.

**Contract**: Full `bin/rails test` green; rubocop clean; brakeman clean; bundler-audit clean; `db/schema.rb` committed at the new version.

### Success Criteria:

#### Automated Verification:

- Concurrency test passes: `docker compose exec web bin/rails test test/models/walk_concurrency_test.rb`
- Full suite passes: `docker compose exec web bin/rails test`
- Linting passes: `docker compose exec web bundle exec rubocop`
- Security scan clean: `docker compose exec web bundle exec brakeman --no-pager`
- Dependency audit clean: `docker compose exec web bundle exec bundler-audit check --update`

#### Manual Verification:

- The concurrency test is genuinely concurrent (temporarily breaking `accept!` to a non-conditional update makes the test fail with >1 winner — confirms it's a real race test, not a no-op). Revert the break.
- `db/schema.rb` reflects both tables, all FKs, and both check constraints.

**Implementation Note**: After completing this phase and all automated verification passes, pause for manual confirmation. This completes F-02.

---

## Testing Strategy

### Unit Tests:

- `Dog`: `name` required; `belongs_to :user`; `scope :active` excludes deactivated; `deactivate!` behavior.
- `Walk` validations: `owner_id == dog.user_id`; owner≠walker; presence of state/city/dog/owner; role guards.
- `Walk` transitions: full happy-path lifecycle with timestamps; every illegal transition (skip/reverse/wrong-actor) rejected.
- DB constraints (AR-bypassed raw inserts): invalid state, walker-presence mismatches rejected.

### Integration Tests:

- None in F-02 (no controllers/routes). The HTTP-level accept-race integration test is explicitly S-05's responsibility.

### Manual Testing Steps:

1. Console: create Owner → Dog → Walker; create a `requested` walk; run `accept! → start! → complete!`; confirm states + timestamps.
2. Console: attempt an illegal transition (`start!` while `requested`); confirm falsy + unchanged state.
3. Console: raw-insert an `accepted` walk with null walker; confirm `ActiveRecord::StatementInvalid`.
4. Console: `deactivate!` a dog with a walk; confirm the walk (history) survives.

## Performance Considerations

Negligible at v1 scale (PRD: small users/qps/data_volume). The `[state, city]` composite index keeps S-05's open-requests filter fast. The conditional-`UPDATE` transition path adds no extra round-trips versus a read-then-write and avoids holding explicit row locks. Free-tier Postgres cold-start (deploy-plan Risk Register) is an infra concern, not introduced here.

## Migration Notes

Two new migrations: `create_dogs`, then `create_walks` (with FKs + check constraints). They stack on F-01's schema (version `2026_05_29_132054`); no existing rows to backfill (both tables are new). `db/schema.rb` advances to the `create_walks` timestamp and must be committed. No destructive changes; dog removal is soft-delete, so no cascade is configured (FKs are `restrict`).

## References

- Roadmap item: `context/foundation/roadmap.md` §F-02 (and §S-03/S-04/S-05/S-07/S-10 for downstream consumers)
- PRD: `context/foundation/prd.md` — §Business Logic (Singleness, Locality, Immediacy), §Non-Functional (linear state machine, role separation), §Success Criteria §Guardrails, FR-009..FR-014, Open Q #4
- Change identity: `context/changes/domain-schema-walks-and-dogs/change.md`
- Prior foundation (conventions to mirror): `context/changes/auth-and-role-typing/plan.md`, `app/models/user.rb`, `test/models/user_test.rb`
- CLAUDE.md tripwires: Docker-only Rails commands; stale `bootstrap_scaffold_*` DB name

## Progress

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles. See `references/progress-format.md`.

### Phase 1: Dog model + soft-delete

#### Automated

- [x] 1.1 Migration applies: `docker compose exec web bin/rails db:migrate`
- [x] 1.2 Dog model tests pass: `docker compose exec web bin/rails test test/models/dog_test.rb`
- [x] 1.3 Linting passes: `docker compose exec web bundle exec rubocop`

#### Manual

- [x] 1.4 Console: Owner can create a dog; it appears in `Dog.active`
- [x] 1.5 Console: `deactivate!` removes it from `Dog.active` but the row persists

### Phase 2: Walk schema + DB invariants

#### Automated

- [ ] 2.1 Migration applies: `docker compose exec web bin/rails db:migrate`
- [ ] 2.2 Constraint tests pass: `docker compose exec web bin/rails test test/models/walk_constraints_test.rb`
- [ ] 2.3 Schema regenerated with both `t.check_constraint` entries
- [ ] 2.4 Linting passes: `docker compose exec web bundle exec rubocop`

#### Manual

- [ ] 2.5 Console: raw insert of `accepted` walk with no walker raises `ActiveRecord::StatementInvalid`
- [ ] 2.6 `db/schema.rb` shows both check constraints and the `[state, city]` index

### Phase 3: Walk model + transition methods

#### Automated

- [ ] 3.1 Walk model tests pass: `docker compose exec web bin/rails test test/models/walk_test.rb`
- [ ] 3.2 Full suite passes: `docker compose exec web bin/rails test`
- [ ] 3.3 Linting passes: `docker compose exec web bundle exec rubocop`

#### Manual

- [ ] 3.4 Console: `accept! → start! → complete!` in order succeeds and stamps timestamps
- [ ] 3.5 Console: `start!` on a `requested` walk returns falsy, state unchanged

### Phase 4: Concurrency invariant + hardening

#### Automated

- [ ] 4.1 Concurrency test passes: `docker compose exec web bin/rails test test/models/walk_concurrency_test.rb`
- [ ] 4.2 Full suite passes: `docker compose exec web bin/rails test`
- [ ] 4.3 Linting passes: `docker compose exec web bundle exec rubocop`
- [ ] 4.4 Security scan clean: `docker compose exec web bundle exec brakeman --no-pager`
- [ ] 4.5 Dependency audit clean: `docker compose exec web bundle exec bundler-audit check --update`

#### Manual

- [ ] 4.6 Breaking `accept!` to a non-conditional update makes the race test fail (>1 winner), then revert — confirms a real race test
- [ ] 4.7 `db/schema.rb` reflects both tables, all FKs, and both check constraints
