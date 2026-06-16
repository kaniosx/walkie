# S-03: Owner Manages Dog — Plan Brief

> Full plan: `context/changes/owner-manages-dog/plan.md`

## What & Why

Let a signed-in Owner add and edit their own dogs. The dog is the entity the whole marketplace coordinates around (PRD FR-006: "without it Walkie reduces to a generic gig list"), and S-04 (create a walk request) requires an Owner with at least one dog. F-02 built the `Dog` model; this slice adds the remaining detail fields and the owner-facing UI.

## Starting Point

`Dog` exists (F-02): `belongs_to :user`, `name` required, soft-delete machinery, `walks` restrict. The `dogs` table has only `name` as a domain field. There is no dogs controller, route, or view, and nothing in the UI lets an owner manage dogs.

## Desired End State

A signed-in Owner sees a "My dogs" nav link, opens a list of their dogs (each editable) with an "Add a dog" action, adds a dog (name + breed required; weight in kg + notes optional), and edits it. Walkers can't reach `/dogs` (redirected with an alert; link hidden). An Owner can't view/edit another Owner's dog (404). No remove — that's S-10.

## Key Decisions Made

| Decision | Choice | Why (1 sentence) |
| --- | --- | --- |
| Dog fields | name + breed + weight + notes | Enough for a walker to know the dog; richer than name-only |
| Required vs optional | name + breed required; weight + notes optional | Breed always known to a walker; weight/notes nice-to-have |
| breed enforcement | DB `NOT NULL` + backfill (S-02 precedent) | True DB guarantee; collected at dog creation |
| weight modeling | integer kilograms, optional, `>0` & ≤150 when present | No decimal/locale issues; coarse precision fine for v1 |
| Owner-only gate | controller `before_action` redirect + flash | Binding guard (nav hiding is cosmetic on top) |
| Resource shape | `resources :dogs` index/new/create/edit/update (no destroy) | Conventional REST; remove deferred to S-10 |
| Cross-owner access | `current_user.dogs.find` → 404 on miss | Structurally no IDOR; same shape as profile |
| Nav/home | owners-only "My dogs" link + home CTA | Discoverable for owners, hidden from walkers |
| Tests | model validations + controller integration (role gate + scoping) | Covers new fields and the two security guardrails |

## Scope

**In scope:** migration (breed NOT NULL via add→backfill→change-null; weight integer nullable; notes text nullable); Dog validations; `/dogs` CRUD (add+edit); owner gate; per-owner scoping; "My dogs" nav + home CTA; model + integration tests.

**Out of scope:** remove/destroy (S-10); photos; decimal/free-text weight; breed autocomplete; Walker-facing dog views; creating walk requests (S-04).

## Architecture / Approach

Owner-scoped Rails CRUD on the existing `Dog`. Phase 1 is the coupled data layer — migration + model validations + the four dog-creating test fixtures land together, because requiring `breed` breaks any fixture that builds a dog with name only. Phase 2 is the `/dogs` controller/views, owner gate, scoping, and nav/home wiring.

## Phases at a Glance

| Phase | What it delivers | Key risk |
| --- | --- | --- |
| 1. Schema + model + fixtures | breed/weight/notes on Dog with validations; suite green | Missing a dog-creating fixture → red suite (4 files enumerated); NOT-NULL on populated table needs backfill |
| 2. /dogs CRUD + nav/home | Owner add/edit dogs, owner gate, scoping, nav link, tests | Owner gate must block Walkers at the controller (not just hide nav); scope every lookup to current_user.dogs |

**Prerequisites:** S-01 done (auth), F-02 done (Dog model + soft-delete).
**Estimated effort:** ~1 session across 2 phases.

## Open Risks & Assumptions

- `breed` NOT NULL backfill assumes no real users/dogs yet (roadmap baseline) — `"Unknown"` placeholder is safe.
- Four dog-creating test files (walk_test, walk_constraints_test, walk_concurrency_test, dog_test) must be updated in lockstep — enumerated up front (the S-02 lesson).
- No remove action means the soft-delete `active` scope is used read-only here; full removal semantics wait on S-10 / Open Q #4.

## Success Criteria (Summary)

- An Owner can add a dog (name + breed) and edit it; weight/notes optional; missing breed rejected.
- Walkers cannot manage dogs (controller-blocked + link hidden); an Owner cannot touch another Owner's dog (404).
- Suite + rubocop + brakeman green.
