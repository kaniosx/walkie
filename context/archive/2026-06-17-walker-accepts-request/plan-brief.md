# S-05: Walker Accepts an Open Request — Plan Brief

> Full plan: `context/changes/walker-accepts-request/plan.md`

## What & Why

The **north star**: a signed-in Walker sees the open (REQUESTED) walk requests in their city + postcode and accepts one — REQUESTED → ACCEPTED, bound to them, gone from every other walker's list (FR-011, FR-012, US-02). This is the slice that puts the PRD's core hypothesis ("the gap isn't supply, it's the 'available right now' signal") in front of real users; the validation milestone lands at the first real acceptance.

## Starting Point

F-02 already solved the hard part: `Walk#accept!` is an atomic compare-and-swap, the `walks_walker_presence` DB CHECK enforces consistency, and `walk_concurrency_test` proves exactly one winner across 10 racing threads. S-04 produces the REQUESTED walks (with city/postcode copied from the owner). There is no walker-facing controller, route, or view yet — the walker home branch is a placeholder.

## Desired End State

A Walker opens "Open requests" (nav + home link), sees the REQUESTED walks in their exact city + postcode — dog name, breed, locality, and an Accept button (no owner identity) — and taps Accept. The walk binds to them and drops off the list (and everyone else's). Tapping a walk someone just took returns them to the refreshed list with "already accepted". Owners can't reach the controller; out-of-locality/non-requested walks never appear.

## Key Decisions Made

| Decision | Choice | Why (1 sentence) |
| --- | --- | --- |
| Controller | New walker-gated `OpenRequestsController` (index + accept) | Clean role separation; owner `WalksController` stays `OwnerOnly` |
| Walker gate | New `WalkerOnly` concern (mirror `OwnerOnly`) | Symmetric, one-line include, consistent message |
| Locality filter | city AND postcode (exact equality) | Tighter match; literal "same city / postcode" |
| Accept | Call existing `Walk#accept!`, branch on its boolean | Race already DB-enforced + tested; no new concurrency code |
| Post-accept | Redirect to open list + flash; accepted walk drops off | Walker history (own accepted walks) is S-09 |
| Lost race | Redirect to list with "already accepted" alert | Honest, self-correcting; matches US-02 outcome |
| List row | Dog + breed + locality + Accept; no owner identity | Expose only what the FR requires (PRD §NFR) |
| Race test | Sequential "already accepted" integration test | Integration tests are serial/transactional; parallel race stays `walk_concurrency_test`'s job |
| Tests | Full flow + role-separation + locality + lost-race | Locks both PRD guardrails at the HTTP layer |

## Scope

**In scope:** `WalkerOnly` concern; `Walk.open_in_locality(city, postcode)` scope; `resources :open_requests` (index + member accept); `OpenRequestsController`; open-requests index view; walker nav/home links; integration + scope tests.

**Out of scope:** start/complete (S-07); walker walk-history view (S-09); owner identity in list; realtime/auto-refresh; radius/proximity; any new concurrency mechanism; migration.

## Architecture / Approach

Walker-gated Rails flow on the existing `Walk`. List = `Walk.open_in_locality(current_user.city, current_user.postcode).includes(:dog)`. Accept = `walk.accept!(current_user)` → branch: won → notice; lost/taken → "already accepted" alert. Phase 1 is backend plumbing (concern + scope + scope test); Phase 2 is the controller/view/nav/links + integration tests.

## Phases at a Glance

| Phase | What it delivers | Key risk |
| --- | --- | --- |
| 1. Walker gate + scope | `WalkerOnly` concern + `Walk.open_in_locality` + scope test; suite green | Tiny/additive; mainly getting the locality filter exactly right (city AND postcode) |
| 2. Walker flow + accept | open-requests list + accept (calls accept!), nav/home, integration tests | Don't re-implement the race — call accept! and surface its boolean; keep the controller walker-gated |

**Prerequisites:** S-01, S-02, S-04, F-02 — all done.
**Estimated effort:** ~1 session across 2 phases. No migration.

## Open Risks & Assumptions

- The literally-parallel HTTP race isn't unit-tested in the integration suite (serial/transactional); the real race is covered by F-02's thread-based `walk_concurrency_test` — S-05 verifies the sequential outcome contract only.
- city+postcode exact match may show an empty list in a thin market; accepted v1 coarseness (a friendly empty state names the locality).
- 2s NFR met on a warm DB; free-tier cold start caveat applies as in S-04.

## Success Criteria (Summary)

- A Walker accepts an in-locality open request in one tap; it binds to them and disappears from all walkers' lists.
- Exactly one walker can hold a given walk; a losing/late accept gets "already accepted" with the original binding intact.
- Owners can't reach the walker controller; out-of-locality/non-requested walks never appear. Suite + rubocop + brakeman green.
