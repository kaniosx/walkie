---
change_id: testing-state-machine-feedback
title: Phase 2 rollout — state machine HTTP feedback for illegal transitions
status: impl_reviewed
created: 2026-06-25
updated: 2026-07-08
archived_at: null
---

## Notes

Open a change folder for rollout Phase 2 of context/foundation/test-plan.md:
"State machine feedback".
Risks covered: #2 (controller HTTP response for illegal/out-of-sequence state transitions).
Test types planned: integration + model.
Risk response intent:
- Risk #2: prove that a Walker attempting an out-of-sequence transition on their own
  walk (e.g. complete before start, or start on a walk already in_progress) receives a
  clear HTTP error response and is not silently misled; the sequential wrong-state path
  produces 404 via WalkerWalksController's state-scoped find — challenge whether this
  same-walker scenario is already covered by Phase 1's IDOR 404 tests or is distinct;
  avoid writing tests for the else-branch flash under the assumption it is sequentially
  reachable (it is race-only).
