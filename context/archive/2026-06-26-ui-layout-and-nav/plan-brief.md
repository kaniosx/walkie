# UI Layout Shell + Role-Aware Navigation — Plan Brief

> Full plan: `context/changes/ui-layout-and-nav/plan.md`

## What & Why

Build the shared application shell that every page will use: a responsive navbar with role-aware
links and a mobile hamburger, plus auto-dismissing flash messages. This is U-02 — the first
visible UI change users will experience, and the prerequisite for all subsequent UI slices (U-03..U-05).

## Starting Point

The current layout has a bare unstyled `<nav>` inline in `application.html.erb` (no partial, no
Tailwind classes), raw flash `tag.div` calls with no auto-dismiss, and **no JavaScript running
in the browser** — Stimulus and Turbo gems are installed but `javascript_importmap_tags` is absent
from the layout, so no JS loads at all.

## Desired End State

Every page has a styled navbar: desktop shows logo + role-based links + sign out; mobile shows
logo + hamburger button that toggles a slide-in menu. Unauthenticated users see Sign in + Sign up.
Flash messages appear with colour, auto-dismiss after 4 seconds, and survive Turbo navigations.

## Key Decisions Made

| Decision | Choice | Why (1 sentence) |
|----------|--------|-----------------|
| Hamburger implementation | Stimulus controller | Good a11y (aria-expanded), extensible, sets up JS infrastructure for all future slices |
| Flash Turbo handling | data-turbo-permanent + auto-dismiss | Flash persists through Turbo Drive navigations and is cleaned up by Stimulus after 4s |
| Nav structure | Extract to `_nav.html.erb` partial | Separation of concerns; layout stays concise |
| Unauthenticated nav | Logo + Sign in + Sign up | Clear CTA for new users |
| Vanilla CSS nav rules | Remove from application.css | Tailwind utilities replace them; no specificity conflicts |

## Scope

**In scope:** importmap + Stimulus bootstrap, `_nav.html.erb` partial, `nav_controller.js`
(hamburger), `flash_controller.js` (auto-dismiss), Tailwind nav styling, removal of old nav CSS.

**Out of scope:** Flash CSS migration to Tailwind, breadcrumbs, user avatar/profile image,
animations beyond Tailwind transitions, Turbo Streams for flash, PWA.

## Architecture / Approach

Phase 1 wires JavaScript into the browser for the first time: `config/importmap.rb` pins Turbo
and Stimulus, `app/javascript/` directory with `application.js` entry point and
`controllers/index.js` using `eagerLoadControllersFrom` (auto-discovers controllers by filename).
Phases 2 and 3 add Stimulus controllers and ERB partials — no further index.js changes needed.

## Phases at a Glance

| Phase | What it delivers | Key risk |
|-------|-----------------|----------|
| 1. JavaScript Infrastructure | importmap + Stimulus loading in browser | `config/importmap.rb` missing → must be created; pin order matters |
| 2. Navigation | `_nav.html.erb`, `nav_controller.js`, Tailwind styling, CSS cleanup | Mobile menu a11y (aria-expanded); Tailwind `md:` breakpoint behaviour |
| 3. Flash Messages | `flash_controller.js` auto-dismiss, turbo-permanent container | `id="flash-container"` must be in every response for Turbo permanent to work |

**Prerequisites:** U-01 done ✅ (Tailwind v3 wired, `stylesheet_link_tag "tailwind"` in layout)
**Estimated effort:** ~1 session across 3 phases

## Open Risks & Assumptions

- `config/importmap.rb` does not exist yet (agent found no explicit file) — Phase 1 creates it.
  If Rails auto-generated one during bootstrap, Phase 1 must merge not overwrite.
- `data-turbo-permanent` on flash container requires the flash wrapper div to be present in every
  page response with `id="flash-container"` — even when no flash exists. The plan accounts for this.
- No existing Stimulus controller pattern to follow — Phase 1 establishes the project convention.

## Success Criteria (Summary)

- Browser console shows no JS errors; Stimulus is loaded on every page
- Desktop and mobile nav work correctly for Owner, Walker, and unauthenticated users
- Flash messages auto-dismiss after 4 seconds and survive Turbo Drive navigations
