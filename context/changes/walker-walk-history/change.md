---
change_id: walker-walk-history
title: Walker walk history — Past section on My walk page (S-09)
status: implementing
created: 2026-06-23
updated: 2026-06-23
---

## Notes

Roadmap item **S-09** (`context/foundation/roadmap.md`). Outcome: A Walker sees the list of their own accepted + current + completed walks. PRD FR-016, §NFR (role separation — scope must be `accepted_by_walker_id: current_user.id` only, never a broader scope that would leak open requests).

S-07 built `WalkerWalksController` showing only the active walk. This slice adds a Past section to the same page: completed walks scoped to this walker, with dog name, breed, completed_at, and owner display_label.
