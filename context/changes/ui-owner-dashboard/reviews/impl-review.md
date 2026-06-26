<!-- IMPL-REVIEW-REPORT -->
# Implementation Review: Owner Dashboard Screens — Tailwind Styling

- **Plan**: `context/changes/ui-owner-dashboard/plan.md`
- **Scope**: All phases (1–3)
- **Date**: 2026-06-26
- **Verdict**: NEEDS ATTENTION
- **Findings**: 0 critical  2 warnings  2 observations

## Verdicts

| Dimension | Verdict |
|-----------|---------|
| Plan Adherence | PASS |
| Scope Discipline | PASS |
| Safety & Quality | WARNING |
| Architecture | PASS |
| Pattern Consistency | WARNING |
| Success Criteria | PASS |

## Findings

### F1 — Table headers missing scope="col"

- **Severity**: ⚠️ WARNING
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Safety & Quality (Accessibility)
- **Location**: `app/views/walks/index.html.erb:10–13, 51–55`
- **Detail**: All eight `<th>` cells in both tables lack `scope="col"`. Screen readers use this to associate headers with column data. U-05 will add more tables that inherit this gap if not fixed here.
- **Fix**: Add `scope="col"` to every `<th>` in both tables.
  - Strength: One-attribute addition per cell, zero visual change, makes tables WCAG 2.1 AA compliant.
  - Tradeoff: None — purely additive.
  - Confidence: HIGH — standard HTML table accessibility requirement.
  - Blind spot: None significant.
- **Decision**: FIXED — added scope="col" to all 8 <th> cells

### F2 — Submit button not in paired flex row with Cancel link

- **Severity**: ⚠️ WARNING
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Pattern Consistency
- **Location**: `app/views/dogs/_form.html.erb:22`, `app/views/dogs/edit.html.erb:7`, `app/views/dogs/new.html.erb:7`
- **Detail**: `profiles/edit.html.erb` (U-03 reference) wraps submit in `<div class="mt-4 flex items-center">` alongside an inline Cancel link. The dog form partial has a standalone `form.submit` with no wrapper and no inline Cancel; the back link lives outside the partial in the wrapper pages.
- **Fix**: Wrap `form.submit` in `<div class="mt-4 flex items-center">` with an inline `link_to "Cancel", dogs_path, class: "ml-4 text-sm text-stone-500 hover:text-stone-700"`. Remove the separate back link from `dogs/new.html.erb` and `dogs/edit.html.erb`.
  - Strength: Matches U-03 pattern exactly; Cancel sits adjacent to Submit.
  - Tradeoff: Minor — three file edits.
  - Confidence: HIGH — `profiles/edit.html.erb` is the direct precedent.
  - Blind spot: None significant.
- **Decision**: FIXED — submit wrapped in flex row with inline Cancel link in _form; back links removed from new/edit wrappers

### F3 — Multiple "Walk my dog" buttons indistinguishable to screen readers

- **Severity**: ℹ️ OBSERVATION
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Safety & Quality (Accessibility)
- **Location**: `app/views/dogs/index.html.erb:24`
- **Detail**: When an Owner has multiple dogs, N identical "Walk my dog" buttons appear with no differentiation. Screen readers hear "Walk my dog" repeated without knowing which dog each applies to.
- **Fix**: Add `aria: { label: "Walk my dog — #{dog.name}" }` to the `button_to` call.
- **Decision**: FIXED — aria-label with dog name added to button_to

### F4 — form.submit uses Rails-inferred label instead of explicit text

- **Severity**: ℹ️ OBSERVATION
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Pattern Consistency
- **Location**: `app/views/dogs/_form.html.erb:22`
- **Detail**: `profiles/edit.html.erb` passes an explicit `"Save"` label. The dog form partial uses `form.submit` with no label; Rails infers "Create Dog" on new and "Update Dog" on edit — inconsistent with the rest of the app.
- **Fix**: `<%= form.submit(@dog.persisted? ? "Save" : "Add dog"), class: "..." %>`
- **Decision**: FIXED — explicit "Add dog" / "Save" labels via @dog.persisted?
