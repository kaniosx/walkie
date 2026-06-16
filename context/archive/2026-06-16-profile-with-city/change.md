---
change_id: profile-with-city
title: User profile with city/postcode (S-02)
status: archived
created: 2026-06-16
updated: 2026-06-16
archived_at: 2026-06-16T07:31:30Z
---

## Notes

Roadmap item **S-02** (`context/foundation/roadmap.md`) — second user-visible slice; prerequisite for S-04 (owner creates walk request) which copies the owner's city/postcode onto the walk.

Outcome: A signed-in user (Owner or Walker) can view and edit their profile — display name (optional) + city/postcode (required). Per the planning interview, city/postcode are collected at sign-up and stored `NOT NULL`, so every user always has a locality (no point-of-use guard needed in S-04/S-05). display_name is optional and falls back to email where a name is shown. PRD refs: FR-005, §Business Logic §Locality, §Open Q #6 (coarse city/postcode, accepted v1 limitation).
