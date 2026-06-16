---
change_id: owner-manages-dog
title: Owner adds + edits their own dog (S-03)
status: implementing
created: 2026-06-16
updated: 2026-06-16
---

## Notes

Roadmap item **S-03** (`context/foundation/roadmap.md`) — Owner-side journey (stream B); prerequisite for S-04 (owner creates a walk request, which requires a dog to walk).

Outcome: A signed-in Owner can add a dog (name + breed required, weight in kg + notes optional) and edit it. Management is Owner-only (Access Control matrix) and scoped to the owner's own dogs. Deliberately **add + edit only** — remove is S-10 (blocked on Open Q #4). PRD refs: FR-006, FR-007, US-01 ("Owner with at least one dog"). The `Dog` model + soft-delete already exist from F-02; this slice adds the remaining fields, the owner-scoped CRUD, and the UI.
