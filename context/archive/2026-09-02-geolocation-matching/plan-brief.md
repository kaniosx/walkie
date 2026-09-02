# Geolocation-Radius Walker↔Owner Matching — Plan Brief

> Full plan: `context/changes/geolocation-matching/plan.md`
> Frame brief: `context/changes/geolocation-matching/frame.md`

## What & Why

Replace `Walk.open_in_locality`'s exact city+postcode string match with a
radius-based match using live browser-captured coordinates. The frame brief's
reframed problem statement — that geolocation matching wasn't the actual
blocker on real launch, but was a legitimate post-v1 PRD direction (Open
Q#6) — held; the user chose to proceed with it anyway after seeing that
analysis, so this plan implements it deliberately, resolving the two
entangled decisions the frame flagged: filtering stays clean of the "no
proximity ranking" non-goal (no distance sort), and the R-01 broadcast
precedent is adapted rather than reused as-is (new per-Walker channel).

## Starting Point

Today, `Walk.open_in_locality(city, postcode)` (`app/models/walk.rb:23`) does
an exact match on both fields; a Walker in the same city but a different
postcode sees nothing. No geo infra exists anywhere in the codebase — no
gems, no DB extensions, no coordinate columns. R-01's realtime broadcast
layer keys its Turbo Stream channels directly off `[city, postcode]`, which
this plan has to redesign since "nearby" isn't a fixed string bucket the way
"same city+postcode" is.

## Desired End State

A Walker sees REQUESTED walks within 10km of their current browser-reported
position (pre-filtered to their profile's city), with live updates delivered
to exactly the Walkers currently in range. An Owner's request permanently
snapshots their coordinates at creation time. Anyone who denies or lacks
browser geolocation sees a "location required" state — no degraded fallback
to the old matching. `postcode` no longer exists anywhere in the app.

## Key Decisions Made

| Decision | Choice | Why (1 sentence) | Source |
| --- | --- | --- | --- |
| Filter vs. sort | Filter only, FIFO order unchanged | Stays clean of the separate "no proximity ranking" non-goal | Plan (questioning) |
| Coordinate source | Browser `navigator.geolocation` | User's explicit choice over server-side geocoding — no external API dependency | Plan (questioning) |
| Distance engine | Postgres `cube`+`earthdistance` | Stock extensions, zero new gems, indexable at this scale | Plan (questioning) |
| Radius | Fixed 10km, not configurable | Simplest option that delivers real value; matches PRD's minimalist style | Plan (questioning) |
| Coordinate persistence | Live per page view, not stored on `User` | User's explicit choice — coordinates never touch the profile | Plan (questioning) |
| Missing-location fallback | Exclude entirely, no fallback to old matching | User's explicit choice — a conscious UX tradeoff, not an oversight | Plan (questioning) |
| Broadcast targeting | Per-Walker channel (`[walker, :nearby_open_requests]`) | Correct at any radius; follows R-01's existing per-entity array-key convention | Plan (questioning) |
| City pre-filter | Kept | Reuses the existing `["state", "city"]` index for a cheap first pass | Plan (questioning) |
| Live-location cache | Short-TTL `:memory_store` (not Solid Cache) | Solid Cache isn't actually wired up in this repo; activating it is disproportionate for 10-min-TTL data; single Puma worker makes `:memory_store` correctness-safe | Plan (research) |
| `postcode` | Removed entirely (`users` + `walks`) | Becomes fully unused once city+radius replaces city+postcode matching | Plan (questioning) |

## Scope

**In scope:**
- `cube`/`earthdistance` extensions, `walks.latitude`/`longitude`, `Walk.open_nearby`
- Owner-side geolocation capture at walk-request creation
- Walker-side geolocation-aware open-requests list + home dashboard count
- Per-Walker live broadcast redesign
- Full removal of `postcode` (columns, validations, forms, tests)

**Out of scope:**
- Distance-based sort/ranking
- Configurable per-Walker radius
- Any fallback to city/postcode matching for ungeolocated users
- PostGIS, external geocoding APIs, map UI
- Backfilling historical walk rows with coordinates
- Editing `context/foundation/prd.md` (FR-005 divergence is documented, not auto-corrected)

## Architecture / Approach

Owner coordinates are captured live and permanently snapshotted onto the
`Walk` record at creation (same pattern as today's city/postcode snapshot,
different source). Walker coordinates are *never* persisted to the profile —
captured fresh per page view via a self-referencing Turbo Frame (JS resolves
geolocation, sets the frame's own `src` back to the same URL with
`lat`/`lng` params, Turbo extracts the populated fragment from the response —
no new routes needed) and written to a short-TTL cache purely for live
broadcast targeting. The realtime layer keeps R-01's existing
`turbo_stream_from [record, :symbol]` convention, just pointed at the Walker
instead of a city string.

## Phases at a Glance

| Phase | What it delivers | Key risk |
| --- | --- | --- |
| 1. Postcode removal | `postcode` gone everywhere, tests updated | Diverges from PRD FR-005 — documented, not silently done |
| 2. Schema & radius foundation | `open_nearby` scope, Owner coordinate snapshot | New SQL (`earth_distance`) with no in-repo precedent |
| 3. Owner-side capture | Geolocation-gated walk-request form | First browser-API Stimulus controller in this repo |
| 4. Walker-side radius list | Self-referencing Turbo Frame for list + count | First geolocation stubbing needed in system tests |
| 5. Live per-Walker broadcast | Redesigned realtime targeting | Solid Cable is DB-backed/polling — N-Walker fan-out multiplies writes |

**Prerequisites:** None beyond what's already shipped (R-01, S-01..S-10).
**Estimated effort:** ~5 sessions, one per phase, each with its own manual
browser-verification checkpoint.

## Open Risks & Assumptions

- **PRD FR-005 divergence**: this plan removes `postcode`, which the PRD
  still names as a profile field. Not auto-corrected — a follow-up `/10x-prd`
  run would be needed to formally amend the text.
- **`:memory_store` cache assumes single-process production** (`WEB_CONCURRENCY`
  unset in `config/puma.rb`). If that ever changes, per-Walker broadcast
  targeting silently breaks across processes — flagged in the plan's Critical
  Implementation Details, not otherwise guarded against in code.
- **No existing precedent for stubbing browser geolocation in system tests**
  — Phase 4 establishes this from scratch (Chrome auto-grant prefs + CDP
  `Page.setGeolocationOverride`); some trial-and-error during implementation
  is likely.
- **"Exclude ungeolocated users entirely"** is a real UX regression risk for
  any Walker on a browser/device that blocks geolocation by default — a
  conscious tradeoff the user chose explicitly during questioning, not an
  oversight.

## Success Criteria (Summary)

- A Walker inside the 10km radius sees a request; one outside does not.
- A new request's live Turbo Stream update reaches only in-radius Walkers'
  already-open tabs.
- `postcode` no longer appears anywhere in the schema, models, forms, or views.
- Full test suite + rubocop + brakeman pass with no regressions to existing
  lifecycle/history/broadcast behavior.
