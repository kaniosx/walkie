---
change_id: geolocation-matching
title: Locality matching precision (city/postcode → geolocation radius)
status: archived
created: 2026-09-02
updated: 2026-09-02
archived_at: 2026-09-02T14:20:32Z
---

## Notes

Opened via `/10x-frame` to challenge the framing behind a proposal to replace
`Walk.open_in_locality`'s exact city+postcode match with geolocation-radius
matching. Frame brief (`frame.md`) reframed the problem as timing/precedent,
not matching precision — user reviewed it and chose to proceed anyway.
`/10x-plan` then produced a 5-phase implementation plan (`plan.md`,
`plan-brief.md`): postcode removal, radius-query foundation, Owner-side
capture, Walker-side radius list, per-Walker live broadcast.
