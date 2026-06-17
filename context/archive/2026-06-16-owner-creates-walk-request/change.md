---
change_id: owner-creates-walk-request
title: Owner creates a walk request (S-04)
status: archived
created: 2026-06-16
updated: 2026-06-17
archived_at: 2026-06-17T13:37:44Z
---

## Notes

Roadmap item **S-04** (`context/foundation/roadmap.md`) — Owner-side journey (stream B); the request that S-05 (walker accepts) consumes. Joins the marketplace-binding stream.

Outcome: An Owner with a dog taps "Walk my dog" (on home or /dogs) and creates a walk request in REQUESTED state; the walk's city/postcode are copied from the owner's profile; the request appears in a minimal "My walk requests" list. One active request per dog. PRD refs: FR-009, US-01, §Business Logic §Locality. The Walk model, state machine, and DB constraints already exist from F-02 — this slice is the owner-side creation flow + a minimal listing.
