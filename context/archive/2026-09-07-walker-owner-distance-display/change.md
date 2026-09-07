---
change_id: walker-owner-distance-display
title: Display live distance between Walker and Owner on UI
status: archived
created: 2026-09-07
updated: 2026-09-07
archived_at: 2026-09-07T15:10:55Z
---

## Notes

Opened via `/10x-frame` for a user-proposed roadmap addition: show the numeric
distance between Walker and Owner on the open-requests list and the
active-walk screen, updating live without a page refresh.

Framed before any roadmap entry was written because it lands on PRD non-goal
territory (§Non-Goals "Real-time UI layer (live GPS...)" and §Open Q #6
"no radius, no map, no proximity ranking") — same shape of decision as L-01
(`geolocation-matching`), which itself was opened via `/10x-frame`.

**Decision (2026-09-07):** frame found "live" would reverse a distinct,
never-touched non-goal ("continuous GPS tracking during a walk") requiring
new infra (watchPosition, per-walk storage, new broadcast channel) —
identical in shape to the "live map" idea raised earlier the same session.
User chose to scope down to a **static**, page-load-computed distance
instead, riding on L-01's existing precedent. See `frame.md` → `## Decision
(post-frame)`. Added to roadmap as `L-02`.
