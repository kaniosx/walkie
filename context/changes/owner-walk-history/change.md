---
change_id: owner-walk-history
title: Owner walk history — active / past split with timestamps (S-08)
status: impl_reviewed
created: 2026-06-23
updated: 2026-06-23
---

## Notes

Roadmap item **S-08** (`context/foundation/roadmap.md`). Outcome: An Owner sees their own past + current walks (every state, including COMPLETED and CANCELLED). PRD FR-015, §NFR "completed walks remain in immutable history."

S-04 and S-06 built the walks index and cancel action; the current index shows non-cancelled walks with minimal info (dog name, state, created_at). This slice enriches it into a proper history: cancelled walks added, Active / Past split, lifecycle timestamps, and walker display name for Past walks.
