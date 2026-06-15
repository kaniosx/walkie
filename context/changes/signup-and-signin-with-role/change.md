---
change_id: signup-and-signin-with-role
title: Sign-up + sign-in with role choice (S-01)
status: implemented
created: 2026-06-15
updated: 2026-06-15
---

## Notes

Roadmap item **S-01** (`context/foundation/roadmap.md`) — first user-visible slice; prerequisite for S-02, S-03, and transitively every other slice.

Outcome: A visitor can sign up as an Owner or Walker (email + password, role chosen at sign-up), sign in, and sign out — with a presentable UI. The auth machinery was built in F-01; this slice adds layout polish, a persistent nav bar, proper flash rendering, improved role-radio copy, a role-aware home page, and integration tests for the UX layer. PRD refs: FR-001, FR-002, FR-003, FR-004, §Access Control.
