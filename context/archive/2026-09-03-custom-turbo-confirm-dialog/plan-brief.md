# Custom Turbo Confirm Dialog — Plan Brief

> Full plan: `context/changes/custom-turbo-confirm-dialog/plan.md`

## What & Why

Replace the native, unstylable `window.confirm()` (currently used at three destructive/irreversible actions) with a Tailwind-styled `<dialog>`-based modal, using Turbo 8's built-in confirm-override hook. Motivation: the app already looks polished elsewhere; a raw browser alert breaks that consistency at exactly the moments (cancel, remove, end walk) where UX trust matters most.

## Starting Point

Three views today pass `data: { turbo_confirm: "..." }` to `button_to`, which Turbo resolves via the browser's native `confirm()`: cancel a walk request, remove a dog, end a walk. No custom confirm handling exists in `app/javascript/` yet. Three system tests use Capybara's `accept_confirm`, which only understands the native dialog and will break once it's replaced.

## Desired End State

Clicking any of the three triggers opens a centered, styled modal with the same message text, generic "Cancel"/"Confirm" buttons, Cancel focused by default, and the Confirm button colored to match the trigger's existing severity (red for Cancel/Remove, primary for End walk). Escape and backdrop-click both dismiss safely, same as clicking Cancel.

## Key Decisions Made

| Decision | Choice | Why (1 sentence) | Source |
| --- | --- | --- | --- |
| Confirm button color | Inherits trigger's severity (red vs primary) | Preserves the visual language already present in the 3 call sites | Plan (user Q&A) |
| Backdrop/Escape dismiss | Both count as Cancel | Matches native `confirm()`'s existing Escape-cancels behavior — no UX regression | Plan (user Q&A) |
| Button labels | Generic "Cancel"/"Confirm" everywhere | Message text already carries the specific context; avoids new per-site plumbing | Plan (user Q&A) |
| Test scope | Only fix the 3 existing `accept_confirm` tests | Matches the project's stated "thin e2e layer" philosophy from T-01 | Plan (user Q&A) |
| Default focus | Cancel | Safer default for irreversible actions, matches native `confirm()`'s common default | Plan (user Q&A) |
| Override mechanism | `Turbo.config.forms.confirm` (not deprecated `setConfirmMethod`) | Confirmed against the actual bundled Turbo 8.0.23 source in the gem | Plan (research) |
| Ownership pattern | New `confirm-dialog` Stimulus controller, one `<dialog>` in the layout | Matches existing one-controller-per-element convention (flash, nav, owner/walker-location) | Plan (research) |

## Scope

**In scope:** New Stimulus controller + `<dialog>` markup in the shared layout; one new data attribute on 2 of the 3 existing views; fixing the 3 now-broken system tests.

**Out of scope:** Changing confirm message copy; per-site custom button labels; new test coverage for the Cancel/dismiss path; any backend/model/state-machine change.

## Architecture / Approach

A single `<dialog data-controller="confirm-dialog">` lives once in `application.html.erb`. On `connect()`, the controller installs itself as `Turbo.config.forms.confirm`, so every existing `turbo_confirm:` call site is intercepted automatically — no view changes needed beyond an optional `turbo_confirm_style: "danger"` data attribute for red variants. `<form method="dialog">` inside the modal gives free Escape/close semantics via `dialog.returnValue`; one small click listener adds backdrop-dismiss.

## Phases at a Glance

| Phase | What it delivers | Key risk |
| --- | --- | --- |
| 1. Custom confirm dialog | Working styled modal wired to all 3 existing triggers | Backdrop-click boundary check relies on DOM structure (box styles must live on an inner wrapper, not the `<dialog>` itself) |
| 2. Fix existing system tests | 3 system tests updated to click the new dialog instead of `accept_confirm` | Low — mechanical Capybara change, generic "Confirm" label makes it a 1-line swap per test |

**Prerequisites:** None beyond the running Docker dev environment.
**Estimated effort:** ~1 session, 2 phases.

## Open Risks & Assumptions

- Assumes `<dialog>`/`showModal()` browser support is sufficient for the project's target browsers (no IE/legacy support needed — matches the app's existing modern-browser assumptions, e.g. the geolocation API already in use).
- Rubocop/Brakeman have no JS-specific linting in this stack, so JS style consistency relies on matching existing controller conventions by hand, not a linter gate.

## Success Criteria (Summary)

- All three trigger actions show the new styled modal instead of a native browser alert, with correct color/focus/dismiss behavior.
- `bin/rails test:system` and `bin/rails test` both pass with no regressions.
