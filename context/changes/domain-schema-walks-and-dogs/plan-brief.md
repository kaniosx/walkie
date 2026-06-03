# F-02: Domain Data Schema (Dog + Walk) — Plan Brief

> Full plan: `context/changes/domain-schema-walks-and-dogs/plan.md`

## What & Why

Build Walkie's domain data layer: a `dogs` table and a `walks` table with a linear state machine (`requested → accepted → in_progress → completed`, plus a `cancelled` branch off `requested`). The PRD's two non-negotiable Guardrails — single-Walker acceptance and the linear state machine — must be **binding outside the UI**, so they are enforced by DB `CHECK` constraints and atomic compare-and-swap transition methods, not just Active Record validations. This is the foundation S-03/S-04/S-05/S-07 all build on.

## Starting Point

F-01 (`auth-and-role-typing`) is complete: `users` + `sessions` tables exist, `User` has a string-backed `role` enum (Owner/Walker). The schema is at version `2026_05_29_132054`; there are no `dogs` or `walks` tables yet. Conventions are set — string enums, comment-documented migrations with explicit `null: false`, Minitest with inline builders (no fixtures).

## Desired End State

`dogs` and `walks` exist with foreign keys and check constraints; `Dog` and `Walk` models carry associations, validations, and four transition methods (`accept!`/`start!`/`complete!`/`cancel!`); and the single-Walker accept race is proven correct under real multi-threaded contention. No controllers, routes, or views — pure schema + model layer, fully tested.

## Key Decisions Made

| Decision | Choice | Why (1 sentence) | Source |
| --- | --- | --- | --- |
| `state` storage | String-backed enum | Consistent with `User#role`; readable rows; negligible index cost at this scale | Plan |
| `cancelled` state | Define in enum now | PRD §NFR already names it; avoids re-migrating the foundation when S-06 lands | Plan |
| Owner scoping | Denormalized `owner_id` on walks | Makes the role-separation guardrail query direct and robust; survives dog soft-delete | Plan |
| Transition + race enforcement | Model methods + atomic conditional `UPDATE` | Pure omakase, no gem; compare-and-swap makes the accept race correct at the DB | Plan |
| DB constraints | `CHECK` tying `state ↔ walker presence` | PRD Guardrails: invariants binding outside the UI, not advisory | Plan |
| Dog removal (Open Q #4) | Soft-delete (`deactivated_at`) | Roadmap's recommendation; preserves history; forecloses none of S-10's options | Plan |
| Locality field | Snapshot `city`/`postcode` onto walks | Fixes locality at request time; later profile edits can't re-scope an open request | Plan |
| Dog fields | `name` only | Models exactly what's needed; breed/notes deferred to S-03 (trivial additive migration) | Plan |
| Concurrency test | Model-level multi-thread race test in F-02 | Roadmap calls it load-bearing; proves the DB backstop under contention before S-05 | Plan |
| Transition timestamps | `accepted_at`/`started_at`/`completed_at`/`cancelled_at` | Cheap chronology for history (FR-015/016); set in the methods we're already writing | Plan |

## Scope

**In scope:** `dogs` + `walks` migrations (FKs, check constraints, indexes); `Dog` + `Walk` models; four transition methods; soft-delete; unit + DB-constraint + concurrency tests.

**Out of scope:** controllers/routes/views (S-03/04/05/06/07); profile `city` field (S-02); coverage tooling/CI (F-03); state-machine gem; dog detail fields beyond `name`; HTTP-level race test (S-05); DB rename.

## Architecture / Approach

Bottom-up: `Dog` → `walks` table + DB constraints (verified by raw inserts) → `Walk` model + transition methods → concurrency proof + hardening. Transitions are atomic `UPDATE … WHERE id = ? AND state = <expected> [AND owner/walker guard]` — affected-rows=1 wins the race; the `WHERE` guard fuses authorization and the race check into one write. DB `CHECK` constraints are the backstop even when `update_all` bypasses AR.

## Phases at a Glance

| Phase | What it delivers | Key risk |
| --- | --- | --- |
| 1. Dog model + soft-delete | `dogs` table, `Dog` model, `scope :active`, tests | Avoiding `default_scope` foot-gun |
| 2. Walk schema + DB invariants | `walks` table with FKs + both `CHECK`s, raw-insert constraint tests | Getting the `state ↔ walker` CHECK expression exactly right |
| 3. Walk model + transitions | Associations, enum, validations, 4 transition methods + timestamps | Conditional `UPDATE` correctness; `update_all` must set `updated_at` |
| 4. Concurrency + hardening | Multi-thread race test; rubocop/brakeman/audit clean | Test must use real connections (non-transactional) to expose the race |

**Prerequisites:** F-01 complete (✓). Docker dev environment up (`make start`).
**Estimated effort:** ~2–3 sessions across 4 phases.

## Open Risks & Assumptions

- **Concurrency test plumbing:** the race test must disable transactional fixtures and manage connections/cleanup manually, or it silently serializes and proves nothing. Phase 4 manual step 4.6 guards against a no-op test.
- **Locality snapshot vs profile:** F-02 snapshots a locality string with no source field yet (S-02 defines the profile `city`). S-04 must populate `walks.city` from the real profile field; until then it's caller-supplied.
- **Stale `bootstrap_scaffold_*` DB name** persists (out of scope, same as F-01).

## Success Criteria (Summary)

- Full lifecycle (`requested → accepted → in_progress → completed`) and a `cancelled` branch work via model methods; every illegal transition is rejected outside the UI.
- The DB rejects inconsistent rows even on AR-bypassed writes; exactly one of N concurrent `accept!` calls wins.
- `bin/rails test` green; rubocop + brakeman + bundler-audit clean.
