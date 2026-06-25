---
change_id: testing-http-guardrails
title: HTTP contract guardrails — Singleness, cross-account isolation, and IDOR 404
status: impl_reviewed
created: 2026-06-25
updated: 2026-06-25
archived_at: null
---

## Notes

Open a change folder for rollout Phase 1 of context/foundation/test-plan.md:
"HTTP guardrails".
Risks covered: #1 (Singleness HTTP contract), #3 (cross-account data isolation),
#4 (IDOR 404 contract).
Test types planned: integration.
Risk response intent:
- Risk #1: prove POST accept on an already-ACCEPTED walk → user-visible rejection
  (flash/alert rendered) and walk state + accepted_by_walker_id unchanged; challenge
  assumption that the model-level concurrency test covers the HTTP contract.
- Risk #3: prove Owner B GETs /walks → zero rows from Owner A; Walker B GETs
  /walker_walks → zero rows from Walker A; only absence of wrong user's rows
  proves isolation.
- Risk #4: prove Walker B POSTs start/complete on Walker A's walk → HTTP 404
  specifically and walk state unchanged; challenge "model guard makes HTTP test
  redundant" — the 404 is the client-visible security contract.
