# Custom Turbo Confirm Dialog Implementation Plan

## Overview

Replace the native, unstylable `window.confirm()` — currently triggered by Turbo whenever a `data-turbo-confirm` attribute fires — with a Tailwind-styled `<dialog>`-based modal. This uses Turbo 8's built-in confirm-override hook, so none of the three existing call sites need to change their `turbo_confirm:` message; only the confirm *mechanism* changes.

## Current State Analysis

Three views use `data: { turbo_confirm: "..." }` on a `button_to`, which Turbo intercepts and resolves via the browser's native `confirm()`:

- `app/views/walks/_active_table.html.erb` — Cancel a walk request (styled red, `bg-red-600`)
- `app/views/dogs/index.html.erb` — Remove a dog (styled red, `bg-red-600`)
- `app/views/walker_walks/_current_walk.html.erb` — End a walk (styled primary, `bg-primary-600`)

Three existing Minitest system tests drive these flows through Capybara's `accept_confirm { click_on "..." }`, which specifically waits for and accepts a **native** browser dialog:

- `test/system/realtime_active_walk_test.rb:31`
- `test/system/full_walk_lifecycle_test.rb:38`
- `test/system/owner_cancels_request_test.rb:18`

No custom confirm handling exists anywhere in `app/javascript/` today. Stimulus controllers auto-register via `eagerLoadControllersFrom` (`app/javascript/controllers/index.js`) — dropping a new file in `app/javascript/controllers/` is the entire registration step, no importmap or index changes needed. The project's existing controllers (`flash`, `nav`, `owner-location`, `walker-location`) each own exactly one DOM element/concern, which is the pattern this change follows.

## Desired End State

Clicking "Cancel" (walk request), "Remove" (dog), or "End walk" opens a centered, Tailwind-styled modal instead of the browser's native dialog. The modal shows the same message text as today, with generic "Cancel" / "Confirm" buttons. The Confirm button is red for the two destructive actions (Cancel walk request, Remove dog) and primary-colored for End walk, matching each action's existing trigger-button color. Cancel is focused by default. Clicking the backdrop or pressing Escape dismisses the modal exactly like clicking Cancel (no action taken). All three existing system tests pass against the new modal.

Verification: run `docker compose exec web bin/rails test:system` and confirm all three affected tests plus the full system suite pass; manually click all three trigger buttons in the browser and confirm dialog + focus + color match spec.

### Key Discoveries:

- Turbo 8.0.23 (bundled via `turbo-rails` 2.0.23) exposes `Turbo.config.forms.confirm = (message, formElement, submitter) => Promise<boolean>` as the documented override point (confirmed by reading the bundled source: default implementation is `confirmMethod(e){return Promise.resolve(confirm(e))}`, invoked as `e(message, this.formElement, this.submitter)`). The older `Turbo.setConfirmMethod` is deprecated in this version — use `Turbo.config.forms.confirm` directly.
- `@hotwired/turbo-rails` exports a named `Turbo` object (`export{Wt as Turbo,Gt as cable}`), so `import { Turbo } from "@hotwired/turbo-rails"` is the correct import in a Stimulus controller.
- The `submitter` argument passed to the confirm function is the exact button/input that triggered it — the same element `button_to`'s `data:` hash attaches attributes to. This means a new `data-turbo-confirm-style` attribute added alongside the existing `data-turbo-confirm` on each of the two red-button call sites is directly readable as `submitter.dataset.turboConfirmStyle` inside the controller, with no new plumbing.
- Using `<form method="dialog">` inside the `<dialog>` for the Cancel/Confirm buttons means clicking either button auto-closes the dialog natively and sets `dialog.returnValue` to that button's `value` attribute — and pressing Escape also auto-closes with `returnValue` left as `""`. Both cases reduce to one `close` event listener reading `returnValue`, with Escape-cancels falling out for free (no extra Escape handling needed).
- Backdrop-click-to-dismiss on `showModal()` is not automatic and needs one explicit check: a `click` listener on the `<dialog>` element that closes it when `event.target` is the dialog element itself (i.e. the click landed on the backdrop, not on a child element).

## What We're NOT Doing

- Not changing the `turbo_confirm:` message text at any of the three call sites.
- Not adding per-call-site custom button labels — "Cancel" / "Confirm" are generic and reused everywhere (per user decision).
- Not adding a new system test for the modal's Cancel/dismiss path — only fixing the three tests that already exist and would otherwise break (per user decision; the existing "thin e2e layer" philosophy from T-01 applies).
- Not touching any backend, model, or state-machine code — this is a pure front-end presentation change.
- Not introducing a JS library/dependency — uses Turbo's built-in hook and the native `<dialog>` element only.

## Implementation Approach

