# S-04: Owner Creates a Walk Request — Plan Brief

> Full plan: `context/changes/owner-creates-walk-request/plan.md`

## What & Why

Let an Owner with a dog tap "Walk my dog" and create a walk request in REQUESTED state (FR-009, US-01). This is the request the north-star slice S-05 (walker accepts) consumes — the first half of the marketplace binding. The flow is optimized to be quick: one tap from the home page or the dogs list.

## Starting Point

F-02 already built the `Walk` model, state machine, DB CHECK constraints, the `owner_id = dog.user_id` invariant, and transition methods. S-02 made `users.city`/`postcode` NOT NULL; S-03 gave Owners a dogs CRUD with an owner-only gate. There is no walks controller, route, or view yet.

## Desired End State

An Owner lands on home, sees their active dogs each with a one-tap "Walk my dog" button (also on `/dogs`), taps it, and a REQUESTED walk is created with city/postcode copied from their profile; they're redirected to a minimal "My walk requests" list showing it. A second tap for a dog that already has an active request is rejected. Walkers can't create requests; an Owner can't request for another owner's dog.

## Key Decisions Made

| Decision | Choice | Why (1 sentence) |
| --- | --- | --- |
| Entry point | Per-dog "Walk my dog" button on home **and** /dogs | One-tap, fast; home lists the owner's dogs with buttons |
| Walk locality | Auto-copied from owner profile at create | PRD §Locality; zero friction; always populated (NOT NULL) |
| Post-create | Minimal owner walks index + redirect with flash | Satisfies US-01 "visible in own history"; S-08 enriches later |
| No-dogs gate | Naturally gated (no button) + scoped `dogs.active.find` | Scoped create is the binding guard; no special-case UI |
| Duplicate requests | Prevent a second **active** request per dog (model guard) | A dog is walked once at a time; stops double-tap dupes |
| Owner gate | Extract shared `require_owner` concern (refactor DogsController) | Two controllers need it; one definition |
| Per-request note | None (no migration) | Keeps one-tap; dog notes already carry care info |
| Tests | Walks controller integration + dupe-guard model test | Covers the flow + role/scoping/dupe guards |

## Scope

**In scope:** Walk `active` scope + one-active-per-dog validation; shared owner concern; `resources :walks` (index/create); WalksController (scoped create, locality copy); walks index; "Walk my dog" buttons on home + /dogs; owners-only "My requests" nav link; tests.

**Out of scope:** walker open-list/accept (S-05); start/complete/cancel UI (S-06/S-07); full history view (S-08); scheduling/notes/per-request locality; DB-level one-active constraint; any migration.

## Architecture / Approach

Owner-side Rails CRUD on the existing `Walk`. Creation: `current_user.dogs.active.find(dog_id)` → `dog.walks.new(owner: current_user, city/postcode from profile)` → save (state defaults to `requested`). Phase 1 is backend plumbing (Walk guard + shared owner concern, refactoring DogsController) with no user surface; Phase 2 is the one-tap flow, listing, and wiring.

## Phases at a Glance

| Phase | What it delivers | Key risk |
| --- | --- | --- |
| 1. Walk guard + shared owner gate | active scope + dupe validation; shared require_owner concern | Refactor changes DogsController's alert text → update the S-03 test assertion |
| 2. Owner walk-request flow | /walks create+index, buttons on home/dogs, nav, tests | Scope every create to current_user.dogs.active (no IDOR / no-dogs); copy locality server-side |

**Prerequisites:** S-01, S-02, S-03, F-02 — all done.
**Estimated effort:** ~1 session across 2 phases. No migration.

## Open Risks & Assumptions

- Dupe-guard is create-time, not race-safe — acceptable (single owner acting sequentially; not a PRD Singleness invariant, which is the walker-side DB guard).
- "Visible in own history" is satisfied by a minimal list now; S-08 enriches it (overlap is intentional, additive).
- The 2s / under-30s NFR is a manual smoke check (no Capybara); measure against a warm/Basic-tier DB, not the free-tier cold start.

## Success Criteria (Summary)

- An Owner creates a walk request in one tap and sees it listed, well under 30s.
- A dog can't have two active requests; Walkers can't create; no cross-owner/soft-deleted-dog requests.
- Suite + rubocop + brakeman green.
