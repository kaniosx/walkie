# Geolocation-Radius Walker↔Owner Matching Implementation Plan

## Overview

Replace `Walk.open_in_locality`'s exact city+postcode string match with a
radius-based match using live browser-captured coordinates. Filtering only
(no distance sort), city retained as a coarse pre-filter, no fallback for
users who deny/lack location, and R-01's realtime broadcast re-targeted from
a shared city-keyed channel to a per-Walker channel. `postcode` is removed
entirely (`users` + `walks`) since it stops being used anywhere once radius
matching lands.

## Current State Analysis

- `Walk.open_in_locality(city, postcode)` (`app/models/walk.rb:23`) does exact
  `WHERE city: city, postcode: postcode`, backed by the `["state", "city"]`
  index (`db/schema.rb:66`); postcode is "a cheap residual filter"
  (`walk.rb:22`) — it never has its own index.
- `walks.city`/`walks.postcode` are a one-time snapshot taken at creation
  (`app/controllers/walks_controller.rb:32`), not a live reference to the
  owner's profile — editing a profile after a request exists doesn't update
  the request's locality.
- `open_in_locality` is called from three places: `OpenRequestsController#index`
  (`open_requests_controller.rb:5`), `HomeController#index`'s walker branch
  (`home_controller.rb:14`, count only), and
  `Walk#broadcast_open_requests_locality` (`walk.rb:108-116`), which also uses
  `[city, postcode]` as the Turbo Stream channel key (`walk.rb:110,113`) —
  R-01's realtime layer keys directly off these two strings.
- No geo infra exists anywhere: no gems (`geocoder`, `rgeo`, `activerecord-postgis-adapter`),
  no DB extensions beyond `pg_catalog.plpgsql` (`db/schema.rb:15`), no lat/lng
  columns. `cube`/`earthdistance` are stock Postgres 17 contrib extensions —
  enable via a plain migration, no new gem.
- `Rails.cache` is never used anywhere in the app (`grep` returns zero hits).
  Solid Cache is in the `Gemfile` but not actually wired: dev uses
  `:memory_store`, test uses `:null_store`, production has `cache_store`
  commented out (falls back to Rails' file-store default) and
  `db/cache_migrate/` doesn't exist. `config/puma.rb` defaults
  `WEB_CONCURRENCY` to 1 (single process) — see Key Discoveries.
- No Stimulus controller in `app/javascript/controllers/` calls `fetch`,
  touches a browser API, or reads the CSRF meta tag — `flash_controller.js`
  and `nav_controller.js` are the only two, both pure-DOM. `csrf_meta_tags`
  is present in the layout (`app/views/layouts/application.html.erb:9`) but
  nothing in JS reads it yet.
- Solid Cable in production is DB-backed and **polling-based**
  (`config/cable.yml`: `polling_interval: 0.1.seconds`, `message_retention: 1.day`) —
  every `broadcast_replace_to` call writes a row to the `cable` database.
  Fan-out cost scales with write volume, not subscriber count.
- R-01 set no custom `ActionCable::Channel` — `turbo_stream_from` uses
  turbo-rails' built-in `Turbo::StreamsChannel` with array-based stream keys
  (`[record, :symbol]`, e.g. `[current_user, :active_walks]`,
  `home/index.html.erb:6`). A per-Walker channel needs no new channel class,
  just a new array key following this same convention.
- No test in this repo stubs `navigator.geolocation` or any browser
  permission — this is new test infrastructure.

### Key Discoveries:

- **Solid Cache isn't actually active** despite `CLAUDE.md` listing it as a
  live part of the stack (`Gemfile:29` present, but no `cache_store` line
  activates it, no `db/cache_migrate/`). Fully activating it would mean
  provisioning a new database — the same class of infra work R-01's Phase 5
  spent on the `cable` database — disproportionate for ~10-minute-TTL
  ephemeral data. `config/puma.rb` confirms `WEB_CONCURRENCY` defaults to 1
  (single Puma process, no `workers` line beyond the `ENV.fetch` default), so
  a single in-process `:memory_store` cache is correctness-safe today. This
  plan configures `:memory_store` explicitly across all three environments
  instead of activating Solid Cache — see **Critical Implementation Details**.
- **`walks.postcode` is never rendered in any view** — `open_requests/_list.html.erb`
  only shows `walk.city` (`_list.html.erb:9`). Removing it has zero view-layer
  blast radius on the Walk side; the Owner-profile side (`profiles/show.html.erb:22-23`,
  `edit.html.erb:24-25`, `registrations/new.html.erb:32-33`) does render/collect it
  and needs explicit field removal.
- **This diverges from PRD FR-005**, which explicitly names "display name,
  city / postcode" as the profile field set. This plan does not edit
  `context/foundation/prd.md` — that requires a separate `/10x-prd` run — but
  the divergence is called out here and in the plan brief so it's visible
  before implementation starts.
- **The frame brief's flagged tension resolved cleanly**: the "filter only, no
  sort" decision (locked during questioning) means this plan does **not**
  need to touch the separate "no proximity ranking" PRD non-goal — only Open
  Q#6 (geolocation matching itself) is being addressed. Display order stays
  `created_at: :asc` (FIFO), unchanged from today.
- **Owner-side and Walker-side coordinates are architecturally asymmetric,
  by design**: the Owner's coordinates are captured live and snapshotted
  permanently onto the `Walk` record at creation (mirrors today's
  city/postcode snapshot pattern exactly — just swap the source from the
  profile field to a live geolocation read). The Walker's coordinates are
  *never* persisted anywhere durable — captured fresh per page view, used to
  filter that request's query, and written only to a short-TTL cache for
  broadcast targeting. No `latitude`/`longitude` columns are added to `users`.
- **Turbo Frame self-referencing src is sufficient — no new routes needed.**
  Both the open-requests list and the home-dashboard count already render
  from actions that can accept optional `lat`/`lng` params; pointing a
  wrapping `<turbo-frame>`'s `src` back at the *same* URL (with coordinates
  appended once JS resolves them) lets Turbo extract the matching frame ID
  from the full-page response — the standard Hotwire pattern for a
  lazily-populated fragment with zero dedicated partial-only endpoints.