Add one new Stimulus controller (`confirm-dialog`) owning a single `<dialog>` element placed once in the shared layout, matching the existing per-element-controller convention. On `connect()`, it installs itself as `Turbo.config.forms.confirm`. Two of the three existing views get one additional `data-turbo-confirm-style: "danger"` attribute (the third — End walk — needs no view change, since "primary" is the fallback default). Finally, the three system tests that use `accept_confirm` are updated to click the new dialog's "Confirm" button instead.

## Critical Implementation Details

**Backdrop-click boundary check**: give the visual box (border, padding, background, rounded corners) to an inner wrapper `<div>` inside the `<dialog>`, not to the `<dialog>` element itself. This guarantees a click that lands directly on the `<dialog>` element (rather than on the inner wrapper or its children) can only be a backdrop click, making the `event.target === this.element` check in the click listener reliable.

## Phase 1: Custom confirm dialog

### Overview

Build the dialog markup + Stimulus controller, wire it up as Turbo's confirm method, and add the color-variant data attribute to the two destructive-action views.

### Changes Required:

#### 1. Dialog markup in the shared layout

**File**: `app/views/layouts/application.html.erb`

**Intent**: Add a single, reusable `<dialog>` element (hidden until opened via `showModal()`) near the end of `<body>`, styled with Tailwind to match the app's existing card/button language (stone palette for the box and Cancel button, red/primary for Confirm depending on variant).

**Contract**: A `<dialog data-controller="confirm-dialog" data-confirm-dialog-target="dialog">` wrapping an inner styled `<div>` containing a `<p data-confirm-dialog-target="message">` and a `<form method="dialog">` with two buttons: `<button value="cancel" data-confirm-dialog-target="cancelButton" autofocus>Cancel</button>` and `<button value="confirm" data-confirm-dialog-target="confirmButton">Confirm</button>`. The Confirm button carries the two variant classes as data (or is toggled via a `data-confirm-dialog-variant-value` / class swap — see controller below) so its color can switch between the app's `bg-red-600 hover:bg-red-700` (danger) and `bg-primary-600 hover:bg-primary-700` (primary, default) treatments already used elsewhere in the app. Cancel button uses a neutral style consistent with the app's stone palette (e.g. `bg-white border border-stone-300 text-stone-700 hover:bg-stone-50`).

#### 2. Confirm dialog Stimulus controller

**File**: `app/javascript/controllers/confirm_dialog_controller.js` (new)

**Intent**: Install itself as Turbo's confirm method on connect; when invoked, populate the message, apply the correct Confirm-button color variant, open the dialog modally, and resolve a Promise based on which button (or Escape) closed it.

**Contract**:
```js
import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["dialog", "message", "confirmButton"]

  connect() {
    Turbo.config.forms.confirm = (message, formElement, submitter) => this.confirm(message, submitter)
    this.dialogTarget.addEventListener("click", (event) => {
      if (event.target === this.dialogTarget) this.dialogTarget.close()
    })
  }

  confirm(message, submitter) {
    this.messageTarget.textContent = message
    this.applyVariant(submitter?.dataset.turboConfirmStyle === "danger")
    this.dialogTarget.showModal()
    return new Promise((resolve) => {
      this.dialogTarget.addEventListener(
        "close",
        () => resolve(this.dialogTarget.returnValue === "confirm"),
        { once: true }
      )
    })
  }

  applyVariant(isDanger) {
    this.confirmButtonTarget.classList.toggle("bg-red-600", isDanger)
    this.confirmButtonTarget.classList.toggle("hover:bg-red-700", isDanger)
    this.confirmButtonTarget.classList.toggle("bg-primary-600", !isDanger)
    this.confirmButtonTarget.classList.toggle("hover:bg-primary-700", !isDanger)
  }
}
```
No importmap or `controllers/index.js` change needed — `eagerLoadControllersFrom` auto-registers this file as `confirm-dialog`, matching the `data-controller="confirm-dialog"` in the layout markup above.

#### 3. Color-variant data attribute on the two destructive call sites

**Files**: `app/views/walks/_active_table.html.erb`, `app/views/dogs/index.html.erb`

**Intent**: Mark the Cancel-walk and Remove-dog triggers as "danger" so their Confirm button renders red, matching their existing trigger-button color. No change needed at `app/views/walker_walks/_current_walk.html.erb` (End walk) — the controller's `applyVariant` defaults to primary when the attribute is absent, which already matches that button's current color.

**Contract**: Add `turbo_confirm_style: "danger"` as a sibling key inside the existing `data: { turbo_confirm: "..." }` hash at both call sites — no other change to those `button_to` calls.

### Success Criteria:

#### Automated Verification:

- [ ] 1.1 `docker compose exec web bundle exec rubocop` passes (no new offenses)
- [ ] 1.2 Application boots without JS console errors: `docker compose up` then load any page and check devtools console

