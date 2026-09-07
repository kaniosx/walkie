# Static Walker↔Owner Distance Display — Implementation Plan

## Overview

Show the distance between Walker and Owner (e.g. "2.3 km") on three surfaces: the Walker's open-requests list, the Walker's active-walk screen, and the Owner's active-walk screens (`/walks` table + home dashboard). Computed once per relevant page load from coordinates already captured for L-01 — no continuous tracking, no new broadcast channel.

## Current State Analysis

- `Walk#distance_km_to(other_latitude, other_longitude)` (`app/models/walk.rb:149-157`) already computes Haversine distance from `self.latitude`/`self.longitude` (the Owner's coordinates, captured once at walk creation, `walks_controller.rb:35-36`) to an arbitrary point. It is **private** and used only by `broadcast_open_requests_locality` (`walk.rb:127-142`).
- **Open-requests list** (`app/views/open_requests/_list.html.erb`): the Walker's `lat`/`lng` are already available in `OpenRequestsController#index` (`app/controllers/open_requests_controller.rb:5-6`) but are used only for `WalkerLocationCache.write` and the `Walk.open_nearby` scope — never passed to the partial.
- **Walker's active-walk screen** (`app/views/walker_walks/_current_walk.html.erb`, via `WalkerWalksController#index`): no geolocation capture exists here at all today. The Walker stops visiting the two pages that write `WalkerLocationCache` (`open_requests#index`, `home#index`) once they're mid-walk, so that cache entry goes stale within its 10-minute TTL (`app/models/walker_location_cache.rb:8`).
- **Owner's active-walk screens** (`app/views/walks/_active_table.html.erb` via `WalksController#index`; `app/views/home/_owner_active_walks.html.erb` via `HomeController#index`): no geolocation capture, and neither controller eager-loads `accepted_by_walker` (`walks_controller.rb:5` only `.includes(:dog)`; `home_controller.rb:8` same) — calling `walk.accepted_by_walker` per row today would N+1.
- The existing `walker-location` Stimulus controller (`app/javascript/controllers/walker_location_controller.js`) is generic: it reads `navigator.geolocation`, sets `lat`/`lng` on a turbo-frame's `src` (the `url` value), and is already reused across two unrelated turbo-frames (`open_requests/index.html.erb:6-7`, `home/index.html.erb` Walker branch). It needs no modification to be reused a third time.

## Desired End State

- Walker's open-requests list card shows the distance to that request's Owner.
- Walker's active-walk screen shows the distance to the Owner, appearing shortly after the walk-info card itself (not blocking the Start/End button).
- Owner's `/walks` table and home-dashboard active-walks card each show the distance to the assigned Walker, once that Walker has visited their own active-walk screen at least once since acceptance.
- Wherever either party's location is unavailable (declined permission, cache expired, no fresh capture yet), the distance element is simply absent — no placeholder, no error state.

### Key Discoveries:

- `distance_km_to` silently returns `0.0 * ...` math instead of `nil` when a coordinate is missing, because `nil.to_f == 0.0` (`walk.rb:150-153`). This was safe while the method was internal-only (both operands were always real coordinates in its one call site) but must be hardened now that it drives user-facing display.
- Turbo's frame-matching means a controller action does not need a separate response branch for a nested frame request — it can always render the same view; Turbo extracts only the matching `<turbo-frame>` from the response. This lets the Walker's active-walk view reuse the existing `walker_location_controller.js` unmodified, scoped to a small nested frame around just the distance line, while `WalkerWalksController#index` always computes `@distance_km` from whatever `lat`/`lng` params happen to be present (`nil` on first load, populated on the frame's follow-up request).
- Writing to `WalkerLocationCache` from the new capture point on the Walker's active-walk screen (Phase 3) is what keeps the Owner's read (Phase 4) reasonably fresh — the Owner-side views have no capture mechanism of their own and depend entirely on some Walker-side page having written recently.

## What We're NOT Doing

- No continuous/live-updating tracking (`watchPosition`, polling, or a new broadcast channel) — this was the explicit reframe outcome in `frame.md`.
- No map or visual position indicator — text distance only.
- No change to `Walk.open_nearby`'s radius-filter logic or `MATCH_RADIUS_KM`.
- No fresh geolocation capture for the Owner — Owner-side distance always uses the coordinates already stored on the `Walk` record from request creation.
- No placeholder/error UI when distance is unavailable — the element is simply omitted.

## Implementation Approach

Expose the existing Haversine calculation publicly and harden it against missing coordinates first, since every other phase depends on calling it safely. Then land the three UI surfaces in increasing order of mechanism novelty: the open-requests list needs no new capture (data already flows through the controller each load), the Walker's active-walk screen needs a new but pattern-consistent capture point, and the Owner's active-walk screens need only a read-side fix (eager-loading + cache read) with no client-side changes at all.

## Critical Implementation Details

### Timing & lifecycle

The Walker's active-walk screen must render its walk-info card (dog name, state badge, Start/End button) immediately and unconditionally on first load — it must not wait on, or be replaced by, the geolocation round-trip the way `open_requests/index.html.erb` gates its entire list behind location. Only the distance line itself should live inside the nested turbo-frame that `walker_location_controller.js` targets; everything else in `_current_walk.html.erb` renders from the initial server response with no dependency on `lat`/`lng` params being present.

## Phase 1: Expose and harden `Walk#distance_km_to`

### Overview

Move the Haversine method out from under `private` so controllers/views/helpers can call it, and guard it against missing coordinates so it returns `nil` instead of a nonsense number.

### Changes Required:

#### 1. `Walk#distance_km_to`

**File**: `app/models/walk.rb`

**Intent**: Make the existing Haversine calculation safely callable from outside the model, returning `nil` (not a wrong distance) when either endpoint's coordinates are missing.

**Contract**: Relocate `distance_km_to(other_latitude, other_longitude)` (currently lines 149-157) to above the `private` keyword (currently line 92), keeping its existing internal caller (`broadcast_open_requests_locality`) working unchanged. Add a guard at the top: return `nil` immediately if `latitude.nil? || longitude.nil? || other_latitude.nil? || other_longitude.nil?`, before any `.to_f` coercion.

### Success Criteria:

#### Automated Verification:

- [ ] Unit tests pass: `docker compose exec web bin/rails test test/models/walk_test.rb`
- [ ] Rubocop passes: `docker compose exec web bundle exec rubocop app/models/walk.rb`

#### Manual Verification:

- [ ] None needed — pure model-level change, covered by automated tests.

---

## Phase 2: Distance on the open-requests list

### Overview

Show each open request's distance on the Walker's list card, using the `lat`/`lng` already available in `OpenRequestsController#index`.

### Changes Required:

#### 1. `OpenRequestsController#index`

**File**: `app/controllers/open_requests_controller.rb`

**Intent**: Pass the Walker's already-parsed coordinates through to the partial so each card can compute its own distance.

**Contract**: Pass `lat:` and `lng:` as additional locals in the existing `render "open_requests/list", walks: @walks, city: current_user.city` call (line 12).

#### 2. Open-requests card partial

**File**: `app/views/open_requests/_list.html.erb`

**Intent**: Show the distance to each request's Owner alongside the existing city/time-ago line.

**Contract**: Accept new `lat:`/`lng:` locals (declared alongside the existing `walks`/`city` locals). For each `walk`, compute `walk.distance_km_to(lat, lng)`; when non-nil, render it rounded to one decimal place (e.g. `"2.3 km"`) appended to the existing city/time-ago line (line 8-10); when `nil`, render that line exactly as today.

### Success Criteria:

#### Automated Verification:

- [ ] Integration tests pass: `docker compose exec web bin/rails test test/controllers/open_requests_controller_test.rb`
- [ ] Rubocop passes: `docker compose exec web bundle exec rubocop app/controllers/open_requests_controller.rb app/views/open_requests/`

#### Manual Verification:

- [ ] Sign in as a Walker, grant location, confirm each open-request card shows a distance figure.
- [ ] Deny location (or simulate absent `lat`/`lng`) and confirm cards render as today, with no distance line and no error.

---

## Phase 3: Distance on the Walker's active-walk screen

### Overview

Add a one-shot geolocation capture scoped to a small nested turbo-frame around the distance line only, so the Start/End button and walk info render immediately and unconditionally.

### Changes Required:

#### 1. `WalkerWalksController#index`

**File**: `app/controllers/walker_walks_controller.rb`

**Intent**: Accept optional `lat`/`lng` params, write them to `WalkerLocationCache` (this is what keeps the Owner-side read in Phase 4 reasonably fresh), and compute the distance for display.

**Contract**: Parse `lat`/`lng` via the same `coerce_coordinate` helper already used in `open_requests_controller.rb`/`home_controller.rb`. When both present: `WalkerLocationCache.write(current_user, latitude: lat, longitude: lng)`, then set `@distance_km = @walk.distance_km_to(lat, lng)` if `@walk` is present. When absent, `@distance_km` stays `nil`. No change to the existing `@walk`/`@past_walks` queries.

#### 2. Walker's active-walk partial

**File**: `app/views/walker_walks/_current_walk.html.erb`

**Intent**: Render the walk-info card and Start/End button exactly as today, unconditionally; wrap only the distance line in a nested turbo-frame that requests fresh coordinates independently.

**Contract**: Inside the existing `<% if walk %>` branch (lines 3-20), add a `turbo_frame_tag "walker_current_walk_distance", data: { controller: "walker-location", walker_location_url_value: walker_walks_path }` wrapping a small block that renders `@distance_km` (rounded to one decimal, e.g. `"Owner is 2.3 km away"`) when present, and nothing when `nil`. This reuses `walker_location_controller.js` unmodified — first render has no `lat`/`lng` so the nested frame starts empty; the controller's `connect()` fires, resolves geolocation, and re-requests `walker_walks_path` with `lat`/`lng`, and Turbo swaps in just that frame's content from the (otherwise identical) response.

### Success Criteria:

#### Automated Verification:

- [ ] Integration tests pass: `docker compose exec web bin/rails test test/controllers/walker_walks_controller_test.rb`
- [ ] Rubocop passes: `docker compose exec web bundle exec rubocop app/controllers/walker_walks_controller.rb app/views/walker_walks/`

#### Manual Verification:

- [ ] Sign in as a Walker with an accepted/in-progress walk; confirm the Start/End button and walk info appear immediately, before any location prompt resolves.
- [ ] Grant location and confirm the distance line appears shortly after, without the rest of the card re-rendering or flashing.
- [ ] Deny location and confirm the card still works fully (Start/End functional), just without a distance line.

---

## Phase 4: Distance on the Owner's active-walk screens

### Overview

Read the assigned Walker's cached location (written in Phase 3) to show distance on both Owner-facing active-walk surfaces, fixing the existing N+1 gap along the way.

### Changes Required:

#### 1. `WalksController#index`

**File**: `app/controllers/walks_controller.rb`

**Intent**: Eager-load the accepted Walker so per-row distance lookups don't N+1.

**Contract**: Add `:accepted_by_walker` to the existing `.includes(:dog)` on `@active_walks` (line 5), matching the pattern already used for `@past_walks` (line 8).

#### 2. `HomeController#index` (Owner branch)

**File**: `app/controllers/home_controller.rb`

**Intent**: Same eager-load fix for the dashboard's active-walks query.

**Contract**: Add `:accepted_by_walker` to the existing `.includes(:dog)` on `@active_walks` (line 8).

#### 3. Distance-lookup helper

**File**: `app/helpers/application_helper.rb` (or a walks-specific helper if the project's convention separates them — follow whatever existing helper file `walk_state_badge_classes` lives in, since both are walk-display helpers)

**Intent**: One shared place both Owner-facing partials call to get a walk's distance to its assigned Walker, without duplicating the cache-read + nil-handling logic.

**Contract**: `distance_to_walker_km(walk)` returns `nil` if `walk.accepted_by_walker.nil?`; otherwise reads `WalkerLocationCache.read(walk.accepted_by_walker)`, returns `nil` if that's `nil`, otherwise returns `walk.distance_km_to(location[:latitude], location[:longitude])`.

#### 4. Owner active-walks table partial

**File**: `app/views/walks/_active_table.html.erb`

**Intent**: Show the distance to the assigned Walker for `accepted`/`in_progress` rows.

**Contract**: Within the existing per-row loop (lines 4-19), call `distance_to_walker_km(walk)`; when non-nil, render it rounded to one decimal (e.g. `"Walker is 2.3 km away"`) in the existing state-badge cell (line 8-10) or an adjacent cell; when `nil` (includes all `requested`-state rows, which have no walker yet), render nothing extra.

#### 5. Owner dashboard active-walks partial

**File**: `app/views/home/_owner_active_walks.html.erb`

**Intent**: Same distance display, for dashboard parity.

**Contract**: Within the existing per-walk loop (lines 5-13), call `distance_to_walker_km(walk)` the same way and render it near the existing state badge (line 11) when non-nil.

### Success Criteria:

#### Automated Verification:

- [ ] Integration tests pass: `docker compose exec web bin/rails test test/controllers/walks_controller_test.rb test/controllers/home_controller_test.rb`
- [ ] Rubocop passes: `docker compose exec web bundle exec rubocop app/controllers/walks_controller.rb app/controllers/home_controller.rb app/helpers/ app/views/walks/ app/views/home/`
- [ ] No N+1 introduced: existing `bullet` gem check (if configured) or a query-count assertion in the controller test for `@active_walks`

#### Manual Verification:

- [ ] As an Owner with an accepted/in-progress walk whose Walker has recently viewed their own active-walk screen, confirm distance shows on both `/walks` and the home dashboard.
- [ ] As an Owner whose Walker has not visited their active-walk screen since accepting (cache empty), confirm both views render normally with no distance line and no error.
- [ ] As an Owner with a still-`requested` walk (no walker yet), confirm no distance line appears for that row.

---

## Testing Strategy

### Unit Tests:

- `distance_km_to` returns `nil` when either latitude or either longitude is `nil` (four combinations: self missing lat, self missing lng, other missing lat, other missing lng).
- `distance_km_to` returns the correct known-good Haversine value for a fixed coordinate pair (regression guard, e.g. against the existing radius-match test fixtures).
- `distance_km_to` is now callable from outside the model (i.e., not raising `NoMethodError: private method`).

### Integration Tests:

- Open-requests list: with `lat`/`lng` present, the rendered card includes a distance string; without them, it renders exactly as before.
- Walker's active-walk screen: `@distance_km` is set when `lat`/`lng` params are present and the Walker has an active walk; the walk-info card and Start/End button render regardless of whether `lat`/`lng` are present.
- Owner's `/walks` and home dashboard: distance renders for an `accepted`/`in_progress` walk when `WalkerLocationCache` has an entry for `accepted_by_walker`; omitted when the cache entry is absent or expired; omitted entirely for `requested`-state rows.

### Manual Testing Steps:

1. Full happy path: Owner creates a request → Walker (with location granted) sees distance on open-requests list → Walker accepts, starts the walk, sees distance on their active-walk screen → Owner sees distance on `/walks` and the home dashboard.
2. Location-denied path: repeat with the Walker denying the location prompt at each step; confirm no errors, only absent distance lines.
3. Stale-cache path: Walker accepts a walk, waits past the 10-minute `WalkerLocationCache` TTL without revisiting their active-walk screen, confirms the Owner's views show no distance (rather than a stale/wrong one).

## Performance Considerations

`distance_to_walker_km` reads from `Rails.cache` (in-memory) per row — negligible at this project's stated `target_scale` (small users, low QPS). No new SQL queries beyond the two `.includes` fixes, which reduce query count rather than add to it.

## Migration Notes

No schema changes. No data migration — all coordinates already exist (`walks.latitude`/`longitude`) or are ephemeral (`WalkerLocationCache`).

## References

- Related frame: `context/changes/walker-owner-distance-display/frame.md`
- `app/models/walk.rb:149-157` (`distance_km_to`, to be made public + hardened)
- `app/models/walker_location_cache.rb` (`write`/`read`/`key_for`)
- `app/controllers/open_requests_controller.rb:4-13`, `app/views/open_requests/_list.html.erb`
- `app/controllers/walker_walks_controller.rb:4-13`, `app/views/walker_walks/_current_walk.html.erb`
- `app/controllers/walks_controller.rb:4-11`, `app/views/walks/_active_table.html.erb`
- `app/controllers/home_controller.rb:1-22`, `app/views/home/_owner_active_walks.html.erb`
- `app/javascript/controllers/walker_location_controller.js` (reused unmodified)

## Progress

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles. See `references/progress-format.md`.

### Phase 1: Expose and harden `Walk#distance_km_to`

#### Automated

- [x] 1.1 Unit tests pass: `docker compose exec web bin/rails test test/models/walk_test.rb` — 7246852
- [x] 1.2 Rubocop passes: `docker compose exec web bundle exec rubocop app/models/walk.rb` — 7246852

### Phase 2: Distance on the open-requests list

#### Automated

- [x] 2.1 Integration tests pass: `docker compose exec web bin/rails test test/controllers/open_requests_controller_test.rb` — c88020a
- [x] 2.2 Rubocop passes: `docker compose exec web bundle exec rubocop app/controllers/open_requests_controller.rb app/views/open_requests/` — c88020a

#### Manual

- [x] 2.3 Sign in as a Walker, grant location, confirm each open-request card shows a distance figure.
- [x] 2.4 Deny location and confirm cards render as today, with no distance line and no error.

### Phase 3: Distance on the Walker's active-walk screen

#### Automated

- [x] 3.1 Integration tests pass: `docker compose exec web bin/rails test test/controllers/walker_walks_controller_test.rb` — 0ee3251
- [x] 3.2 Rubocop passes: `docker compose exec web bundle exec rubocop app/controllers/walker_walks_controller.rb app/views/walker_walks/` — 0ee3251

#### Manual

- [x] 3.3 Confirm Start/End button and walk info appear immediately, before any location prompt resolves. — 0ee3251
- [x] 3.4 Grant location and confirm the distance line appears shortly after, without the rest of the card re-rendering or flashing. — 0ee3251
- [x] 3.5 Deny location and confirm the card still works fully, just without a distance line. — 0ee3251

### Phase 4: Distance on the Owner's active-walk screens

#### Automated

- [x] 4.1 Integration tests pass: `docker compose exec web bin/rails test test/controllers/walks_controller_test.rb test/controllers/home_controller_test.rb` — ff4fd4a
- [x] 4.2 Rubocop passes: `docker compose exec web bundle exec rubocop app/controllers/walks_controller.rb app/controllers/home_controller.rb app/helpers/ app/views/walks/ app/views/home/` — ff4fd4a
- [x] 4.3 No N+1 introduced on `@active_walks` — ff4fd4a

#### Manual

- [x] 4.4 Owner with a Walker who recently viewed their active-walk screen sees distance on both `/walks` and the home dashboard. — ff4fd4a
- [x] 4.5 Owner whose Walker hasn't visited their active-walk screen (cache empty) sees both views render normally with no distance line. — ff4fd4a
- [x] 4.6 Owner with a still-`requested` walk sees no distance line for that row. — ff4fd4a
