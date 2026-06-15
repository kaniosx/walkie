# S-01: Sign-up + Sign-in with Role Choice — Plan Brief

> Full plan: `context/changes/signup-and-signin-with-role/plan.md`

## What & Why

Add the user-facing UI layer on top of the auth mechanics F-01 built. The sign-up, sign-in, and sign-out flows are functionally complete but the presentation is bare: the app title still reads "Bootstrap Scaffold", flash messages are silently swallowed on most pages, there is no persistent navigation, and the role radio buttons show raw enum values. S-01 makes the auth flow usable by a real test user without any tutorial.

## Starting Point

F-01 delivered working auth controllers, models, routes, and tests. The application layout has no flash block and no nav element. The home page has a sign-out button but it is only visible there. The sign-up form already has role radios using the Rails enum iterator, but the labels are "owner" / "walker" (unformatted).

## Desired End State

A visitor opens the app, sees the "Walkie" brand in the tab and in a nav bar, signs up by choosing "I'm a Dog Owner" or "I'm a Dog Walker", lands on a home page with a role-appropriate hint, and can sign out from the persistent nav at any time. Flash messages (failed sign-in, rate-limit alerts) appear consistently on every page. The password-reset form explains that email reset is not available in v1.

## Key Decisions Made

| Decision | Choice | Why (1 sentence) | Source |
| --- | --- | --- | --- |
| Post-auth redirect | Single root for both roles | Owner/Walker dashboards don't exist yet; role-split routing is an S-02+ decision | Plan |
| Flash rendering | Layout-level (not per-view) | Prevents silent flash loss on new pages; removes duplication from auth views | Plan |
| Navigation | Thin nav bar, always visible; sign-out only when `authenticated?` | Sign-out must be reachable from any page; brand always present | Plan |
| CSS | Minimal custom CSS, no framework | Propshaft + importmap stack avoids Node; Tailwind would add a build step not chosen at bootstrap | Plan |
| Role UI | Keep radio buttons; improve labels | Binary choice; radios are clearer than a dropdown; raw enum values ("owner") are confusing to real users | Plan |
| Password reset | Keep link + v1 notice | Inert email delivery is a v1 constraint; users need an explanation, not a 404 | Plan |
| Test scope | Navigation + flash integration tests only | F-01 tests already cover auth flow; S-01 tests cover only the new UX surface | Plan |

## Scope

**In scope:** Application layout (title, flash, nav); sign-up form copy; password-reset notice; home page role hints; minimal CSS; navigation + flash integration tests.

**Out of scope:** Password-reset email wiring; Tailwind or CSS frameworks; role-specific routing; Capybara / system tests; SimpleCov gate flip; any model or controller changes.

## Architecture / Approach

Purely view-layer changes. No new routes, controllers, or models. Three ordered phases: (1) layout first (flash and nav depend on the layout being wired before views remove their inline flash), (2) individual view polish + CSS, (3) tests + full gate. The `authenticated?` helper is already a `helper_method` in `Authentication` concern — the nav bar guard uses it directly.

## Phases at a Glance

| Phase | What it delivers | Key risk |
| --- | --- | --- |
| 1. Layout (title, flash, nav) | Persistent brand, global flash, authenticated nav with sign-out | Removing inline flash before layout flash is wired causes silent flash loss — must do layout first |
| 2. View polish + CSS | Friendly role labels, v1 password notice, role hint on home, minimal CSS | Double-rendering flash if inline flash not removed from sessions/new and registrations/new |
| 3. Tests + full gate | Navigation + flash integration tests; rubocop + brakeman clean | No new test infrastructure needed; plain ActionDispatch integration tests suffice |

**Prerequisites:** F-01 `done` (confirmed archived 2026-06-15).  
**Estimated effort:** ~1 session across 3 small phases.

## Open Risks & Assumptions

- `app/controllers/home_controller.rb` is assumed to exist as an empty ApplicationController subclass (required for `root "home#index"` to work). If missing, it must be created before Phase 2's home view change is testable.
- `authenticated?` is confirmed available as a `helper_method` — safe to use in the layout without further controller changes.

## Success Criteria (Summary)

- A real test user can sign up as Owner or Walker, land on a role-appropriate home page, and sign out — all without knowing any URLs.
- Flash messages (failed sign-in, rate-limit alerts) appear on every page without per-view duplication.
- `bin/rails test`, `rubocop`, and `brakeman` are all green after Phase 3.
