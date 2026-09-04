# Real-time Walk Status Updates — Plan Brief

> Full plan: `context/changes/realtime-walk-status-updates/plan.md`

## What & Why

Walkie's locked PRD explicitly excluded real-time UI updates from v1 ("Owners and Walkers see status changes by refreshing"). With more runway than the original 3-week budget assumed, the team is reversing that non-goal: state changes (REQUESTED created/taken, ACCEPTED → IN_PROGRESS → COMPLETED) should push live over Turbo Streams / Solid Cable, already in the Gemfile. This is purely additive — no FR, role, or state-machine change.

## Starting Point

`turbo-rails` and `solid_cable` gems are installed with correct per-environment adapter config, but nothing is actually wired: `/cable` isn't mounted, there are no broadcasts anywhere, no partials exist (every target view inlines its markup), and the production Solid Cable database has never been provisioned. `Walk`'s transition methods (`accept!`/`start!`/`complete!`/`cancel!`) use a raw `update_all` compare-and-swap that bypasses ActiveRecord callbacks entirely — the single biggest constraint on how broadcasting can be wired in.

## Desired End State

An Owner watching their home dashboard or walk-requests page sees a Walker's accept/start/complete actions reflected instantly, with no refresh. A Walker watching the open-requests list sees new requests appear and taken/cancelled requests vanish live. Everything else about the app — the HTTP flow, the state machine, role scoping — is unchanged.

## Key Decisions Made

| Decision | Choice | Why (1 sentence) |
| --- | --- | --- |
| Broadcast trigger site | Inside `Walk#swap_state` after a successful CAS, plus `after_create_commit` for new requests | The CAS's `update_all` skips callbacks entirely, so this is the only place guaranteed to fire exactly once per real transition |
| Open-requests stream scope | One stream per `(city, postcode)` | Mirrors the existing `open_in_locality` scope exactly — no cross-locality data leakage |
| Partial consolidation | Shared "current walk" partial for home + `walker_walks#index` (literally duplicated markup); separate partial for open-request rows | Consolidates only what's genuinely identical, without forcing unrelated shapes into one over-parameterized partial |
| Broadcast targeting | Whole-container replace, not per-row append/remove | Eliminates the "append target doesn't exist because empty-state markup was rendered instead" failure mode, at negligible cost given the PRD's small/low-qps scale |
| Accept-race UX | No new logic — the existing "already accepted" alert already covers it | The CAS already guarantees correctness; live removal is cosmetic urgency for everyone else |
| Home dashboard open-requests count | Broadcast-driven, same locality stream as the list | One consistent event model instead of introducing a second (frame-reload) mechanism |
| Testing | Model-level `assert_turbo_stream_broadcasts` on every transition + 2 targeted dual-session system tests | Cheap correctness net plus real end-to-end confidence, without making every system test a flaky dual-session test |
| Production Solid Cable DB | Provisioned in this plan (Phase 5), not deferred | The feature can't actually broadcast in production without it — deferring risks a silent "works in dev, dead in prod" gap |
| Reconnect fallback | None — rely on Turbo's built-in reconnect | Consistent with the PRD's existing "no offline support" non-goal |

## Scope

**In scope:**
- Walker's open-requests list (live add/remove)
- Active-walk screen, both roles (`walker_walks#index`, `walks#index` Active table)
- Home dashboard, both roles (Owner's active-request card, Walker's current-walk widget + open-requests count)
- Mounting `/cable`, production origin restriction, Solid Cable DB provisioning

**Out of scope:**
- Walk history views (S-08/S-09 "Past" tables) — immutable, no live-update value
- Any state-machine, role, or FR change
- Polling fallback for dropped connections
- Roadmap.md edit (deferred to a follow-up per `change.md`)

## Architecture / Approach

Three Turbo Streams, each keyed to who needs to see what: a locality stream (`open_requests` + city + postcode) for the Walker-facing open list and count; a per-walker stream for their single active-walk widget; a per-owner stream for their (possibly multi-item) active-walks views. `Walk` broadcasts to whichever streams a transition affects — always the owner's, conditionally the locality's (only when entering/leaving REQUESTED) and the walker's (only once one is assigned). Every broadcast replaces a whole, always-rendered container rather than appending/removing individual rows, so empty states are just another render of the same container.

## Phases at a Glance

| Phase | What it delivers | Key risk |
| --- | --- | --- |
| 1. Cable transport plumbing | `/cable` mounted, production origins locked down | Low — no channel code needed, turbo-rails auto-connects |
| 2. Model-level broadcasting | `Walk` broadcasts on every transition + creation, fully model-tested | Medium — must not disturb the CAS concurrency guarantee |
| 3. Walker-facing live views | Open-requests list + Walker's current-walk widget, live | Medium — first dual-session system test, empty-state container gotcha |
| 4. Owner-facing live views | Owner's home card + `walks#index` Active table, live | Medium — two different markup shapes (card vs. table row) sharing one stream |
| 5. Production readiness | Solid Cable DB provisioned, deploy path verified | Medium — generator force-overwrites `config/cable.yml`; must restore the production tuning |

**Prerequisites:** None beyond what's already merged — this builds entirely on existing gems, models, and views.
**Estimated effort:** ~3-4 sessions across 5 phases.

## Open Risks & Assumptions

- Assumes Kamal's deploy hook already runs `db:prepare` for all configured databases (needs a one-time confirmation in Phase 5, not a code change).
- The two dual-session system tests are new test surface for this codebase (no existing test drives two concurrent Capybara sessions) — first attempt may need iteration to avoid flake.
- Synchronous (not `_later`/ActiveJob-queued) broadcasting is assumed safe against the 2-second NFR at current scale; revisit only if a future load test says otherwise.

## Success Criteria (Summary)

- An Owner and a Walker in two separate browser sessions can watch a walk move through its full lifecycle with neither session ever navigating or refreshing.
- All existing tests (model, integration, system) continue to pass unmodified alongside the new broadcast and dual-session tests.
- The feature actually works after a real deploy, not just in dev/test.
