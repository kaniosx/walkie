---
change_id: owner-cancels-requested-walk
title: Owner cancels a walk request in REQUESTED state (S-06)
status: implemented
created: 2026-06-19
updated: 2026-06-19
---

## Notes

Roadmap item **S-06** (`context/foundation/roadmap.md`). Outcome: the Owner who created a walk request can cancel it while it is still in REQUESTED state; cancellation is blocked once a Walker has accepted (PRD FR-010; post-accept cancellation is explicitly post-v1 per §Open Q #5).

The `Walk#cancel!(owner)` model method, the `cancelled` enum state, and the `cancelled_at` column all exist from F-02. This change wires the HTTP layer: route, controller action, view button, and integration tests.
