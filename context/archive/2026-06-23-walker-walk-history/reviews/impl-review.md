<!-- IMPL-REVIEW-REPORT -->
# Implementation Review: Walker Walk History

- **Plan**: `context/changes/walker-walk-history/plan.md`
- **Scope**: Full plan (Phase 1 + Phase 2 of 2)
- **Date**: 2026-06-23
- **Verdict**: APPROVED
- **Findings**: 0 critical, 2 warnings, 4 observations

## Verdicts

| Dimension            | Verdict |
|----------------------|---------|
| Plan Adherence       | PASS    |
| Scope Discipline     | PASS    |
| Safety & Quality     | WARNING |
| Architecture         | PASS    |
| Pattern Consistency  | WARNING |
| Success Criteria     | PASS    |

## Findings

### F1 — past.owner called without nil guard (diverges from S-08 pattern)

- **Severity**: ⚠️ WARNING
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Safety & Quality
- **Location**: `app/views/walker_walks/index.html.erb:29`
- **Detail**: `past.owner.display_label` is called unconditionally. `owner` is a non-optional `belongs_to` on Walk, so it should never be nil — but S-08's equivalent (`walk.accepted_by_walker`) is guarded with `if walk.accepted_by_walker` before calling `.display_label`. A data anomaly with a null `owner_id` would raise `NoMethodError`. The controller's `includes(:dog, :owner)` prevents N+1 but does not prevent a nil crash.
- **Fix**: Wrap with `<% if past.owner %> · Walked for <%= past.owner.display_label %><% end %>` — consistent with S-08's defensive pattern.
- **Decision**: FIXED — nil guard added: `<% if past.owner %> · Walked for …<% end %>`

### F2 — Missing section-placement assertion in "completed walk" test

- **Severity**: ⚠️ WARNING
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Pattern Consistency
- **Location**: `test/integration/walker_walks_test.rb:82-92` (missing assertions)
- **Detail**: The "completed walk appears in walker's past walk history" test asserts "Rex" and "Completed" appear in the body and "No past walks yet." is absent — but does not verify the completed walk is NOT in the active section. A regression moving completed walks into `@walk` (showing Start/End buttons) would pass this test.
- **Fix**: Add `assert_not_includes response.body, "Start walk"` and `assert_not_includes response.body, "End walk"` to confirm the completed walk did not bleed into the active area.
- **Decision**: FIXED — assert_not_includes "Start walk" and "End walk" added to completed walk test

### F3 — Blank timestamp span for non-completed past walks

- **Severity**: 👁️ OBSERVATION
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Safety & Quality
- **Location**: `app/views/walker_walks/index.html.erb:26-29`
- **Detail**: `@past_walks` excludes only `accepted` and `in_progress` states — so `cancelled` walks could appear (if a Walker's accepted walk was somehow cancelled, e.g. via a future admin operation). `completed_at&.to_fs(:short)` nil-guards correctly so no crash, but renders a blank `<span></span>`. S-08 branches on `walk.completed?` vs `walk.cancelled?` to show the right timestamp. In v1 walkers can't cancel walks, so the impact is theoretical.
- **Fix**: Add `elsif past.cancelled?` branch showing `past.cancelled_at&.to_fs(:short)` — consistent with S-08 and future-proof.
- **Decision**: FIXED — added elsif past.cancelled? branch showing cancelled_at

### F4 — Negative state exclusion instead of positive allowlist

- **Severity**: 👁️ OBSERVATION
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Data Safety
- **Location**: `app/controllers/walker_walks_controller.rb:15-19`
- **Detail**: `@past_walks` uses `.where.not(state: %w[accepted in_progress])` instead of `.where(state: %w[completed cancelled])` (S-08's positive allowlist). A future new state would automatically flow into walker history without a deliberate decision. The state machine prevents a walk having `accepted_by_walker_id` set while in `requested` state, so the practical risk is low, but the positive allowlist is self-documenting and defensive.
- **Fix**: Change to `.where(accepted_by_walker_id: current_user.id, state: %w[completed cancelled])`.
- **Decision**: FIXED — changed to .where(state: %w[completed cancelled]) positive allowlist

### F5 — update_columns bypasses state machine in test setup

- **Severity**: 👁️ OBSERVATION
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Pattern Consistency
- **Location**: `test/integration/walker_walks_test.rb:29`
- **Detail**: `@walk.update_columns(state: "completed", completed_at: Time.current)` bypasses `complete!` and skips `start!` (which sets `started_at`). The rest of the test file uses proper transition chains (`start!` → `complete!`). Inconsistent setup risks masking bugs if `complete!` ever requires a prior state check.
- **Fix**: Replace with `@walk.start!(@walker); @walk.complete!(@walker)` to match lines 83-84 and the established pattern.
- **Decision**: FIXED — replaced update_columns with start!(@walker); complete!(@walker)

### F6 — View copy: "· Walked for" vs plan's "Walked for:"

- **Severity**: 👁️ OBSERVATION
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Plan Adherence
- **Location**: `app/views/walker_walks/index.html.erb:29`
- **Detail**: The plan contract specified `"Walked for: owner.display_label"` (colon after "for"). Implementation renders `· Walked for <%= past.owner.display_label %>` (middle-dot separator, no colon). Purely cosmetic — no functional impact.
- **Fix**: Accept as-is (middle-dot is arguably better UX) or add colon to match plan literally.
- **Decision**: ACCEPTED — middle-dot separator is visually cleaner; kept as-is