#### Manual Verification:

- [ ] 1.3 Clicking "Cancel" on a walk request opens the styled modal (not the native browser dialog) with a red Confirm button
- [ ] 1.4 Clicking "Remove" on a dog opens the styled modal with a red Confirm button
- [ ] 1.5 Clicking "End walk" opens the styled modal with a primary-colored Confirm button
- [ ] 1.6 In each case, Cancel has default keyboard focus (pressing Enter immediately after open does nothing destructive)
- [ ] 1.7 Clicking the backdrop, pressing Escape, and clicking the Cancel button all dismiss the modal without performing the action
- [ ] 1.8 Clicking Confirm performs the original action (walk cancelled / dog removed / walk ended) exactly as before

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 2: Fix existing system tests

### Overview

Update the three system tests that use Capybara's `accept_confirm` (which only understands the native browser dialog) so they interact with the new custom modal instead.

### Changes Required:

#### 1. Replace `accept_confirm` blocks with a direct click on the new dialog's Confirm button

**Files**: `test/system/realtime_active_walk_test.rb`, `test/system/full_walk_lifecycle_test.rb`, `test/system/owner_cancels_request_test.rb`

**Intent**: Since the Confirm button in the new dialog carries the generic label "Confirm" (from Phase 1), each `accept_confirm { click_on "X" }` becomes a plain `click_on "X"` followed by `click_on "Confirm"` — Capybara's default wait behavior already handles waiting for the dialog to become visible before the second click finds it.

**Contract**: In `realtime_active_walk_test.rb` and `full_walk_lifecycle_test.rb`, replace `accept_confirm { click_on "End walk" }` with:
```ruby
click_on "End walk"
click_on "Confirm"
```
In `owner_cancels_request_test.rb`, replace `accept_confirm { click_on "Cancel" }` with:
```ruby
click_on "Cancel"
click_on "Confirm"
```

### Success Criteria:

#### Automated Verification:

- [ ] 2.1 `docker compose exec web bin/rails test:system` passes (all system tests green, including the three updated ones)
- [ ] 2.2 `docker compose exec web bin/rails test` passes (full suite, no regressions elsewhere)

#### Manual Verification:

- [ ] 2.3 None — this phase is test-only; Phase 1's manual verification already covers the user-facing behavior.

---

## Testing Strategy

### Unit Tests:

- None planned — this is a presentational Stimulus controller with no business logic; the existing system tests provide the relevant coverage end-to-end.

### Integration Tests:

- N/A — no controller/model layer touched.

### Manual Testing Steps:

1. Sign in as an Owner with an active walk request, click "Cancel", verify the modal (not a native alert) appears with a red Confirm button, message text intact.
2. Repeat for "Remove" on a dog (dogs index).
3. Sign in as a Walker with an in-progress walk, click "End walk", verify the modal appears with a primary-colored Confirm button.
4. For each of the three, verify: Escape dismisses without action; clicking outside the box dismisses without action; clicking Cancel dismisses without action; clicking Confirm performs the action.
5. Tab/keyboard-only pass: confirm Cancel is focused on open, Tab moves to Confirm, Enter on Cancel does nothing destructive.

## Performance Considerations

None — a single small controller and one static `<dialog>` element added to the layout; no additional queries or network calls.

## Migration Notes

N/A — no data or schema changes.

## References

- Turbo 8 confirm-override source (read directly from the installed gem): `turbo-rails-2.0.23/app/assets/javascripts/turbo.min.js` — `Turbo.config.forms.confirm` / deprecated `Turbo.setConfirmMethod`.
- Existing Stimulus controller conventions: `app/javascript/controllers/flash_controller.js`, `app/javascript/controllers/nav_controller.js`.
- Existing call sites: `app/views/walks/_active_table.html.erb`, `app/views/dogs/index.html.erb`, `app/views/walker_walks/_current_walk.html.erb`.

## Progress

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles. See `references/progress-format.md`.

### Phase 1: Custom confirm dialog

#### Automated

- [x] 1.1 `docker compose exec web bundle exec rubocop` passes (no new offenses)
- [x] 1.2 Application boots without JS console errors

#### Manual

- [x] 1.3 Cancel-walk modal is styled, not native, with red Confirm
- [x] 1.4 Remove-dog modal is styled, not native, with red Confirm
- [x] 1.5 End-walk modal is styled, not native, with primary Confirm
- [x] 1.6 Cancel has default focus on open
- [x] 1.7 Backdrop click, Escape, and Cancel button all dismiss without action
- [x] 1.8 Confirm performs the original action in all three cases

### Phase 2: Fix existing system tests

#### Automated

- [ ] 2.1 `docker compose exec web bin/rails test:system` passes
- [ ] 2.2 `docker compose exec web bin/rails test` passes
