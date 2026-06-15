---
change_id: test-infrastructure-scaffold
title: Test infrastructure scaffold — Minitest baseline + coverage tooling
status: archived
created: 2026-06-02
updated: 2026-06-15
archived_at: 2026-06-15T12:49:11Z
---

## Notes

Roadmap F-03 (foundation). Prerequisites: — (parallel with F-01, which is already complete; `test/` now exists as a side effect of F-01's `bin/rails g authentication`).

Scope (from `context/foundation/roadmap.md` §F-03):
- `test/` directory exists (Minitest) with `test/test_helper.rb` configured. **F-01 already created this** — F-03 formalizes/standardizes it rather than scaffolding from zero.
- A coverage tool (e.g. SimpleCov) installed and reporting against the four core flows.
- CI placeholder — runs tests + the coverage gate on push (Auto-Deploy stays off pending a separate decision).

PRD refs: §Success Criteria §Guardrails — ≥80% coverage on the 4 core flows (create request, accept request, start walk, complete walk), with unit/integration tests on the most important business cases.

Open Unknown (does NOT block work): wire CI now (GitHub Actions, Ruby 3.4.9 + Postgres 17) or only the local-test loop? Owner: user. Roadmap notes CI can be deferred; local tests are enough for skill-level v1 validation. Decide at `/10x-plan` time.

Risk / nuance: F-01 already generated `test/` and wrote model + integration tests *without* SimpleCov. F-03 must bolt coverage onto the existing suite (the tripwire it was meant to pre-empt has partially already happened) and reconcile the ≥80% gate against what F-01/F-02 already cover.
