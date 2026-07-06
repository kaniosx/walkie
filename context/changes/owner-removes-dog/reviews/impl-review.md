<!-- IMPL-REVIEW-REPORT -->
# Implementation Review: Owner removes their own dog (soft-delete)

- **Plan**: context/changes/owner-removes-dog/plan.md
- **Scope**: All phases (1–3 of 3)
- **Date**: 2026-07-06
- **Verdict**: NEEDS ATTENTION
- **Findings**: 0 critical | 2 warnings | 3 observations

## Verdicts

| Dimension | Verdict |
|-----------|---------|
| Plan Adherence | PASS |
| Scope Discipline | WARNING |
| Safety & Quality | WARNING |
| Architecture | PASS |
| Pattern Consistency | PASS |
| Success Criteria | PASS |

## Findings

### F1 — TOCTOU race between guard check and deactivate!

- **Severity**: ⚠️ WARNING
- **Impact**: 🔎 MEDIUM — real tradeoff; pause to reason through it
- **Dimension**: Safety & Quality
- **Location**: app/controllers/dogs_controller.rb:35-41
- **Detail**: The `@dog.walks.active.exists?` check and `@dog.deactivate!` ran as two separate DB round-trips with no transaction or lock between them. A concurrent WalksController#create for the same dog could insert a REQUESTED walk after the guard passed and before the deactivation landed. Result: a deactivated dog with a live walk the owner can no longer cancel.
- **Fix Applied**: Pessimistic lock inside a `Dog.transaction` block returning `:blocked` or `:ok`. `@dog.lock!` (SELECT FOR UPDATE) serialises concurrent writes to this dog row. Block-return pattern avoids the Ruby non-local-return gotcha with Rails transaction blocks.
- **Decision**: FIXED via Fix A

### F2 — Missing index-visibility assertion after deactivation

- **Severity**: ⚠️ WARNING
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Safety & Quality
- **Location**: test/integration/dogs_test.rb (missing assertion)
- **Detail**: The happy-path test asserted `dog.reload.active?` is false but never called GET dogs_path to verify the dog disappears from the response body. End-state #2 from the plan ("dog disappears from the index") was only verified at the model layer.
- **Fix Applied**: Added `get dogs_path; assert_no_match edit_dog_path(dog), response.body` to the happy-path test. Checks for the edit link (not the name, which appears in the flash).
- **Decision**: FIXED

### F3 — Two unplanned files touched

- **Severity**: OBSERVATION
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Scope Discipline
- **Location**: app/views/dogs/_form.html.erb:34 · config/application.rb:43-45
- **Detail**: Both edits were outside the plan's "Changes Required" list but are correct and load-bearing. _form.html.erb fixed a pre-existing ERB syntax error from commit ffb32b0 that caused 3/12 tests to error. config/application.rb added `button_to_generates_button_tag: true`, required for the Remove button's text colour on Linux GTK/Qt.
- **Decision**: SKIPPED — no code change needed; both edits are justified by discovered constraints

### F4 — Re-deactivating an already-deactivated dog succeeded silently

- **Severity**: OBSERVATION
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Safety & Quality
- **Location**: app/controllers/dogs_controller.rb (set_dog)
- **Detail**: `current_user.dogs.find(params[:id])` fetched deactivated dogs too. A second DELETE called `deactivate!` again, updated `deactivated_at` to a new timestamp, and returned a success flash — misleading.
- **Fix Applied**: Added a separate `before_action :set_active_dog, only: %i[destroy]` scoped to `current_user.dogs.active.find`. Already-deactivated dogs now return 404 on DELETE.
- **Decision**: FIXED

### F5 — Unauthenticated DELETE not covered

- **Severity**: OBSERVATION
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Safety & Quality
- **Location**: test/integration/dogs_test.rb (missing test)
- **Detail**: The four new tests covered owner-happy, guard-blocked, cross-owner, and walker. An unauthenticated DELETE (no session) was not tested.
- **Fix Applied**: Added `test "unauthenticated cannot deactivate a dog"` asserting redirect to new_session_path and dog still active.
- **Decision**: FIXED