## Desired End State

A Walker sees REQUESTED walks within `Walk::MATCH_RADIUS_KM` (10km) of their
current browser-reported position, pre-filtered to their profile's city, with
live Turbo Stream updates delivered to exactly the Walkers currently in range
of a new/changed request. An Owner's walk request is created with a live
coordinate snapshot; if either party denies/lacks browser geolocation, they
see an explicit "location required" state with no fallback to the old
exact-match behavior. `postcode` no longer exists anywhere in the schema,
models, or forms.

Verifiable by: `Walk.open_nearby` unit tests pass; system tests demonstrate a
Walker inside the radius sees a request and one outside does not; a live
two-session system test shows a new request reaching only the in-radius
Walker's already-open tab; `bin/rails db:migrate` runs clean on a fresh DB.

## What We're NOT Doing

- No distance-based sort/ranking — list order stays `created_at: :asc`
  (locked decision; keeps this plan clear of the separate "no proximity
  ranking" non-goal).
- No configurable per-Walker radius — one fixed constant (`10km`) for all
  Walkers.
- No fallback to exact city/postcode matching for a user without granted
  location — a denial/unavailable result means "location required," not a
  degraded-but-working experience.
- No coordinates persisted on `User` — only `Walk` gets `latitude`/`longitude`,
  snapshotted once at creation.
- No PostGIS, no new geocoding gem/API — `cube`/`earthdistance` (stock
  Postgres contrib) + browser `navigator.geolocation`.
- No backfill of historical (already-completed/cancelled) `Walk` rows —
  `latitude`/`longitude` stay `NULL` for rows created before this ships; only
  `REQUESTED` walks are ever matched, and none of those predate this change.
- No map UI, no visual radius indicator — filter/list only, per PRD's
  existing "no map" non-goal language, left untouched.
- No PRD text edit — the FR-005 divergence (postcode removal) and Open Q#6
  resolution are documented here, not written back into `prd.md`.

## Implementation Approach

Five phases, ordered to keep risk isolated: postcode removal first (pure
cleanup, zero geolocation logic, validates the removal doesn't break anything
before new complexity lands on top); then the DB/model foundation; then the
two capture surfaces (Owner creation, Walker query) each behind their own
manual-verification checkpoint since both need a real browser to test
meaningfully; then the broadcast redesign last, since it depends on every
prior phase (coordinates must exist on `Walk` and be query-able before
broadcast targeting can use them).

## Critical Implementation Details

**Cache store activation.** `Rails.cache` has never been used in this app.
This plan sets `config.cache_store = :memory_store` explicitly in
`config/environments/development.rb` (already the default, make it explicit),
`test.rb` (currently `:null_store`, which no-ops all cache calls — must change
or the location-cache logic is untestable), and `production.rb` (currently
commented out, falls back to file-store). This is a deliberate deviation from
"reuse Solid Cache" — Solid Cache isn't actually wired up (see Key
Discoveries), and activating it would require provisioning a new database for
data that expires in 10 minutes. `:memory_store` is correctness-safe only
because `config/puma.rb` defaults to a single worker process
(`WEB_CONCURRENCY` unset). **If production is ever scaled to more than one
Puma worker, this cache silently stops working for cross-process broadcast
targeting** (each process has its own memory) — flagged here so it isn't
rediscovered as a mystery bug later.

