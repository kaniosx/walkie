<!-- IMPL-REVIEW-REPORT -->
# Implementation Review: Custom Turbo Confirm Dialog

- **Plan**: context/changes/custom-turbo-confirm-dialog/plan.md
- **Scope**: Full plan (Phase 1 of 2, Phase 2 of 2)
- **Date**: 2026-09-03
- **Verdict**: APPROVED
- **Findings**: 0 critical, 2 warnings, 3 observations

## Verdicts

| Dimension | Verdict |
|-----------|---------|
| Plan Adherence | PASS |
| Scope Discipline | PASS |
| Safety & Quality | PASS |
| Architecture | PASS |
| Pattern Consistency | WARNING |
| Success Criteria | PASS |

Automated checks re-verified at review time: `bundle exec rubocop` (83 files, 0 offenses), `bin/rails test:system` (11 runs, 0 failures), `bin/rails test` (129 runs, 0 failures). Plan-drift sub-agent found zero drift — every planned file matches its Contract exactly. Security check confirmed the interpolated dog-name confirm message is XSS-safe (`textContent`, not `innerHTML`, plus Rails auto-escaping).

## Findings

### F1 — Declared cancelButton target is never registered

- **Severity**: ⚠️ WARNING
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Pattern Consistency
- **Location**: app/views/layouts/application.html.erb:44 / app/javascript/controllers/confirm_dialog_controller.js:5
- **Detail**: The layout declares `data-confirm-dialog-target="cancelButton"` on the Cancel button, but the controller's `static targets = ["dialog", "message", "confirmButton"]` never lists `cancelButton`. Stimulus silently ignores unregistered target attributes — no runtime error, but the attribute looks functional (mirrors `confirmButtonTarget`, which IS used) and isn't.
- **Fix**: Remove the unused `data-confirm-dialog-target="cancelButton"` attribute — nothing currently needs a JS reference to Cancel (it relies on `autofocus` + native form submission).
- **Decision**: FIXED

### F2 — Imperative addEventListener instead of declarative data-action

- **Severity**: ⚠️ WARNING
- **Impact**: 🔎 MEDIUM — real tradeoff; pause to reason through it
- **Dimension**: Pattern Consistency
- **Location**: app/javascript/controllers/confirm_dialog_controller.js:9-11
- **Detail**: Every other controller in the app (nav_controller.js, flash_controller.js, owner/walker_location_controller.js) wires DOM events declaratively via `data-action` in the HTML. This controller is the only one calling `this.dialogTarget.addEventListener("click", ...)` imperatively inside `connect()`, with no matching `disconnect()` to tear it down. Currently harmless (this app uses full-body Turbo Drive navigation, not morph, so `connect()` only fires once per page load) — but it's a latent trap: if Turbo morph rendering is ever adopted and this dialog's node gets preserved across a reconnect, the listener would stack.
- **Fix A ⭐ Recommended**: Convert to `data-action="click->confirm-dialog#backdropClick"` on the layout's `<dialog>`, with a `backdropClick(event) { if (event.target === this.dialogTarget) this.dialogTarget.close() }` method, dropping the manual addEventListener.
  - Strength: Matches every sibling controller's convention; Stimulus handles listener lifecycle automatically, eliminating the stacking risk class entirely, not just today's instance of it.
  - Tradeoff: None meaningful — same line count, same behavior.
  - Confidence: HIGH — direct precedent in nav_controller.js's data-action use.
  - Blind spot: None significant.
- **Fix B**: Leave as-is, add a `disconnect()` to remove the listener.
  - Strength: Smaller diff; keeps the imperative style if there's a reason to prefer explicit control.
  - Tradeoff: Doesn't fix the underlying convention mismatch; still the only controller doing manual DOM wiring.
  - Confidence: MEDIUM — technically correct but doesn't address why F2 exists.
  - Blind spot: None significant.
- **Decision**: FIXED via Fix A

### F3 — Single point of failure for all destructive actions app-wide

- **Severity**: 👁️ OBSERVATION
- **Impact**: 🏃 LOW — informational, no action required now
- **Dimension**: Architecture
- **Location**: app/javascript/controllers/confirm_dialog_controller.js:14-32
- **Detail**: `connect()`/`confirm()`/`applyVariant()` touch `this.dialogTarget`/`messageTarget`/`confirmButtonTarget` with no `hasXTarget` guard (unlike nav_controller.js's `hasHamburgerTarget` checks). Since this function is now the sole gate for every `data-turbo-confirm` action app-wide, a future edit that accidentally drops one of those three data attributes from the layout would break every confirm dialog at once, not just this feature.
- **Fix**: No action needed now — informational for awareness.
- **Decision**: SKIPPED

### F4 — Startup race falls back to native confirm() (benign)

- **Severity**: 👁️ OBSERVATION
- **Impact**: 🏃 LOW — informational, no action required now
- **Dimension**: Reliability
- **Location**: app/javascript/controllers/confirm_dialog_controller.js:8
- **Detail**: A click on a turbo_confirm button before the Stimulus controller's `connect()` has run falls back to Turbo's built-in native `confirm()` for that one click, rather than failing. Cosmetic inconsistency only, self-resolves on the next click.
- **Fix**: No action needed — informational.
- **Decision**: SKIPPED

### F5 — Duplicate "Cancel" accessible name (page button + modal button)

- **Severity**: 👁️ OBSERVATION
- **Impact**: 🏃 LOW — informational, no action required now
- **Dimension**: Success Criteria (future test risk)
- **Location**: app/views/walks/_active_table.html.erb, app/views/layouts/application.html.erb
- **Detail**: The page's own "Cancel" button and the modal's "Cancel" button share the same accessible name. None of the three updated tests click "Cancel" while the dialog is open, so this doesn't cause flakiness today — flagged so a future test author scoping a `click_on "Cancel"` inside an open dialog knows to disambiguate (e.g. `within("dialog") { click_on "Cancel" }`).
- **Fix**: No action needed now — informational for future test authors.
- **Decision**: SKIPPED
