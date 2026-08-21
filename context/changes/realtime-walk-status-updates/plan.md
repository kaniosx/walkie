# Real-time Walk Status Updates via Turbo Streams — Implementation Plan

## Overview

Walkie's PRD locked "no real-time UI updates" as a v1 non-functional non-goal — state changes were meant to be seen on refresh, not push. `context/changes/realtime-walk-status-updates/change.md` reverses that decision: the MVP has more runway than the original 3-week budget assumed, and the team wants Owners and Walkers to see walk-state changes live, over Turbo Streams / Solid Cable (already in the Gemfile — no new infra dependency). This plan wires the actual transport, broadcasting, and view layer for four screens: the Walker's open-requests list, the active-walk screen for both roles, and the home dashboard for both roles. It changes no FR, no state machine, and no roles — purely how existing state transitions become visible without navigating away.

## Current State Analysis

**Turbo Streams / Solid Cable — gems and per-env config exist, wiring doesn't.**
`turbo-rails` (2.0.23) and `solid_cable` (4.0.0) are in the Gemfile. `config/cable.yml` has correct per-environment adapters: `async` in development, `test` in test, `solid_cable` (DB-backed, `connects_to.database.writing: cable`) in production. But:
- `/cable` is **not mounted** anywhere in `config/routes.rb`.
- No custom `ActionCable::Channel` exists beyond `app/channels/application_cable/connection.rb`, which is already customized to authenticate the connection via the session cookie (`identified_by :current_user`, looked up from `cookies.signed[:session_id]`) — real prior groundwork, unused until now.
- No broadcasts, no JS consumer setup exist anywhere in `app/`.
- Production's `cable` database has never been provisioned: no `db/cable_schema.rb`, no cable-specific migrations. `config/database.yml` only defines the 3-way `primary`/`cache`/`queue`/`cable` split for `production:` — development/test have no multi-db split (consistent with them using the `async`/`test` adapters, which don't touch a database at all).

**The CAS transition pattern is the load-bearing gotcha.**
`Walk#swap_state` (`app/models/walk.rb:77-84`) performs a single atomic `UPDATE ... WHERE id = ? AND state = <from> AND <guard>` via `update_all`, returning `true` only when exactly one row was affected. `update_all` **skips ActiveRecord callbacks**, so `after_update`/`broadcasts_to`-style macros never fire from `accept!`, `start!`, `complete!`, or `cancel!`. Broadcasting must be triggered explicitly from inside `swap_state` after a successful CAS. `test/models/walk_concurrency_test.rb` asserts exactly one thread wins simultaneous transition attempts — broadcasting must not alter that race.

