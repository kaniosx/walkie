# Auth + Profile Screens — Plan Brief

> Full plan: `context/changes/ui-auth-and-profile/plan.md`

## What & Why

Style the four existing auth and profile views (sign-in, sign-up, profile show, profile edit) with Tailwind CSS. The navbar (U-02) is already fully Tailwind-styled; these four pages are the last vanilla-CSS surfaces, and the visual inconsistency is visible as soon as a user lands on sign-in or profile after navigating the navbar.

## Starting Point

All four views wrap their content in `div.form-container` (vanilla CSS: max-width 400px, centred). Validation errors use `div.form-errors` (vanilla CSS red box). The Tailwind design tokens (emerald = primary, stone = neutral) are in place from U-01; the navbar in U-02 proves the pipeline works.

## Desired End State

Sign-in, sign-up, profile show, and profile edit each render as a centred white card consistent with the navbar's design language. Inputs have stone borders with primary-coloured focus rings; the action button uses `bg-primary-600`; validation error banners are Tailwind-red. The app works on mobile at 375 px without horizontal scroll. `application.css` no longer contains `.form-container` or `.form-errors` rule groups.

## Key Decisions Made

| Decision | Choice | Why (1 sentence) |
| --- | --- | --- |
| Container migration | Full Tailwind (`max-w-sm mx-auto …`) | Mixing vanilla CSS wrappers with Tailwind utilities perpetuates the split U-02 was meant to close |
| Profile show scope | Include in this slice | Profile show shares `.form-container` and will look raw next to the styled edit form |
| Validation error layout | Banner above the form | Minimal structural change; roadmap says "highlighted in red", which a banner delivers |
| application.css cleanup | Remove migrated rules | `.form-container` and `.form-errors` become dead code; removing avoids confusion for the next change |

## Scope

**In scope:** `sessions/new.html.erb`, `registrations/new.html.erb`, `profiles/show.html.erb`, `profiles/edit.html.erb`; removal of `.form-container` / `.form-errors` / stub input rules from `application.css`

**Out of scope:** Any controller, route, model, or Stimulus change; `.flash-alert` / `.flash-notice` migration; `dogs/` or walk views; inline per-field error layout

## Architecture / Approach

Pure view-layer change. Each view replaces its `class="form-container"` wrapper with a Tailwind card and receives label, input, button, and error-banner classes. `<br>` separators between form fields are replaced by `<div class="mb-4">` wrappers. One canonical set of class strings is defined for each shape (card, label, input, button, error banner, link) and applied consistently across all four views.

## Phases at a Glance

| Phase | What it delivers | Key risk |
| --- | --- | --- |
| 1. CSS Cleanup | Remove dead vanilla CSS from `application.css` | Premature removal before views are updated would briefly unstyled forms — do this first, verify layout intact, then move to Phase 2 |
| 2. Style Auth Views | Tailwind-styled sign-in + sign-up | Role radio `<fieldset>` requires manual test to confirm the radio still writes the correct role after visual changes |
| 3. Style Profile Views | Tailwind-styled profile show + edit | `<dl>` styling is custom; verify definition list is readable on mobile |

**Prerequisites:** U-01 (Tailwind pipeline) and U-02 (layout shell) — both archived.
**Estimated effort:** ~1 session across 3 phases (all are small view edits).

## Open Risks & Assumptions

- Tailwind's JIT scanner must see the new class strings in `.erb` files at build time — if a class is only constructed dynamically it may be purged. All class strings in this plan are static literals, so no risk.
- The Tailwind `placeholder-stone-400` utility requires `tailwindcss-rails` 3.x+ (standalone binary); the gem version should be confirmed in `Gemfile.lock` if placeholder colour doesn't render.

## Success Criteria (Summary)

- All four pages render as a consistent white card on desktop and mobile (375 px, no horizontal scroll)
- Validation error banners appear in red on invalid submits (sign-up, profile edit)
- Sign-up role radio remains functional after visual changes
