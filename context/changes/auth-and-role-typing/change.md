---
change_id: auth-and-role-typing
title: Rails 8 auth + role-typed accounts (F-01 foundation)
status: impl_reviewed
created: 2026-05-29
updated: 2026-06-01
archived_at: null
---

## Notes

Roadmap item **F-01** (`context/foundation/roadmap.md`) — first foundation on the critical path; prerequisite for S-01 and transitively every other slice.

Outcome: `User` model with bcrypt-hashed password, a sessions controller for sign-up/sign-in/sign-out, and a binding `role` column (Owner XOR Walker, chosen at registration). Internal hooks `current_user` / `require_authentication` available. PRD refs: FR-001..004, §Access Control (Role → capability matrix). Role typing decision (enum vs typed column) is load-bearing — dual-role is explicitly out of scope, so a simple string-backed `enum role: { owner: "owner", walker: "walker" }` suffices.
