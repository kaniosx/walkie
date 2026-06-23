<!-- IMPL-REVIEW-REPORT -->
# Implementation Review: Owner Walk History

- **Plan**: `context/changes/owner-walk-history/plan.md`
- **Scope**: Full plan (Phase 1 + Phase 2 of 2)
- **Date**: 2026-06-23
- **Verdict**: NEEDS ATTENTION
- **Findings**: 0 critical, 5 warnings, 1 observation

## Verdicts

| Dimension            | Verdict |
|----------------------|---------|
| Plan Adherence       | WARNING |
| Scope Discipline     | WARNING |
| Safety & Quality     | WARNING |
| Architecture         | PASS    |
| Pattern Consistency  | WARNING |
| Success Criteria     | PASS    |

## Findings

### F1 — completed_at / cancelled_at not nil-guarded in view

- **Severity**: ⚠️ WARNING
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Safety & Quality
- **Location**: `app/views/walks/index.html.erb:31,36`
- **Detail**: `walk.completed_at.to_fs(:short)` and `walk.cancelled_at.to_fs(:short)` are called without nil guards. Both columns are set by `update_all` inside `complete!`/`cancel!` which bypasses AR callbacks — if a walk ever reaches `completed` or `cancelled` state without the timestamp (data repair, test fixture, direct DB write), this raises `NoMethodError: undefined method 'to_fs' for nil`.
- **Fix**: Add safe navigation: `walk.completed_at&.to_fs(:short)` and `walk.cancelled_at&.to_fs(:short)`.
- **Decision**: FIXED — added &. safe navigation to completed_at and cancelled_at in view

### F2 — Unbounded @past_walks query

- **Severity**: ⚠️ WARNING
- **Impact**: 🔎 MEDIUM — real tradeoff; pause to reason through it
- **Dimension**: Safety & Quality
- **Location**: `app/controllers/walks_controller.rb:6-9`
- **Detail**: `@past_walks` loads all completed + cancelled walks for the owner with no LIMIT. A power user with many completed walks will load all rows and their `:accepted_by_walker` associations in a single request. The plan explicitly notes "No pagination (walk counts are small in v1)" — but no comment documents this as an accepted limitation.
- **Fix A ⭐ Recommended**: Add a comment noting the deliberate no-pagination decision and that a limit should be added before real-user launch.
  - Strength: Zero behavior change; makes the deliberate choice visible to future contributors.
  - Tradeoff: A data anomaly still loads unbounded rows — acceptable for v1.
  - Confidence: HIGH — plan explicitly defers pagination.
  - Blind spot: Render time is not tested under load.
- **Fix B**: Add `.limit(50)` to the `@past_walks` query.
  - Strength: Bounds the query for any realistic v1 data volume.
  - Tradeoff: Owner silently loses access to walks older than position 50; UI gives no indication of truncation.
  - Confidence: MED — a hard limit without pagination UX is a worse UX failure than a slow page.
  - Blind spot: 50 is arbitrary.
- **Decision**: FIXED via Fix B — .limit(50) added to @past_walks query

### F3 — Tests don't verify Active vs Past section placement

- **Severity**: ⚠️ WARNING
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Plan Adherence
- **Location**: `test/integration/walks_test.rb` (missing assertions)
- **Detail**: The plan contract required asserting which section each walk appears in. The implementation tests verify that "Cancelled" / "Completed" appear in the response body, but do not verify they appear under the "Past" heading rather than "Active". A regression that moved a completed walk to the Active section would not be caught.
- **Fix**: In `"cancelled walk appears in the walk index"` and `"completed walk appears in the walk index"`, add `assert_not_includes response.body, "No past walks yet."` and optionally assert the ordering of "Past" before the walk name using regex or string position.
- **Decision**: FIXED — section placement assertions added to cancelled + completed tests

### F4 — Missing cross-owner isolation test for @past_walks

- **Severity**: ⚠️ WARNING
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Pattern Consistency / Safety & Quality
- **Location**: `test/integration/walks_test.rb` (missing test)
- **Detail**: The existing "index lists only the current owner's walks" test creates walks in REQUESTED state. The `@past_walks` query is a separate DB query — cross-owner isolation is enforced there too (via `current_user.owned_walks`) but this is not tested. PRD §NFR "role separation never leaks" requires verifying isolation for every data query, including past walks.
- **Fix**: Add a test that transitions `@other_owner`'s walk to `completed`, signs in as `@owner`, and asserts `assert_not_includes response.body, "Fido"` (other owner's dog name must not appear even as a past walk).
- **Decision**: FIXED — past walks cross-owner isolation test added

### F5 — Missing: walker blocked from GET walks_path index

- **Severity**: ⚠️ WARNING
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Pattern Consistency
- **Location**: `test/integration/walks_test.rb` (missing test)
- **Detail**: The test covers walker attempting `POST walks_path` (create) → redirected by OwnerOnly. There is no test for `GET walks_path` (index) by a walker. The reference pattern in `walker_walks_test.rb:68-73` explicitly tests role-gate for the index action.
- **Fix**: Add `test "a walker cannot access the walk index: redirected by OwnerOnly"` — `sign_in_as "walker@example.com"` → `get walks_path` → `assert_redirected_to root_path` + `assert_equal "Only Owners can do that.", flash[:alert]`.
- **Decision**: FIXED — walker-blocked-from-index test added

### F6 — View renders dog.breed not in plan contract

- **Severity**: 👁️ OBSERVATION
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Scope Discipline
- **Location**: `app/views/walks/index.html.erb:9,22`
- **Detail**: Both Active and Past sections render `walk.dog.breed` in parentheses. The plan contract specified dog name and state/timestamps only. Already eagerly loaded (no N+1), harmless content.
- **Fix**: Accept as-is (breed is contextually useful) or remove to stay on plan contract.
- **Decision**: ACCEPTED — breed is useful context; kept as-is
