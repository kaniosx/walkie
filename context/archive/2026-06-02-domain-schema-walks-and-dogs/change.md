---
change_id: domain-schema-walks-and-dogs
title: Domain data schema — Dog + Walk + state machine + DB-level invariants
status: archived
created: 2026-06-02
updated: 2026-06-15
archived_at: 2026-06-15T12:49:11Z
---

## Notes

Roadmap F-02 (foundation). Prereq F-01 (`auth-and-role-typing`) is complete.

Scope (from `context/foundation/roadmap.md` §F-02):
- `dogs` table — belongs_to User, basic fields.
- `walks` table — belongs_to Dog, `state` enum REQUESTED/ACCEPTED/IN_PROGRESS/COMPLETED, nullable `accepted_by_walker_id`.
- DB-level constraints (binding outside the UI, not advisory): check on linear state progression, partial unique index enforcing Singleness (one Walker per Walk once it leaves REQUESTED), foreign keys.
- Active Record validations + a transactional, test-able state-transition method.

Load-bearing risk: the Singleness invariant must be enforced **in the DB**, not only in AR (PRD §Guardrails). Integer enum for `state` (cheaper to index). A concurrency test inside F-02 is the backstop S-05 relies on.

Open decision touching this schema: Open Q #4 (dog removal policy) drives FK behavior — `RESTRICT` vs `NULLIFY` vs soft-delete. Roadmap recommends soft-delete as default since it closes no options. Resolve or default before finalizing.

PRD refs: §Business Logic (Singleness, Locality, Immediacy), §NFR, FR-009..FR-014.
