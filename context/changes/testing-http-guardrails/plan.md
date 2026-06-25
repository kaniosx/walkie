# HTTP Guardrails — Phase 1 Implementation Plan

## Overview

Close the one remaining coverage gap from the Phase 1 HTTP guardrails audit: a missing
integration test that proves Walker B's active-walk section does not reveal Walker A's
accepted walk. Then document the integration-test conventions in §6.1 of the rollout
cookbook and mark §3 Phase 1 complete.

Risks #1 (Singleness HTTP contract) and #4 (IDOR 404) are **already fully covered** by
existing tests. This plan adds no redundant tests for those risks.

## Current State Analysis

Research (`context/changes/testing-http-guardrails/research.md`) audited all three Phase 1
risks against the actual controller and test code:

| Risk | Status before this plan |
|------|------------------------|
| #1 Singleness HTTP contract | Covered — `open_requests_test.rb:55-67` |
| #3 Cross-account isolation | Partly covered — Owner both sections ✓; Walker past section ✓; Walker **active** section ✗ |
| #4 IDOR 404 | Covered — `walker_walks_test.rb:63-67` and `:76-81` |

The gap: no test signs in as Walker2 and asserts Walker1's accepted walk is absent from the
`/walker_walks` active section while Walker1 has that walk.

`WalkerWalksController` queries: `Walk.where(accepted_by_walker_id: current_user.id, state:
%w[accepted in_progress]).first`. Walker2 has no accepted walk, so the query returns `nil`.
But no integration test verifies this by asserting absence from Walker2's perspective.

§6.1 of `test-plan.md` currently holds a TBD placeholder pointing to Phase 1.

## Desired End State

After this plan:
1. `test/integration/walker_walks_test.rb` contains a test asserting Walker2 cannot see
   Walker1's active walk in the active section.
2. Running `docker compose exec web bin/rails test test/integration/walker_walks_test.rb`
   passes with all existing tests plus the new case.
3. `context/foundation/test-plan.md` §6.1 contains a pattern-focused cookbook entry (8–15
   lines) covering the integration test conventions.
4. §3 Phase 1 row is marked `complete`.

### Key Discoveries

