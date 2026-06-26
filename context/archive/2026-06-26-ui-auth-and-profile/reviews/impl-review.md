<!-- IMPL-REVIEW-REPORT -->
# Implementation Review: Auth + Profile Screens — Tailwind Styling

- **Plan**: `context/changes/ui-auth-and-profile/plan.md`
- **Scope**: All phases (1–3)
- **Date**: 2026-06-26
- **Verdict**: NEEDS ATTENTION
- **Findings**: 0 critical | 2 warnings | 3 observations

## Verdicts

| Dimension | Verdict |
|-----------|---------|
| Plan Adherence | PASS |
| Scope Discipline | WARNING |
| Safety & Quality | WARNING |
| Architecture | PASS |
| Pattern Consistency | WARNING |
| Success Criteria | PASS |

## Findings

### F1 — registrations/new pre-populates from params instead of @user

- **Severity**: ⚠️ WARNING
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Safety & Quality / Pattern Consistency
- **Location**: app/views/registrations/new.html.erb:16,23,25
- **Detail**: city, postcode, and email_address repopulate from `params[]` — `value: params[:email_address]`, `value: params[:city]`, `value: params[:postcode]`. RegistrationsController#create already sets `@user = User.new(registration_params)`, so `@user.city` etc. hold the submitted values on re-render. `profiles/edit.html.erb` (same change) correctly uses `value: @user.city` throughout. If the controller ever re-renders without going through params, fields appear blank.
- **Fix**: Replace `value: params[:email_address]` → `value: @user.email_address`, `value: params[:city]` → `value: @user.city`, `value: params[:postcode]` → `value: @user.postcode`, `checked: params[:role] == "owner"` → `checked: @user.role == "owner"` (same for "walker"). Matches profiles/edit and the idiomatic Rails pattern.
- **Decision**: FIXED — replaced params[] with @user.* throughout, radio checked: uses @user.role

### F2 — profiles/show role.capitalize raises on nil

- **Severity**: ⚠️ WARNING
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Safety & Quality
- **Location**: app/views/profiles/show.html.erb:15
- **Detail**: `@user.role.capitalize` — if role is ever nil (legacy row, future schema change, test fixture), raises NoMethodError and produces a 500. The model has a presence validation, but view-layer nil guards are cheap insurance.
- **Fix**: `@user.role&.capitalize || "—"`
- **Decision**: FIXED — @user.role&.capitalize || "—"

### F3 — application.html.erb modified without plan entry

- **Severity**: 👁️ OBSERVATION
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Scope Discipline
- **Location**: app/views/layouts/application.html.erb:27
- **Detail**: Added `class="bg-stone-50 min-h-screen"` to `<body>` — not in the plan. Change is correct and load-bearing (white card on white body was visually invisible). Plan should have anticipated it.
- **Fix**: No code change needed — benign and correct. Plan is already closed.
- **Decision**: SKIPPED — benign and load-bearing; plan already closed

### F4 — profiles/edit submit button deviates from canonical class set

- **Severity**: 👁️ OBSERVATION
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Plan Adherence
- **Location**: app/views/profiles/edit.html.erb:29
- **Detail**: Submit missing `mt-4` and `w-full` vs. canonical set. Correct adaptation — `mt-4` moved to flex wrapper div, `w-full` would break the inline Submit+Cancel layout. Plan spec was self-contradictory (flex row + w-full don't mix). Implementation resolved it correctly.
- **Fix**: No change needed. Plan inconsistency, not an implementation error.
- **Decision**: SKIPPED — plan inconsistency resolved correctly in implementation

### F5 — radio labels use raw `<label>` instead of form.label

- **Severity**: 👁️ OBSERVATION
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Pattern Consistency
- **Location**: app/views/registrations/new.html.erb:39–46
- **Detail**: Radio button wrappers use raw `<label class="flex items-center ...">` rather than `form.label :role, value: "owner" do ... end`. Rest of the form uses `form.label` consistently. Functionally equivalent; minor style inconsistency.
- **Fix**: Refactor to `form.label :role, value: "owner" do ... end` blocks.
- **Decision**: FIXED — refactored to form.label :role, value: ... do ... end blocks
