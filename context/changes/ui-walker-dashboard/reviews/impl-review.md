<!-- IMPL-REVIEW-REPORT -->
# Implementation Review: Walker Dashboard Screens — Tailwind Styling

- **Plan**: `context/changes/ui-walker-dashboard/plan.md`
- **Scope**: All phases (1–3 of 3)
- **Date**: 2026-06-29
- **Verdict**: APPROVED
- **Findings**: 0 critical  1 warning  4 observations

## Verdicts

| Dimension | Verdict |
|---|---|
| Plan Adherence | PASS |
| Scope Discipline | PASS |
| Safety & Quality | PASS |
| Architecture | PASS |
| Pattern Consistency | WARNING |
| Success Criteria | PASS |

## Findings

### F1 — `<th>` elements missing `scope="col"`

- **Severity**: ⚠️ WARNING
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Pattern Consistency
- **Location**: `app/views/walker_walks/index.html.erb:37–40`
- **Detail**: All four `<th>` elements in the walk-history table lack `scope="col"`. The direct sibling `walks/index.html.erb` applies `scope="col"` to every `<th>` in both its tables. This breaks the established pattern and is a minor accessibility gap (screen readers use scope to associate headers with data cells).
- **Fix**: Add `scope="col"` to each of the four `<th>` elements (Dog, State, Date, Owner).
- **Decision**: FIXED — added `scope="col"` to all four `<th>` elements

### F2 — `display_label` can expose owner's raw email address

- **Severity**: 👁 OBSERVATION
- **Impact**: 🔎 MEDIUM — real tradeoff; pause to reason through it
- **Dimension**: Safety & Quality
- **Location**: `app/views/walker_walks/index.html.erb:59`
- **Detail**: `past.owner&.display_label` falls back to the owner's raw email when they have no display name. The PRD §Access Control does not explicitly grant Walkers email access to Owners — only dog name and city (FR-011). Acceptable for a two-test-user MVP; less acceptable at broader launch.
- **Fix A ⭐ Recommended**: Keep as-is; accept as a known v1 limitation consistent with PRD §Open Questions trust gap deferral.
  - Strength: Consistent with PRD's explicit deferral of trust/verification work.
  - Tradeoff: Owner email readable by any Walker who accepted their walk.
  - Confidence: HIGH — PRD explicitly defers trust/verification.
  - Blind spot: Whether team treats email exposure as within or outside the "trust gap".
- **Fix B**: Truncate to display_name only; show "Anonymous" fallback in the Walker view.
  - Strength: Removes email exposure without hiding the owner context.
  - Tradeoff: Adds a view-layer conditional or helper.
  - Confidence: MED — no display_name-only precedent yet.
  - Blind spot: display_name may also be unset for new users.
- **Decision**: ACCEPTED — known v1 limitation per PRD §Open Questions trust gap deferral

### F3 — Active-walk card ring deviation not documented

- **Severity**: 👁 OBSERVATION
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Pattern Consistency
- **Location**: `app/views/walker_walks/index.html.erb:5`
- **Detail**: Active-walk card uses `ring-2 ring-primary-300` — intentionally bolder than `ring-1 ring-stone-200` on every other card. Sound design intent but undocumented; a future maintainer could normalise it to match siblings and lose the visual emphasis.
- **Fix**: Add `<%# ring-2 ring-primary-300: intentional — signals active walk obligation %>` above the card div.
- **Decision**: FIXED — added ERB comment above the active walk card div

### F4 — Extra `text-sm` on empty-state link (minor plan drift)

- **Severity**: 👁 OBSERVATION
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Plan Adherence
- **Location**: `app/views/walker_walks/index.html.erb:26`
- **Detail**: Empty-state link has `text-sm` beyond the plan contract. History empty-state `<td>` also has `px-4` beyond contracted `py-4`. Both are cosmetically consistent with the design system — no action required; noted for future plan precision.
- **Fix**: No code change needed. Mention in the next plan that `text-sm` should be explicit in link contracts.
- **Decision**: SKIPPED — cosmetically consistent; noted for future plan precision