**CSRF for the new fetch/frame requests.** Turbo's automatic CSRF handling
covers `form_with`/`button_to`/`link_to` submissions and Turbo Frame
navigations (setting a frame's `src` attribute triggers a standard
Turbo-managed GET, which already carries CSRF context) — since every new
network call in this plan is either a GET (frame `src`) or a standard Rails
form POST (Owner's walk-creation form, still `form_with`), **no manual fetch +
manual CSRF header handling is needed anywhere in this plan.** This was a false
concern raised during research; confirmed no `fetch()` call is actually
required by the chosen design.

**`earth_distance`/`ll_to_earth` return meters**, not kilometers —
`Walk::MATCH_RADIUS_KM * 1000` in the scope's SQL. `earthdistance` depends on
`cube` and must be enabled after it in the same migration.

**`swap_state` bypasses AR callbacks** (`walk.rb:80-88`, uses `update_all`) —
any per-Walker broadcast triggered by a state transition must be called
explicitly from `broadcast_transition`/`broadcast_creation`, exactly as R-01
already does; this plan adds no new callback-based broadcast triggers.

**Geolocation permission in system tests has no precedent in this repo.**
Selenium's default Chrome profile blocks the geolocation permission prompt
(auto-denies), which is actually useful for testing the "denied" path for
free — but the "granted, at specific coordinates" path needs Chrome launched
with `prefs: { "profile.default_content_setting_values.geolocation" => 1 }`
(auto-grant) plus a CDP `Page.setGeolocationOverride` call (via Selenium's
`execute_cdp` bridge) to set a fixed lat/lng before the page loads. This is
new `test/application_system_test_case.rb` configuration, added in Phase 3.

## Phase 1: Postcode removal

### Overview

Remove `postcode` from `users` and `walks` — columns, validations,
`normalizes`, form fields, view rendering, and every test fixture that seeds
it. Pure cleanup, no geolocation logic yet; validates removal doesn't break
anything before radius-matching complexity lands on top.

### Changes Required:

#### 1. Migration — drop `postcode` columns

**File**: `db/migrate/*_remove_postcode_from_users_and_walks.rb`

**Intent**: Drop the now-unused `postcode` column from both tables in one
migration.

**Contract**: `remove_column :users, :postcode, :string, null: false` and
`remove_column :walks, :postcode, :string` (reversible form, matching column
types/nullability currently in `db/schema.rb:44,59`).

#### 2. `User` model

**File**: `app/models/user.rb`

**Intent**: Remove all postcode-related validation/normalization.

**Contract**: Delete `normalizes :postcode, ...` (`user.rb:16`) and
`validates :postcode, presence: true, length: { maximum: 100 }` (`user.rb:22`).

#### 3. `Walk` model

**File**: `app/models/walk.rb`

**Intent**: Remove postcode validation and the postcode parameter from
`open_in_locality` (which Phase 2 will replace entirely, but strip postcode
now so Phase 1 is independently correct).

**Contract**: Delete `validates :postcode, presence: true` (`walk.rb:27`).
Change `open_in_locality`'s signature to `->(city) { requested.where(city: city) }`
(postcode dropped, city-only) as an interim step — Phase 2 replaces this scope
entirely with `open_nearby`.

#### 4. Controllers — drop postcode from permitted params and denormalization

**Files**: `app/controllers/registrations_controller.rb`,
`app/controllers/profiles_controller.rb`, `app/controllers/walks_controller.rb`,
`app/controllers/open_requests_controller.rb`, `app/controllers/home_controller.rb`

**Intent**: Remove `:postcode` from every `permit`/query call site.

**Contract**: `registration_params` drops `:postcode` (`registrations_controller.rb:25`);
`profile_params` drops `:postcode` (`profiles_controller.rb:23`);
`WalksController#create`'s denormalization drops `postcode: current_user.postcode`
(`walks_controller.rb:32`); `OpenRequestsController#index` and
`HomeController#index` drop the postcode argument from `open_in_locality`
(`open_requests_controller.rb:5`, `home_controller.rb:14`).

#### 5. Views — remove postcode fields/display

**Files**: `app/views/registrations/new.html.erb`, `app/views/profiles/edit.html.erb`,
`app/views/profiles/show.html.erb`

**Intent**: Remove the postcode form field / display row from all three views.

**Contract**: Delete the `<div class="mb-4">...postcode...</div>` block in
each of `registrations/new.html.erb:31-34`, `profiles/edit.html.erb:23-26`,
and the `<dt>`/`<dd>` pair in `profiles/show.html.erb:21-24`.

#### 6. Turbo Stream channel keys — drop postcode

**Files**: `app/models/walk.rb`, `app/views/home/index.html.erb`,
`app/views/open_requests/index.html.erb`

**Intent**: Every `["open_requests", city, postcode]` stream key becomes
`["open_requests", city]` as an interim step (Phase 5 replaces this scheme
entirely with a per-Walker key).

**Contract**: `walk.rb:110,113`, `home/index.html.erb:45`,
`open_requests/index.html.erb:1` — drop the third array element.

#### 7. Tests — strip postcode from fixtures/assertions

**Files**: `test/models/walk_test.rb`, `test/models/user_test.rb`,
`test/integration/open_requests_test.rb`, `test/integration/registration_test.rb`,
`test/integration/profiles_test.rb`, and any other test seeding
`postcode:`/`"30-001"` (grep confirms this exact fixture value is used
uniformly across the suite).

**Intent**: Remove every `postcode:` keyword argument from test setup, delete
postcode-specific assertions (e.g. `walk_test.rb:110-114`'s "postcode is
required" test, `user_test.rb:71-75`, the `other_postcode`/`other_pc` walk
fixtures and their exclusion assertions in `walk_test.rb:143-156` and
`open_requests_test.rb:12-37`, which Phase 2 replaces with radius-based
fixtures anyway).

### Success Criteria:

#### Automated Verification:

- Migration applies cleanly: `docker compose exec web bin/rails db:migrate`
- Full test suite passes: `docker compose exec web bin/rails test`
- Linting passes: `docker compose exec web bundle exec rubocop`

#### Manual Verification:

- Sign up a new user — no postcode field appears on the form.
- Edit an existing profile — no postcode field appears; save succeeds.
- View a profile — no postcode row appears.

**Implementation Note**: Pause here for manual confirmation before proceeding
to Phase 2.

---

## Phase 2: Schema & radius query foundation

### Overview

Enable `cube`/`earthdistance`, add `walks.latitude`/`longitude`, replace
`open_in_locality` with `Walk.open_nearby`, and wire the Owner's live
coordinates into `WalksController#create`. No UI/JS yet — this phase proves
the query layer works via model tests and a `rails console` check.

### Changes Required:

#### 1. Migration — enable extensions

**File**: `db/migrate/*_enable_cube_and_earthdistance.rb`

**Intent**: Enable the two stock Postgres contrib extensions this feature's
distance queries depend on.

**Contract**: `enable_extension "cube"` then `enable_extension "earthdistance"`
(order matters — earthdistance depends on cube).

#### 2. Migration — add coordinates to `walks`

**File**: `db/migrate/*_add_coordinates_to_walks.rb`

**Intent**: Add nullable lat/lng columns (nullable at the DB level, like
`postcode` was — required at the model level for new rows, but no backfill
needed since only `REQUESTED` walks are ever queried and none predate this
change) plus a partial GiST index for the radius query.

**Contract**: `add_column :walks, :latitude, :float`; `add_column :walks, :longitude, :float`;
`add_index :walks, "ll_to_earth(latitude, longitude)", using: :gist, where: "latitude IS NOT NULL AND longitude IS NOT NULL", name: "index_walks_on_earth_coordinates"`.

#### 3. `Walk` model — `open_nearby` scope + validations

**File**: `app/models/walk.rb`

**Intent**: Replace `open_in_locality` with a radius-aware scope; require
coordinates on new records.

**Contract**:
```ruby
MATCH_RADIUS_KM = 10

validates :latitude, :longitude, presence: true

scope :open_nearby, ->(city:, latitude:, longitude:) {
  requested
    .where(city: city)
    .where.not(latitude: nil, longitude: nil)
    .where(
      "earth_distance(ll_to_earth(latitude, longitude), ll_to_earth(?, ?)) <= ?",
      latitude, longitude, MATCH_RADIUS_KM * 1000
    )
}
```
City stays a coarse pre-filter (reuses the existing `["state", "city"]` index
before the distance check runs) — the locked "keep city as pre-filter"
decision. Since `open_in_locality` is replaced outright, update
`broadcast_open_requests_locality`'s call site in this same phase to call
`open_nearby` with the walk's own `city`/`latitude`/`longitude` (its own
values, not a subscriber's) — this keeps the method compiling. Phase 5 changes
*who* it broadcasts to (per-Walker fan-out), not the query used to build one
recipient's list, which is settled here.

#### 4. `WalksController#create` — Owner coordinate snapshot

**File**: `app/controllers/walks_controller.rb`

**Intent**: Accept and snapshot the Owner's live-captured coordinates onto
the new `Walk` (Phase 3 adds the JS that actually populates these params;
this phase makes the controller/model ready for them).

**Contract**: `create` reads `params[:latitude]`/`params[:longitude]` and
passes them into `dog.walks.new(...)` alongside the existing `city:` argument;
`walk.save` failure (e.g. missing coordinates) still surfaces via the existing
`walk.errors.full_messages.to_sentence` flash pattern (`walks_controller.rb:37`) —
no new error-handling code needed, the existing pattern already covers it.

### Success Criteria:

#### Automated Verification:

- Migrations apply cleanly: `docker compose exec web bin/rails db:migrate`
- Model tests pass: `docker compose exec web bin/rails test test/models/walk_test.rb`
- Full suite passes: `docker compose exec web bin/rails test`
- Linting passes: `docker compose exec web bundle exec rubocop`

#### Manual Verification:

- In `bin/rails console`: create two `Walk` rows ~2km apart and one ~50km
  away (same city); confirm `Walk.open_nearby(city: ..., latitude: ..., longitude: ...)`
  returns the two nearby rows and excludes the far one.

**Implementation Note**: Pause here for manual confirmation before proceeding
to Phase 3.

---

## Phase 3: Owner-side location capture

### Overview

The walk-request form on the home dashboard captures the Owner's browser
geolocation before allowing submission; denial/unavailability blocks
submission with a clear message, both client-side (JS) and server-side
(model validation, defense in depth).

### Changes Required:

#### 1. Stimulus controller — `owner_location_controller.js`

**File**: `app/javascript/controllers/owner_location_controller.js`

**Intent**: On connect, request geolocation; on success, populate hidden
lat/lng fields and enable the submit button; on error/denial, replace the
button with an inline message and leave the form unsubmittable.

**Contract**: Targets: `latitude`, `longitude` (hidden fields), `submit`
(the submit button, `disabled` by default in the view). Uses
`navigator.geolocation.getCurrentPosition(success, error)` — no options
object needed beyond defaults at this scale. `pin_all_from "app/javascript/controllers"`
(`config/importmap.rb`) auto-pins this file; `controllers/index.js`'s
`eagerLoadControllersFrom` auto-registers it — no manual registration step.

#### 2. `home/index.html.erb` — per-dog form becomes geolocation-gated

**File**: `app/views/home/index.html.erb`

**Intent**: Convert each dog's `button_to "Walk my dog", ...` (`home/index.html.erb:22-24`)
into a `form_with` carrying the new Stimulus controller, hidden coordinate
fields, and a submit button that starts `disabled`.

**Contract**: `form_with url: walks_path, data: { controller: "owner-location" }`;
hidden fields for `dog_id`, `latitude` (target), `longitude` (target); submit
button as the `submit` target, `disabled: true` in markup (JS enables it on
success).

### Success Criteria:

#### Automated Verification:

- Controller test covers create with coordinates present (succeeds) and
  absent (fails with a validation error, matching the existing
  `walk.errors.full_messages.to_sentence` flash contract):
  `docker compose exec web bin/rails test test/controllers/walks_controller_test.rb`
  (or `test/integration/` if that's where walk-creation is currently tested —
  confirm during implementation)
- Full suite passes: `docker compose exec web bin/rails test`

#### Manual Verification:

- In a real browser, click "Walk my dog": grant location → button was
  disabled, becomes enabled, submission succeeds and the new request has
  coordinates in the DB.
- Deny location (or test in a browser/profile with geolocation blocked): the
  button stays disabled and an inline message explains why.

**Implementation Note**: Pause here for manual confirmation before proceeding
to Phase 4.

---

## Phase 4: Walker-side radius-aware list

### Overview

`open_requests#index` and the home dashboard's open-requests count become
geolocation-aware via a self-referencing Turbo Frame: the frame loads with a
placeholder, a Stimulus controller resolves the Walker's coordinates and sets
the frame's `src` back to the same URL with `lat`/`lng` params, and Turbo
extracts the now-populated frame from the response.

### Changes Required:

#### 1. Stimulus controller — `walker_location_controller.js`

**File**: `app/javascript/controllers/walker_location_controller.js`

**Intent**: On connect, request geolocation; on success, set `this.element.src`
to the controller's configured URL with `lat`/`lng` query params appended; on
error/denial, replace the frame's placeholder content with a "location
required, no results without it" message (no fallback list).

**Contract**: Value: `url` (the base path to re-request, e.g.
`open_requests_path`). No target elements needed — the controller's own
`element` *is* the `<turbo-frame>`.

#### 2. `open_requests/index.html.erb` — wrap list in a self-referencing frame

**File**: `app/views/open_requests/index.html.erb`

**Intent**: Replace the plain `render "open_requests/list", ...` with a
`<turbo-frame>` carrying the new controller, pointed at `open_requests_path`
itself.

**Contract**: `<turbo-frame id="open_requests_frame" data-controller="walker-location" data-walker-location-url-value="<%= open_requests_path %>">` wrapping a placeholder ("Getting your location…"); `OpenRequestsController#index`
renders the real list *inside* the same frame ID once `params[:lat]`/`params[:lng]`
are present.

#### 3. `OpenRequestsController#index` — accept coordinates, call `open_nearby`

**File**: `app/controllers/open_requests_controller.rb`

**Intent**: When `lat`/`lng` params are present, filter via `Walk.open_nearby`;
when absent (the frame's initial placeholder-serving request, if it's ever
hit directly), render the "getting your location" state instead of a list.

**Contract**: `@walks = Walk.open_nearby(city: current_user.city, latitude: params[:lat], longitude: params[:lng]).includes(:dog).order(created_at: :asc)` — order unchanged (locked "no sort" decision).

#### 4. `home/index.html.erb` + `HomeController#index` — same pattern for the count

**Files**: `app/views/home/index.html.erb`, `app/controllers/home_controller.rb`

**Intent**: Wrap the walker branch's open-requests-count block
(`home/index.html.erb:49-53`) in its own self-referencing turbo-frame
(pointed at `root_path`), following the identical pattern from #1-#3 above.

**Contract**: `@open_requests_count` only computed when `params[:lat]`/`params[:lng]`
present (`home_controller.rb:14`); frame id e.g. `open_requests_count_frame`.

### Success Criteria:

#### Automated Verification:

- Controller tests cover: request with coordinates → filtered results;
  request without → placeholder state:
  `docker compose exec web bin/rails test test/integration/open_requests_test.rb`
- System test (new `test/application_system_test_case.rb` Chrome geolocation
  config from **Critical Implementation Details**): a Walker positioned within
  10km of a request sees it; a Walker positioned beyond 10km does not:
  `docker compose exec web bin/rails test:system`
- Full suite passes: `docker compose exec web bin/rails test`

#### Manual Verification:

- In a real browser, visit the open-requests page: see "Getting your
  location…" briefly, then the radius-filtered list.
- Deny location: see the "location required" message, no list, no crash.
- Home dashboard count badge shows the same behavior.

**Implementation Note**: Pause here for manual confirmation before proceeding
to Phase 5.

---

## Phase 5: Live per-Walker broadcast

### Overview

Activate `:memory_store` caching, write each Walker's coordinates to it on
every radius-aware request (Phase 4's params), and redesign the realtime
broadcast to push to a per-Walker channel computed from that cache, replacing
the shared city-keyed channel entirely.

### Changes Required:

#### 1. Cache store configuration

**Files**: `config/environments/development.rb`, `config/environments/test.rb`,
`config/environments/production.rb`

**Intent**: Make `:memory_store` explicit everywhere (see **Critical
Implementation Details** for the full rationale/caveat).

**Contract**: `config.cache_store = :memory_store` in all three files
(`test.rb` changes from `:null_store`; `production.rb`'s commented-out
`mem_cache_store` line is replaced, not just uncommented — that line names a
different store).

#### 2. `OpenRequestsController#index` / `HomeController#index` — cache the Walker's location

**Files**: `app/controllers/open_requests_controller.rb`, `app/controllers/home_controller.rb`

**Intent**: When `lat`/`lng` params are present (Phase 4), also write them to
`Rails.cache` keyed by the Walker's id, so broadcast-time radius checks can
find them later.

**Contract**: `Rails.cache.write("walker_location:#{current_user.id}", { latitude: params[:lat].to_f, longitude: params[:lng].to_f }, expires_in: 10.minutes)`.

#### 3. `Walk` model — per-Walker broadcast targeting

**File**: `app/models/walk.rb`

**Intent**: Replace `broadcast_open_requests_locality`'s single city-keyed
broadcast with a fan-out: find every Walker with a live cache entry within
radius of this walk, and broadcast individually to each one's channel.

**Contract**: New private method queries `User.walker` scoped to the walk's
`city`, reads each candidate's cached location (skip if absent/expired —
"not currently viewing, no live push needed" is expected, not an error),
computes distance in Ruby (no new SQL needed — this is a small, bounded
in-memory set of same-city Walkers, not a table scan), and calls
`broadcast_replace_to([walker, :nearby_open_requests], target: "open_requests_list", partial: "open_requests/list", locals: { walks: Walk.open_nearby(city: walk.city, latitude: walker_lat, longitude: walker_lng), city: walk.city })`
once per in-radius Walker. This mirrors R-01's per-entity array-key
convention (`[record, :symbol]`) exactly — no new `ActionCable::Channel` class.

#### 4. Views — subscribe to the per-Walker channel

**Files**: `app/views/open_requests/index.html.erb`, `app/views/home/index.html.erb`

**Intent**: Replace `turbo_stream_from ["open_requests", current_user.city]`
(Phase 1's interim postcode-less key) with `turbo_stream_from [current_user, :nearby_open_requests]`.

**Contract**: `open_requests/index.html.erb:1`, `home/index.html.erb:45`.

### Success Criteria:

#### Automated Verification:

- Model broadcast test (`assert_turbo_stream_broadcasts`, following the
  existing pattern in `test/models/walk_broadcast_test.rb`) confirms a new
  walk in a Walker's radius triggers a broadcast to that Walker's channel, and
  a same-city-but-out-of-radius Walker's channel receives nothing:
  `docker compose exec web bin/rails test test/models/walk_broadcast_test.rb`
- System test extends the existing two-session pattern (`using_session`, per
  `test/system/realtime_open_requests_test.rb`): Walker A (in radius) has the
  open-requests page open; Owner creates a request in another session; Walker
  A's already-open tab updates without a revisit; Walker B (same city, out of
  radius) does not see it appear:
  `docker compose exec web bin/rails test:system`
- Full suite passes: `docker compose exec web bin/rails test`

#### Manual Verification:

- Two real browser sessions (or profiles) as two Walkers at different
  simulated positions in the same city; a new request from a third
  Owner session appears live only in the in-radius Walker's tab.

**Implementation Note**: This completes the geolocation-matching change.

---

## Testing Strategy

### Unit Tests:

- `Walk.open_nearby`: matches within radius, excludes beyond radius, excludes
  different city, excludes non-`requested` states, excludes rows with nil
  coordinates.
- `Walk` validations: `latitude`/`longitude` presence.
- Cache write/read round-trip for the walker-location key (TTL expiry can be
  tested via `travel_to`/`travel` rather than a real sleep).

### Integration Tests:

- `WalksController#create` with/without coordinate params.
- `OpenRequestsController#index` with/without `lat`/`lng` params.

### Manual Testing Steps:

1. Grant location as an Owner, create a request — confirm coordinates land in
   the DB.
2. Deny location as an Owner — confirm the button stays disabled with a clear
   message.
3. Grant location as a Walker within 10km of an open request — confirm it
   appears.
4. Position (or simulate) a Walker beyond 10km — confirm it doesn't appear.
5. Two-tab live-broadcast check: Walker A's tab open, Owner creates nearby →
   Walker A sees it without refreshing; Walker B (out of radius) doesn't.

## Performance Considerations

City remains the first-pass filter (reuses the existing `["state", "city"]`
index) before the `earth_distance` check runs, keeping the radius query cheap
at any city's request volume. The GiST index on `ll_to_earth(latitude, longitude)`
(partial, `WHERE ... IS NOT NULL`) makes the distance predicate itself
index-assisted rather than a full scan. Per-Walker broadcast fan-out (Phase 5)
means one walk-creation event now writes N rows to the `cable` table instead
of one (N = same-city Walkers with a live cache entry) — negligible at the
PRD's stated `target_scale` (small users, low qps), same reasoning R-01 already
applied to its own broadcasts; revisit if Walker density per city grows
significantly.

## Migration Notes

Three migrations, in order: (1) drop `postcode` from `users`/`walks`
(Phase 1), (2) enable `cube`+`earthdistance` (Phase 2), (3) add
`walks.latitude`/`longitude` + GiST index (Phase 2). No backfill needed for
any of them — postcode removal has nothing to preserve, and coordinate
columns start nullable with no historical data requiring geocoding (see
**What We're NOT Doing**).

## References

- Frame brief: `context/changes/geolocation-matching/frame.md`
- Related roadmap items: R-01 (`realtime-walk-status-updates`,
  `context/archive/2026-08-21-realtime-walk-status-updates/`) — broadcast
  design precedent; S-02 (`profile-with-city`,
  `context/archive/2026-06-16-profile-with-city/`) — original city/postcode
  migration convention (add→backfill→NOT NULL), not needed here since no
  backfill applies.
- PRD refs: Open Question #6 (resolved by this plan); FR-005 (diverged by
  postcode removal — flagged, not auto-corrected in `prd.md`).
- Code references: `app/models/walk.rb`, `app/models/user.rb`,
  `app/controllers/{walks,open_requests,home,registrations,profiles}_controller.rb`,
  `db/schema.rb`, `config/routes.rb`, `config/cable.yml`, `config/puma.rb`.

## Progress

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles.

### Phase 1: Postcode removal

#### Automated

- [x] 1.1 Migration applies cleanly — 052db01
- [x] 1.2 Full test suite passes — 052db01
- [x] 1.3 Linting passes — 052db01

#### Manual

- [x] 1.4 Sign-up form has no postcode field
- [x] 1.5 Profile edit form has no postcode field
- [x] 1.6 Profile show view has no postcode row

### Phase 2: Schema & radius query foundation

#### Automated

- [ ] 2.1 Migrations apply cleanly
- [ ] 2.2 Walk model tests pass
- [ ] 2.3 Full test suite passes
- [ ] 2.4 Linting passes

#### Manual

- [ ] 2.5 Console check: `open_nearby` includes near rows, excludes far row

### Phase 3: Owner-side location capture

#### Automated

- [ ] 3.1 Controller/integration test: create with coordinates succeeds
- [ ] 3.2 Controller/integration test: create without coordinates fails validation
- [ ] 3.3 Full test suite passes

#### Manual

- [ ] 3.4 Browser: grant location, submit succeeds, coordinates persisted
- [ ] 3.5 Browser: deny location, submit stays blocked with clear message

### Phase 4: Walker-side radius-aware list

#### Automated

- [ ] 4.1 Integration test: coordinates present → filtered results
- [ ] 4.2 Integration test: coordinates absent → placeholder state
- [ ] 4.3 System test: in-radius Walker sees request, out-of-radius does not
- [ ] 4.4 Full test suite passes

#### Manual

- [ ] 4.5 Browser: open-requests page resolves from placeholder to list
- [ ] 4.6 Browser: denial shows "location required", no list, no crash
- [ ] 4.7 Browser: home dashboard count badge matches same behavior

### Phase 5: Live per-Walker broadcast

#### Automated

- [ ] 5.1 Model broadcast test: in-radius Walker's channel receives broadcast, out-of-radius does not
- [ ] 5.2 System test: two-session live update reaches only in-radius Walker's open tab
- [ ] 5.3 Full test suite passes

#### Manual

- [ ] 5.4 Two-browser demo: new request appears live only for in-radius Walker