- `walker_walks_test.rb` already has `@walker` and `@walker2` in setup with `@walk` accepted
  by `@walker` — the new test needs zero additional fixture setup. (`research.md` §Risk #3)
- The assertion string should be `"Rex"` — the dog name the view renders for an active walk,
  confirmed by the existing test at `walker_walks_test.rb:20-26`.
- `assert_response :success` guards against a redirect masking the assertion failure.
- State-unchanged assertions after a 404 are vacuous: `RecordNotFound` is raised before any
  mutation executes. The existing 404 tests correctly omit them. (`research.md` §Risk #4)
- The `WalkerWalksController` `start`/`complete` false-return `else` branch is a race path,
  not a sequential illegal-transition path — relevant for Phase 2 research, not this plan.
  (`research.md` §Architecture Insights)

## What We're NOT Doing

- Not adding tests for Risk #1 or Risk #4 — existing tests already prove those contracts.
- Not adding `walk.reload; assert walk.state` assertions after 404 responses — they are
  vacuous because the controller never executes past a `RecordNotFound` raise.
- Not changing any controller, model, route, or migration — this plan is tests + docs only.
- Not addressing Phase 2 (state machine feedback) or Phase 3 (coverage gate) — those are
  separate rollout phases.

## Implementation Approach

Add the single missing test case immediately below the existing walker past-section isolation
test in `walker_walks_test.rb`, mirroring its structure (sign in as walker2, GET the index,
assert absence). Then update the cookbook and status table.

---

## Phase 1: Add Walker Active-Section Isolation Test

### Overview

Add the one test case that proves Walker2's `/walker_walks` active section does not display
Walker1's accepted walk, closing the Risk #3 coverage gap.

### Changes Required

#### 1. Add test to `test/integration/walker_walks_test.rb`

**File**: `test/integration/walker_walks_test.rb`

**Intent**: Add a test immediately after the existing "walker cannot see another walker's
completed walk in history" test (line 105). The new test proves the active section is
also isolated: Walker2, who has never accepted a walk, should see no active walk in their
`/walker_walks` page while Walker1 has one.

**Contract**: New test case in `WalkerWalksTest`. Uses the existing `setup` as-is (`@walk`
is accepted by `@walker`, `@walker2` exists). Sign in as `walker2@example.com`, GET
`walker_walks_path`, `assert_response :success`, `assert_not_includes response.body, "Rex"`.
No inline fixture setup needed; no new users or walks created inside the test.

### Success Criteria

#### Automated Verification

- `docker compose exec web bin/rails test test/integration/walker_walks_test.rb` — full file
  passes (all existing tests plus the new case green)

#### Manual Verification

- Read the new test: confirm it depends only on the existing `setup` block and adds no
  redundant fixture creation
- Confirm the assertion string `"Rex"` matches what the view renders for an active walk
  (same string used in `walker_walks_test.rb:24`)

**Implementation Note**: Pause after this phase. Confirm the suite output shows the new test
name and green status before proceeding to Phase 2.

---

## Phase 2: Update Cookbook and Close Phase 1

### Overview

Replace the §6.1 TBD placeholder with the integration-test cookbook pattern, then mark
§3 Phase 1 as `complete` and advance the change status.

### Changes Required

#### 1. Update `context/foundation/test-plan.md` §6.1

**File**: `context/foundation/test-plan.md`

**Intent**: Replace the placeholder in §6.1 with a pattern-focused entry that gives a future
agent or developer enough to write a new integration test correctly without reading the
existing test files first.

**Contract**: Replace the single-line TBD under `### 6.1 Adding an integration test
(HTTP-layer contract)` with an 8–15 line entry covering:
- Test class: `ActionDispatch::IntegrationTest`
- Sign-in helper pattern (POST to `session_path`)
- Why fixtures are inline (not YAML): `has_secure_password` needs real passwords
- Three core assertion patterns:
  - `assert_not_includes response.body, "name"` for absence (cross-account isolation)
  - `assert_response :not_found` for IDOR 404 contracts
  - `follow_redirect!` then body check for flash content after redirects
- Canonical reference tests for each pattern (file:line citations)

#### 2. Update §3 Phase 1 row in `context/foundation/test-plan.md`

**File**: `context/foundation/test-plan.md`

**Intent**: Record Phase 1 as complete in the rollout status table.

**Contract**: In the `## 3. Phased Rollout` table, update the Phase 1 row:
- Status cell: `change opened` → `complete`
- Change folder cell already reads `context/changes/testing-http-guardrails/` — no change

#### 3. Advance `context/changes/testing-http-guardrails/change.md`

**File**: `context/changes/testing-http-guardrails/change.md`

**Intent**: Record that the change has shipped.

**Contract**: Set `status: complete` and `updated: 2026-06-25`.

### Success Criteria

#### Automated Verification

- `grep -c 'ActionDispatch::IntegrationTest' context/foundation/test-plan.md` — returns ≥ 1
  (cookbook entry landed)
- `grep 'HTTP guardrails' context/foundation/test-plan.md | grep 'complete'` — Phase 1 row
  shows `complete`

#### Manual Verification

- Read §6.1: confirm the three assertion patterns are named and reference tests are cited;
  a future agent reading only §6.1 can start writing a new integration test without opening
  any test file

---

## Testing Strategy

### Automated Tests

- All existing tests in `walker_walks_test.rb` continue to pass (non-regression)
- New test: "walker cannot see another walker's accepted walk in active section" — passes

### Manual Testing Steps

1. After Phase 1: read the full `walker_walks_test.rb` output from `bin/rails test` to
   confirm the new test name appears and is green
2. After Phase 2: read §6.1 aloud as if you were a new agent starting a fresh session —
   does it tell you enough to write `assert_not_includes response.body, "Rex"` in the right
   file with the right setup?

## References

- Research: `context/changes/testing-http-guardrails/research.md`
- Test-plan rollout: `context/foundation/test-plan.md` §3
- Walker isolation pattern: `test/integration/walker_walks_test.rb:105-113`
- Owner isolation pattern: `test/integration/walks_test.rb:33-43`

---

## Progress

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles. See `references/progress-format.md`.

### Phase 1: Add Walker Active-Section Isolation Test

#### Automated

- [x] 1.1 `docker compose exec web bin/rails test test/integration/walker_walks_test.rb` passes (all tests including new case) — b79a437

#### Manual

- [x] 1.2 New test uses only existing setup — no redundant fixture creation inside the test body — b79a437
- [x] 1.3 Assertion string `"Rex"` confirmed to match what the view renders for an active walk — b79a437

### Phase 2: Update Cookbook and Close Phase 1

#### Automated

- [x] 2.1 `grep -c 'ActionDispatch::IntegrationTest' context/foundation/test-plan.md` returns ≥ 1
- [x] 2.2 Phase 1 row in §3 shows `complete`

#### Manual

- [x] 2.3 §6.1 gives a future agent enough to write a new integration test without opening any source test file
