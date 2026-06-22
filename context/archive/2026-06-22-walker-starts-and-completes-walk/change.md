---
change_id: walker-starts-and-completes-walk
title: Walker starts + completes a walk (S-07, US-03)
status: archived
created: 2026-06-22
updated: 2026-06-22
archived_at: 2026-06-22T07:41:11Z
---

## Notes

Roadmap item **S-07** (`context/foundation/roadmap.md`). Outcome: the Walker who accepted a walk can start it (ACCEPTED → IN_PROGRESS) and end it (IN_PROGRESS → COMPLETED). Only that specific Walker can advance state; no other Walker and no Owner may (PRD FR-013, FR-014, US-03, §NFR linear state machine).

Both `Walk#start!(walker)` and `Walk#complete!(walker)` exist from F-02. This change wires the HTTP layer: a new `WalkerWalksController` with index + start + complete actions, routes, a "My active walk" view, nav link, and integration tests.