**No partials exist anywhere; two views duplicate the same markup.**
`app/views/open_requests/index.html.erb`, `app/views/walks/index.html.erb`, `app/views/walker_walks/index.html.erb`, and `app/views/home/index.html.erb` all inline their card/row markup directly inside `.each` loops. `home/index.html.erb:55-71` (Walker's current-walk widget) is a near-exact duplicate of `walker_walks/index.html.erb:6-23` (same card, same Start/End buttons). `dom_id` is not used anywhere in the codebase.

**No `show` route exists for `walks` or `walker_walks`.** The "active-walk screen" for both roles is really their respective `index` action rendering a single walk (or a small list) inline — not a per-walk page. `walks/index.html.erb` additionally splits into an "Active" table (`walks_walker_presence`/`state`-scoped, not yet immutable) and a "Past" table (immutable history, out of scope per `change.md`).

**No test file exists yet for `HomeController`.** All existing system tests (`test/system/*.rb`) drive scenarios via `visit`/page navigation and assert on the resulting page — none assert on a DOM change without navigating, which is new test surface this plan must add.

### Key Discoveries:

- `app/models/walk.rb:77-84` — `swap_state`'s CAS bypasses callbacks; broadcasting is called explicitly, not via `after_update_commit`.
- `app/channels/application_cable/connection.rb:1-16` — connection auth via session cookie already works; nothing downstream consumes it yet.
- `config/environments/production.rb:87-89` — `config.hosts = [/.*\.onrender\.com\z/]` is the existing pattern to mirror for `config.action_cable.allowed_request_origins`.
- `app/helpers/application_helper.rb:2-13` — `walk_state_badge_classes(state)` is the shared badge helper; every new partial must keep using it.
- `Turbo::Broadcastable::TestHelper` (`turbo-rails` gem, `lib/turbo/broadcastable/test_helper.rb`) provides `assert_turbo_stream_broadcasts` / `assert_no_turbo_stream_broadcasts`, built on `ActionCable::TestHelper` — this is the model-level test primitive for Phase 2.
- `solid_cable` ships an install generator (`bin/rails generate solid_cable:install`) that writes `db/cable_schema.rb` **and force-overwrites `config/cable.yml`** — the existing production `polling_interval`/`message_retention` customization must be restored after running it.
- `walks/index.html.erb:16-41` (Active table) already renders its own empty-state row (`colspan="4"`) inside the `<tbody>` — the exact shape needed to make that `<tbody>` a whole-container broadcast target.

## Desired End State

An Owner watching their home dashboard or `walks#index` sees a Walker accept, start, and complete their dog's walk reflected live, with no navigation. A Walker watching the open-requests list sees a new REQUESTED walk appear, and any walk (including their own would-be target) disappear the instant another Walker accepts or the Owner cancels it. A Walker's own active-walk screen (`walker_walks#index` and the home widget) reflects ACCEPTED → IN_PROGRESS → COMPLETED live if watched from a second tab/session. None of this changes the HTTP request/response flow, the state machine, or role scoping — it is purely additive.

**Verification:** `docker compose exec web bin/rails test` passes with new model + system tests; manually, two browser windows (or two Capybara-driven sessions) demonstrate each of the three scenarios above without either window navigating.

## What We're NOT Doing

- Walk history views (`S-08`/`S-09` — the "Past" tables) — immutable state, explicitly excluded by `change.md`.
- Any change to the state machine, `swap_state`'s CAS semantics, roles, or FRs — purely additive visibility.
- A button-disable-on-broadcast UX for the accept-race edge case — the existing "already accepted" alert flow is sufficient (decided).
- A polling fallback for dropped WebSocket connections — Turbo's built-in reconnect is sufficient, consistent with the PRD's existing "no offline support" non-goal (decided).
- A dedicated same-walker-two-tabs system test for the `walker_current_walk` broadcast target — covered at the model level via `assert_turbo_stream_broadcasts`; the two system-test budget (decided) is spent on the open-requests-list and Owner-watches-Walker scenarios, which prove the cross-role value directly.
- Editing `context/foundation/roadmap.md` — `change.md` defers that to a follow-up once this plan's shape is known; out of this plan's scope.

## Implementation Approach

Broadcasting is centralized in the `Walk` model (recommended and decided): a single `after_create_commit` hook for new REQUESTED walks (regular `save`, callbacks fire normally), and explicit calls from inside `swap_state` after a successful CAS for every transition. Three streams cover all four screens:

| Stream | Key | Subscribed by |
|---|---|---|
| Locality | `["open_requests", city, postcode]` | `open_requests#index`, `home#index` (Walker branch) |
| Walker's current walk | `[walker, :current_walk]` | `walker_walks#index`, `home#index` (Walker branch) |
| Owner's active walks | `[owner, :active_walks]` | `walks#index`, `home#index` (Owner branch) |

Every screen-facing broadcast **replaces a whole, always-present container** (never appends/removes individual rows) — the container renders its own empty state when there's nothing to show. This trades a slightly larger payload for eliminating an entire class of "append-target list container doesn't exist because the empty state was rendered instead" bugs, and is trivially cheap at the PRD's stated `target_scale` (small users, low qps). One stream can carry replace actions for multiple target ids from different pages at once — a target id absent from a given subscriber's DOM is a harmless no-op, so `home#index`'s Walker branch and `open_requests#index` can share the locality stream even though each page only has one of the two targets it broadcasts to.

Broadcasting runs synchronously (`broadcast_replace_to`, not the `_later`/ActiveJob-queued variant) — deterministic for system tests, and the in-process cost (render + Solid Cable insert) is well inside the PRD's 2-second NFR at this scale.

## Critical Implementation Details

**Every broadcast target must exist in the initial server-rendered HTML, even representing an empty state.** `broadcast_replace_to` replaces an element by id; if that id was never rendered (e.g. `home/index.html.erb`'s Owner branch today renders nothing at all when `@active_walks` is empty), a later broadcast to that id is a silent no-op — the page simply never updates. Every new partial in this plan (`open_requests/_list`, `home/_owner_active_walks`, `walks/_active_table`, `walker_walks/_current_walk`) must render its wrapping element unconditionally, with the empty state as its own content, never omitting the element itself.

**`solid_cable:install` overwrites `config/cable.yml`.** Run the generator for `db/cable_schema.rb` only, then `git checkout -- config/cable.yml` (or hand-restore the diff) to keep the existing `polling_interval`/`message_retention` production settings — see Phase 5.

## Phase 1: Cable transport plumbing

### Overview

Mount the Action Cable endpoint and lock down its production origins. No channel code is needed — `turbo_stream_from` uses turbo-rails' built-in `Turbo::StreamsChannel`, and the JS side auto-connects once `@hotwired/turbo-rails` is loaded (already preloaded in `app/javascript/application.js`).

### Changes Required:

#### 1. Mount Action Cable

**File**: `config/routes.rb`

**Intent**: Make `/cable` reachable so Turbo's auto-connecting consumer can open a WebSocket.

**Contract**: Add `mount ActionCable.server => "/cable"` inside `Rails.application.routes.draw`, above `root "home#index"`.

#### 2. Restrict production WebSocket origins

**File**: `config/environments/production.rb`

**Intent**: Prevent cross-origin WebSocket connections in production, mirroring the existing `config.hosts` DNS-rebinding protection.

**Contract**: Add `config.action_cable.allowed_request_origins = [/.*\.onrender\.com\z/]` near the existing `config.hosts` block (`production.rb:87-89`).

### Success Criteria:

#### Automated Verification:

- `docker compose exec web bin/rails routes | grep cable` shows the mounted engine
- `docker compose exec web bin/rails test` still passes (no regressions)

#### Manual Verification:

- With `make start` running, sign in and open browser dev tools' Network tab (WS filter) — a WebSocket connection to `/cable` opens and stays connected

---

## Phase 2: Model-level broadcasting

### Overview

Add the broadcast triggers to `Walk` and the four partials' backing data, with full model-level test coverage. This phase is independently verifiable via `assert_turbo_stream_broadcasts` — it needs no view changes to prove correct.

### Changes Required:

#### 1. Creation broadcast

**File**: `app/models/walk.rb`

**Intent**: When an Owner creates a new REQUESTED walk (via `Walk#save`, not `swap_state`), notify the relevant locality stream and the owner's own stream.

**Contract**: `after_create_commit :broadcast_creation`. `broadcast_creation` calls the two private broadcaster methods described below (`broadcast_open_requests_locality`, `broadcast_owner_active_walks`).

#### 2. Transition broadcasts

**File**: `app/models/walk.rb`

**Intent**: After a successful CAS in `swap_state`, notify whichever streams that specific transition affects — without re-adding callback-based broadcasting (which `update_all` would skip).

**Contract**: `swap_state` calls a new private `broadcast_transition(from:)` right before its final `true` return (after `reload`). `broadcast_transition`:
- always calls `broadcast_owner_active_walks` (every transition changes the owner's active-walk view of this walk)
- calls `broadcast_open_requests_locality` only when `from == "requested"` (covers `accept!` and `cancel!` — the only transitions that add/remove a walk from the open list)
- calls `broadcast_walker_current_walk` only when `accepted_by_walker_id.present?` (covers `accept!`, `start!`, `complete!`; skipped for `cancel!`, which never has a walker)

#### 3. Broadcaster methods

**File**: `app/models/walk.rb`

**Intent**: Each broadcaster re-queries the current state fresh (not relying on possibly-stale in-memory associations) and replaces one or more whole containers.

**Contract**:
- `broadcast_open_requests_locality` — re-runs `Walk.open_in_locality(city, postcode)` (same scope the controller uses) and:
  - `broadcast_replace_to(["open_requests", city, postcode], target: "open_requests_list", partial: "open_requests/list", locals: { walks: ... })`
  - `broadcast_replace_to(["open_requests", city, postcode], target: "open_requests_count", partial: "home/open_requests_count", locals: { count: ... })`
- `broadcast_walker_current_walk` — re-queries `Walk.where(accepted_by_walker_id: accepted_by_walker_id, state: %w[accepted in_progress]).first` and calls `broadcast_replace_to([accepted_by_walker, :current_walk], target: "walker_current_walk", partial: "walker_walks/current_walk", locals: { walk: ... })`
- `broadcast_owner_active_walks` — re-queries `owner.owned_walks.active` and calls `broadcast_replace_to([owner, :active_walks], target: "owner_active_walks_home", partial: "home/owner_active_walks", locals: { walks: ... })` and `broadcast_replace_to([owner, :active_walks], target: "owner_active_walks_table", partial: "walks/active_table", locals: { walks: ... })`

These are plain private methods on `Walk` (no new concern module — the codebase doesn't extract model concerns elsewhere, and a single model doesn't warrant one), grouped under a new `# --- Broadcasting ---` comment section following the existing `# --- Transitions ---` style.

### Success Criteria:

#### Automated Verification:

- New `test/models/walk_broadcast_test.rb` passes: `assert_turbo_stream_broadcasts` fires exactly the expected target(s) for each of `create`, `accept!`, `start!`, `complete!`, `cancel!` (and asserts the ones that should stay silent, e.g. `start!` never touches the locality stream)
- `docker compose exec web bin/rails test test/models/walk_concurrency_test.rb` still passes unmodified — broadcasting doesn't affect the CAS race outcome
- `docker compose exec web bin/rails test test/models/walk_test.rb test/models/walk_constraints_test.rb` still pass
- `docker compose exec web bundle exec rubocop app/models/walk.rb` passes

#### Manual Verification:

- None — this phase is fully covered by automated model-level tests, no view surface changes yet

---

## Phase 3: Walker-facing live views

### Overview

Extract the Walker-facing partials, wire their `turbo_stream_from` subscriptions, and prove the open-requests list and the Walker's current-walk widget update live.

### Changes Required:

#### 1. Open-requests list partial

**File**: `app/views/open_requests/_list.html.erb` (new)

**Intent**: Extract the currently-inlined list markup (`open_requests/index.html.erb:4-23`) into a partial taking `walks:`, wrapped in `<div id="open_requests_list">` — including the "No open walk requests..." empty state inside the same wrapper, per Critical Implementation Details.

**Contract**: `open_requests/index.html.erb` becomes `<%= render "open_requests/list", walks: @walks %>` plus a new `<%= turbo_stream_from ["open_requests", current_user.city, current_user.postcode] %>`.

#### 2. Open-requests count partial

**File**: `app/views/home/_open_requests_count.html.erb` (new)

**Intent**: Extract the count/empty-state paragraph from `home/index.html.erb:74-78` (Walker branch, no active walk) into a partial taking `count:`, wrapped in `<div id="open_requests_count">` (the surrounding card chrome and CTA link stay in `home/index.html.erb`, unwrapped, since they never change).

**Contract**: `home/index.html.erb`'s Walker branch renders `<%= render "home/open_requests_count", count: @open_requests_count %>` in place of the current inline paragraph, and adds `<%= turbo_stream_from ["open_requests", current_user.city, current_user.postcode] %>`.

#### 3. Walker's current-walk partial

**File**: `app/views/walker_walks/_current_walk.html.erb` (new)

**Intent**: Consolidate the duplicated card markup (`walker_walks/index.html.erb:4-29` and `home/index.html.erb:55-71`) into one partial taking `walk:` (may be `nil`), wrapped in `<div id="walker_current_walk">`, rendering either the active-walk card (with Start/End buttons per state) or the "no active walk" empty state + link.

**Contract**: Both `walker_walks/index.html.erb` and `home/index.html.erb`'s Walker branch replace their inline card markup with `<%= render "walker_walks/current_walk", walk: @walk %>`, and both add `<%= turbo_stream_from [current_user, :current_walk] %>`.

### Success Criteria:

#### Automated Verification:

- `docker compose exec web bin/rails test test/integration/open_requests_test.rb test/integration/walker_walks_test.rb` still pass (extraction didn't change rendered content)
- `docker compose exec web bin/rails test test/system/walker_accepts_request_test.rb` still passes unmodified
- New `test/system/realtime_open_requests_test.rb` passes: two Walker sessions (`using_session`) in the same locality — Session A viewing `open_requests_path`, Session B accepts a walk — Session A's page loses that row without calling `visit` again
- `docker compose exec web bundle exec rubocop app/views` passes (ERB isn't rubocop's domain, but any helper/controller touch-ups are)

#### Manual Verification:

- Two browser windows signed in as different Walkers in the same city/postcode: creating a new request (as an Owner, third window) makes it appear live in both Walkers' `open_requests` windows; one Walker accepting removes it live from the other's window and updates their home dashboard's open-requests count

**Implementation Note**: After this phase's automated verification passes, pause for the manual two-window confirmation above before proceeding to Phase 4.

---

## Phase 4: Owner-facing live views

### Overview

Extract the Owner-facing partials and prove the highest-value cross-role scenario: an Owner watches a Walker's start/complete actions reflected live.

### Changes Required:

#### 1. Owner's home active-walks partial

**File**: `app/views/home/_owner_active_walks.html.erb` (new)

**Intent**: Extract `home/index.html.erb:6-19` (the "Active requests" heading + cards, currently rendered only `if @active_walks.any?`) into a partial taking `walks:`, wrapped in `<div id="owner_active_walks_home">` that renders unconditionally — heading + cards when `walks.any?`, otherwise an empty `<div>` (matching today's "render nothing" visual behavior while keeping the container present as a broadcast target).

**Contract**: `home/index.html.erb`'s Owner branch renders `<%= render "home/owner_active_walks", walks: @active_walks %>` and adds `<%= turbo_stream_from [current_user, :active_walks] %>`.

#### 2. Owner's active-walks table partial

**File**: `app/views/walks/_active_table.html.erb` (new)

**Intent**: Extract the entire Active `<tbody>` (`walks/index.html.erb:16-41`, including its existing empty-state row) into a partial taking `walks:`, rendering the `<tbody id="owner_active_walks_table">` tag itself (not just its contents) so `broadcast_replace_to` can replace it outerHTML-for-outerHTML.

**Contract**: `walks/index.html.erb` renders `<%= render "walks/active_table", walks: @active_walks %>` inside the existing `<table>`/`<thead>` wrapper (replacing the inlined `<tbody>...</tbody>`), and adds `<%= turbo_stream_from [current_user, :active_walks] %>`.

### Success Criteria:

#### Automated Verification:

- `docker compose exec web bin/rails test test/integration/walks_test.rb test/integration/walks_cancel_test.rb` still pass
- `docker compose exec web bin/rails test test/system/owner_creates_walk_request_test.rb test/system/owner_cancels_request_test.rb test/system/full_walk_lifecycle_test.rb` still pass unmodified
- New `test/system/realtime_active_walk_test.rb` passes: Owner session viewing `walks_path` (or `root_path`), Walker session (in a separate `using_session`) starts then completes the accepted walk — Owner's page reflects ACCEPTED → IN_PROGRESS → COMPLETED (and the walk leaving the Active table) without the Owner's session calling `visit` again
- New `test/controllers/home_controller_test.rb` (fills the existing coverage gap) asserts the Owner and Walker dashboard branches render their respective partials with correct data
- `docker compose exec web bundle exec brakeman --no-pager` reports no new warnings

#### Manual Verification:

- Two browser windows: Owner on their home dashboard (or `walks_path`), Walker (separate account) accepts, starts, and completes the Owner's dog's walk — the Owner's window updates through each state without reloading

**Implementation Note**: After this phase's automated verification passes, pause for the manual two-window confirmation above before proceeding to Phase 5.

---

## Phase 5: Production readiness

### Overview

Provision Solid Cable's production database so the feature actually broadcasts once deployed — without this, the app would work in dev/test (`async`/`test` adapters) and silently do nothing in production.

### Changes Required:

#### 1. Generate the cable schema

**File**: `db/cable_schema.rb` (new), `config/cable.yml` (verify unchanged)

**Intent**: Materialize the `cable` database's schema so production's `db:prepare` step can create and load it.

**Contract**: Run `docker compose exec web bin/rails generate solid_cable:install`, then run `git diff config/cable.yml` and revert it (`git checkout -- config/cable.yml`) — the generator force-overwrites the file and would silently drop the existing `polling_interval: 0.1.seconds` / `message_retention: 1.day` production tuning (see Critical Implementation Details). Only `db/cable_schema.rb` should remain as a new file.

#### 2. Verify the deploy path

**File**: none (verification only)

**Intent**: Confirm the existing `config/database.yml` production `cable:` entry (already present, `database.yml:94-106`) correctly picks up the new schema on `db:prepare`, and that Kamal's deploy hook runs `db:prepare` (it already must, for `primary`/`cache`/`queue` — confirm `cable` is included automatically since Rails 8's multi-db `db:prepare` iterates all configured databases).

### Success Criteria:

#### Automated Verification:

- `docker compose exec web bin/rails db:prepare` completes without error against a local Postgres pointed at by `DATABASE_URL`/the dev database, producing no unexpected schema diff for `primary`/`cache`/`queue` (cable's schema loads into whichever DB `cable:` in `database.yml` resolves to under the given `RAILS_ENV`)
- `git diff config/cable.yml` shows no unintended changes after the restore step

#### Manual Verification:

- After the next deploy, run a Rails console smoke test on the production host (mirroring the O-01 Sentry pattern already used for this project): `ActionCable.server.broadcast("solid_cable_smoke_test", { ok: true })` completes without raising, confirming the `solid_cable` adapter can actually reach the provisioned `cable` database
- Two real browsers against the deployed app (not Docker dev) demonstrate one of the three live-update scenarios end-to-end

---

## Testing Strategy

### Unit Tests:

- `test/models/walk_broadcast_test.rb` — one test per transition × stream combination, asserting exactly the expected `broadcast_replace_to` calls fire (and the ones that shouldn't, don't)

### Integration Tests:

- `test/controllers/home_controller_test.rb` — new file, closes the existing coverage gap for both dashboard branches
- Existing `test/integration/*.rb` files re-run unmodified to confirm partial extraction didn't change rendered output

### Manual Testing Steps:

1. Two Walker browser windows, same city/postcode: confirm open-requests list and count update live on create/accept/cancel
2. Owner + Walker browser windows: confirm the Owner's home dashboard and `walks#index` reflect the Walker's start/complete live
3. Confirm the existing "already accepted" alert still appears correctly for the losing Walker in a real double-click race

## Performance Considerations

Broadcasting runs synchronously and re-queries the DB per broadcast call (up to 5 small queries per transition, each scoped by an indexed column). At the PRD's stated `target_scale` (small users, low qps, small data volume) this is negligible against the 2-second NFR; revisit with `_later`/ActiveJob-queued broadcasts only if a future scale-up makes it measurable.

## Migration Notes

No data migration. `db/cable_schema.rb` is a new schema file for a previously-unprovisioned database — it has no existing data to migrate.

## References

- Change identity: `context/changes/realtime-walk-status-updates/change.md`
- PRD non-goal being reversed: `context/foundation/prd.md` §Non-Goals ("No real-time UI updates")
- Roadmap slices whose views this touches: S-05 (`walker-accepts-request`), S-07 (`walker-starts-and-completes-walk`), U-06 (`ui-home-and-password-polish`) — see `context/foundation/roadmap.md`
- CAS pattern: `app/models/walk.rb:77-84`
- Duplicated markup this plan consolidates: `app/views/walker_walks/index.html.erb:4-29` vs `app/views/home/index.html.erb:55-71`

## Progress

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles.

### Phase 1: Cable transport plumbing

#### Automated

- [x] 1.1 `bin/rails routes` shows the mounted `/cable` engine — 9fea8b8
- [x] 1.2 Full test suite still passes — 9fea8b8

#### Manual

- [x] 1.3 Browser dev tools show a live WebSocket connection to `/cable` after sign-in — 9fea8b8

### Phase 2: Model-level broadcasting

#### Automated

- [x] 2.1 `test/models/walk_broadcast_test.rb` passes for every transition × stream combination — 91a8869
- [x] 2.2 `test/models/walk_concurrency_test.rb` passes unmodified — 91a8869
- [x] 2.3 `test/models/walk_test.rb` and `test/models/walk_constraints_test.rb` pass — 91a8869
- [x] 2.4 `bundle exec rubocop app/models/walk.rb` passes — 91a8869

### Phase 3: Walker-facing live views

#### Automated

- [x] 3.1 `test/integration/open_requests_test.rb` and `test/integration/walker_walks_test.rb` pass — 56087b1
- [x] 3.2 `test/system/walker_accepts_request_test.rb` passes unmodified — 56087b1
- [x] 3.3 New `test/system/realtime_open_requests_test.rb` passes (dual-session live removal) — 56087b1
- [x] 3.4 `bundle exec rubocop app/views` passes — 56087b1

#### Manual

- [x] 3.5 Two-window Walker demo: create/accept/cancel reflected live in list + count — 56087b1

### Phase 4: Owner-facing live views

#### Automated

- [x] 4.1 `test/integration/walks_test.rb` and `test/integration/walks_cancel_test.rb` pass — 59ffb9e
- [x] 4.2 `test/system/owner_creates_walk_request_test.rb`, `owner_cancels_request_test.rb`, `full_walk_lifecycle_test.rb` pass unmodified — 59ffb9e
- [x] 4.3 New `test/system/realtime_active_walk_test.rb` passes (Owner watches Walker live) — 59ffb9e
- [x] 4.4 New `test/controllers/home_controller_test.rb` passes — 59ffb9e
- [x] 4.5 `bundle exec brakeman --no-pager` reports no new warnings — 59ffb9e

#### Manual

- [x] 4.6 Two-window Owner+Walker demo: full ACCEPTED→IN_PROGRESS→COMPLETED reflected live — 59ffb9e

### Phase 5: Production readiness

#### Automated

- [x] 5.1 `bin/rails db:prepare` completes cleanly with `db/cable_schema.rb` present
- [x] 5.2 `git diff config/cable.yml` shows no unintended changes after restore

#### Manual

- [ ] 5.3 Post-deploy Rails console smoke-test broadcast succeeds against the real `solid_cable` adapter
- [ ] 5.4 Real-browser end-to-end demo against the deployed app
