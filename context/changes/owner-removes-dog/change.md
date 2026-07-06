---
id: owner-removes-dog
title: "Owner removes their own dog (soft-delete)"
status: impl_reviewed
created: 2026-07-06
updated: 2026-07-06
roadmap_id: S-10
prd_refs: FR-008
---

Owner can deactivate their dog via a "Remove" button. Dog record is soft-deleted
(`deactivated_at` timestamp); walk history for both sides is preserved. If the dog
has any active walk (REQUESTED / ACCEPTED / IN_PROGRESS), removal is blocked until
the walk completes or is cancelled.

Model infrastructure (deactivated_at column, Dog.active scope, deactivate! method)
was implemented during F-02 / S-03. This slice wires the controller action, route,
view, and integration tests.
