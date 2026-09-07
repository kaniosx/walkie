# Static Walker↔Owner Distance Display — Plan Brief

> Full plan: `context/changes/walker-owner-distance-display/plan.md`
> Frame brief: `context/changes/walker-owner-distance-display/frame.md`

## What & Why

Show the distance between Walker and Owner (e.g. "2.3 km") on the open-requests list and both parties' active-walk screens. The original ask was a live-updating number, but the frame found that "live" would reverse a distinct, never-touched non-goal ("continuous GPS tracking during a walk") requiring materially new infrastructure — the same build as an earlier-discussed live-map idea, just rendered as text. The user chose to scope down to a **static**, page-load-computed distance instead, which rides on L-01's existing precedent and needs no non-goal reversal.

## Starting Point

L-01 already captures coordinates (Owner's at request creation, Walker's one-shot on the open-requests/home pages) and already computes Haversine distance internally (`Walk#distance_km_to`, private, used only to decide broadcast eligibility). Nothing renders that number to a user today, and two of the three target screens (both active-walk views) have no location-capture mechanism at all.

## Desired End State

Walker sees the distance to the Owner on the open-requests list and on their own active-walk screen. Owner sees the distance to the assigned Walker on `/walks` and the home dashboard. Wherever a location is unavailable (declined permission, expired cache), the distance line is simply absent — no placeholder, no error.

## Key Decisions Made

| Decision | Choice | Why (1 sentence) | Source |
| --- | --- | --- | --- |
| Live vs. static | Static, page-load-computed | Live requires the same infra as continuous GPS tracking, a distinct non-goal never touched by prior reversals | Frame |
| Scope (which screens) | Both open-requests list and both roles' active-walk screens | User confirmed this is one unified feature, not scoped to a single screen | Frame |
| Walker's location on their own active-walk screen | New one-shot geolocation capture on that page | `WalkerLocationCache` goes stale once the Walker stops visiting the open-requests/home pages mid-walk | Plan |
| Owner's location for distance calc | Reuse the coordinates already stored on `Walk` from request creation | Avoids a second geolocation prompt for the Owner; Owner rarely moves meaningfully during a short walk | Plan |
| Missing/stale data | Omit the distance element silently | Matches existing pattern (`WalkerLocationCache.write` already no-ops on missing coordinates); avoids designing a new error state | Plan |
| Display format | Rounded to 1 decimal (e.g. "2.3 km") | Matches Haversine's actual precision without over- or under-stating it | Plan |
| Dashboard parity | Include `home/_owner_active_walks.html.erb`, not just `/walks` | Owner should see the same information regardless of which screen they check | Plan |
| Test coverage | Unit test on the hardened `distance_km_to` + integration tests on all three views | Matches this project's existing test-plan-driven testing culture | Plan |

## Scope

**In scope:**
- Public, nil-safe `Walk#distance_km_to`
- Distance display on open-requests list, Walker's active-walk screen, Owner's `/walks` table, Owner's home-dashboard active-walks card
- A new one-shot geolocation capture on the Walker's active-walk screen (reusing the existing Stimulus controller unmodified)
- Fixing an existing N+1 gap (`accepted_by_walker` not eager-loaded) as part of the Owner-side work

**Out of scope:**
- Live/auto-updating distance (`watchPosition`, polling, new broadcast channel)
- Any map or visual position indicator
- Changes to `Walk.open_nearby`'s radius-filter logic or `MATCH_RADIUS_KM`
- Fresh geolocation capture for the Owner
- Any placeholder/error UI for missing distance data

## Architecture / Approach

No new infrastructure. Phase 1 hardens and exposes the existing Haversine method. Phase 2 (open-requests list) just threads already-available coordinates into a partial's locals. Phase 3 adds one new capture point (Walker's active-walk screen) that reuses the existing Stimulus controller unmodified, scoped to a small nested turbo-frame so it never blocks the Start/End button. That capture also refreshes `WalkerLocationCache`, which Phase 4 (Owner-side, read-only, no new client-side code) depends on for its own distance figure.

## Phases at a Glance

| Phase | What it delivers | Key risk |
| --- | --- | --- |
| 1. Model | Public, nil-safe `distance_km_to` | Low — pure model change, existing internal caller unaffected |
| 2. Open-requests list | Distance on each Walker-facing card | Low — data already flows through the controller |
| 3. Walker's active-walk screen | Distance without blocking Start/End button | Medium — new turbo-frame nesting pattern, must not regress existing UX |
| 4. Owner's active-walk screens | Distance on `/walks` + dashboard | Medium — depends on Phase 3 having run recently enough to populate the cache |

**Prerequisites:** L-01 (`geolocation-matching`) already shipped — this plan builds entirely on its data.
**Estimated effort:** ~1-2 sessions across 4 phases.

## Open Risks & Assumptions

- Owner-side distance is only as fresh as the Walker's last visit to their own active-walk screen (bounded by the 10-minute cache TTL) — for a long walk where the Walker never re-opens that screen, the Owner's distance can go stale or disappear. Accepted per the "static, not live" scope decision.
- `WalkerLocationCache` remains single-process (`:memory_store` in all environments, per its own code comment) — a multi-worker production deploy would see inconsistent reads. Pre-existing limitation from L-01, not introduced by this plan.

## Success Criteria (Summary)

- A Walker with location granted sees a distance figure on every open-request card and on their own active-walk screen, without any delay to the Start/End button.
- An Owner sees a distance figure to their assigned Walker on both `/walks` and the home dashboard, whenever that Walker has recently viewed their own active-walk screen.
- Nobody sees an error or broken layout when location data is unavailable — the distance line is simply absent.
