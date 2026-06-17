---
change_id: walker-accepts-request
title: Walker accepts an open request (S-05, north star)
status: implementing
created: 2026-06-17
updated: 2026-06-17
---

## Notes

Roadmap item **S-05** (`context/foundation/roadmap.md`) — the **north star**. The slice that puts the PRD's core hypothesis ("the gap is the 'available right now' signal") in front of real users: the validation milestone lands at the first real-user acceptance.

Outcome: A signed-in Walker sees the REQUESTED walk requests filtered to their city + postcode (dog + breed + locality, no owner identity) and taps "Accept" → REQUESTED → ACCEPTED, bound to them; the request drops off every other walker's list. Exactly one walker can win a concurrent accept. PRD refs: FR-011, FR-012, US-02, §Business Logic §Singleness, §Guardrails (single-Walker race; role separation never leaks). The atomic `Walk#accept!` + DB `walks_walker_presence` CHECK + thread-race test already exist from F-02; this slice wires the walker-facing flow and verifies the outcome at the HTTP layer.
