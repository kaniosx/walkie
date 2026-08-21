---
change_id: realtime-walk-status-updates
title: Real-time walk status updates via Turbo Streams
status: implemented
created: 2026-08-21
updated: 2026-08-21
archived_at: null
---

## Notes

Reverses the PRD non-functional non-goal "No real-time UI updates" (§Non-Goals) —
a deliberate v1 limitation, now being picked up because the MVP has more runway
than the original 3-week budget assumed. This is additive: it does not change
the state machine, roles, or any FR — only how state changes become visible.

Scope decided with the user before planning:
- **Transport:** Turbo Streams over Solid Cable (already in the stack per
  `context/foundation/tech-stack.md` — no new infra, no Redis/ActionCable
  external dependency).
- **Screens/transitions in scope (full lifecycle, first iteration):**
  - Walker's open-requests list (S-05 view) — new REQUESTED walk appears live;
    a walk disappears live the moment another Walker accepts it (reinforces
    the Singleness guarantee visibly, not just via refresh).
  - Active-walk screen, both roles (S-07 views) — ACCEPTED → IN_PROGRESS →
    COMPLETED reflected live without navigating away.
  - Home dashboard (U-06) — Owner's active-request status card and Walker's
    current-walk / open-requests-count both update live.
- Walk history views (S-08/S-09) are explicitly out of scope for this
  iteration — they show completed/immutable state, no live-update value.

Roadmap implication: this should land as a new item in `context/foundation/roadmap.md`
(under a new stream, e.g. "Realtime") — not yet added; leave that to `/10x-plan`
or a follow-up roadmap edit once the plan's shape is known.
