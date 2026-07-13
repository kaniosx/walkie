# Owner and Walker Walk History — Plan Brief

> Full plan: `context/changes/e2e-walk-history/plan.md`

## What & Why

Add a fifth real-flow browser-level system test (roadmap **T-05**) proving both walk-history views render correctly: an Owner sees a completed walk in their `walks_path` Past section with the walker's name, and a Walker sees the same completed walk in their `walker_walks_path` history section with the owner's name. Closes the last item in the "Testing infrastructure" stream (F) — T-01 through T-04 covered creation, acceptance, cancellation, and the full lifecycle; T-05 covers the resulting history views on both sides.

## Starting Point

T-01 wired Rails System Tests into Docker/CI with the shared infra and pattern; T-02 added the sign-in helper. S-08 and S-09 (both done, unchanged since) built the Owner and Walker history views — Active/Past split for Owner, active-walk + history table for Walker — and are already integration-tested for rendering and cross-account isolation. No infra or feature work is needed; this is the last browser-level gap.

## Desired End State

A new `test/system/walk_history_test.rb` with two tests: one confirms the Owner's Past section shows a completed walk with the walker's display name and state, the other confirms the Walker's history section shows the same walk with the owner's display name — both also confirming the `"No past walks yet."` empty state renders correctly. Verified via a deliberate-break check on each view's past-section rendering.

## Key Decisions Made

| Decision | Choice | Why (1 sentence) | Source |
| --- | --- | --- | --- |
| File structure | One file, two independent test methods | Both assertions serve one roadmap outcome (T-05); no shared state, so no reason to split into two files | Plan |
| Fixture construction | Model bang! calls (`accept!`/`start!`/`complete!`) directly in setup | Matches the exact convention already used in `walks_test.rb`/`walker_walks_test.rb` to build terminal-state walks; T-04 already proved the UI transition path, so redriving it here is redundant | Plan |
| Scenario depth | One COMPLETED walk each + empty state, no CANCELLED case | Directly matches T-05's stated outcome and Low risk rating (render-only); T-03 and the integration layer already cover CANCELLED | Plan |
| Cross-account isolation | Not re-tested at the browser layer | Already proven at the integration layer per T-05's roadmap risk note — this test only needs to prove rendering | Plan |
| Deliberate-break target | Force each view's past-section condition to the empty-state branch, then revert | Targets exactly what this test uniquely protects (the rendering path), not logic already covered elsewhere | Plan |

## Scope

**In scope:**
- `test/system/walk_history_test.rb` (new)

**Out of scope:**
- Any changes to `walks_controller.rb`, `walker_walks_controller.rb`, or either view (the deliberate-break view edits are temporary and reverted before the phase is done)
- CANCELLED-walk browser-level coverage (already covered by T-03 and the integration layer)
- Cross-account isolation at the browser layer (already covered at the integration layer)
- Any CI, Gemfile, Dockerfile, or sign-in-helper changes — all already in place from T-01/T-02

## Architecture / Approach

One test file, two independent tests. Each builds a completed-walk fixture via direct model bang! calls (bypassing the UI transition path, which T-04 already proves), signs in through the real form, visits the relevant history page, and asserts the rendered content. A second no-past-walks user in each test proves the empty state.

## Phases at a Glance

| Phase | What it delivers | Key risk |
| --- | --- | --- |
| 1. Add the walk-history system test | New system test file (2 tests), deliberate-break verified | Low — roadmap already rates this Low risk; render-only assertions with no concurrency or isolation angle |

**Prerequisites:** T-01 infra (done), T-02 sign-in helper (done), S-08/S-09 features (done) — all already in place.
**Estimated effort:** ~1 session, single phase.

## Open Risks & Assumptions

- Assumes the "Walked by" / owner-name column and empty-state string in both views remain stable — a future redesign of either view would need this test updated alongside it.
- Assumes `walk.accept!(walker); walk.start!(walker); walk.complete!(walker)` reliably reaches COMPLETED without additional guards — already true per existing integration-test usage of the identical sequence.

## Success Criteria (Summary)

- `bin/rails test:system` passes locally and in CI, including both new tests.
- Both tests are confirmed to fail when the relevant view's past-section rendering is deliberately broken, then pass again once reverted.
- Both the Owner's and the Walker's walk-history views are provably shown to render a completed walk with the correct counterpart name, and the empty state when there are none.
