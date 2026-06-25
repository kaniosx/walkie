# Tailwind CSS Setup — Plan Brief

> Full plan: `context/changes/tailwind-setup/plan.md`

## What & Why

Install Tailwind CSS v3 as the UI foundation for the Walkie app (roadmap U-01).
The project has no CSS framework today — only ~80 lines of vanilla CSS — and four
UI slices (U-02..U-05) are waiting on this foundation before they can style any view.
`tailwindcss-rails` (standalone binary, no Node required) is the correct fit for a
Rails 8 + Propshaft + importmap stack.

## Starting Point

A working Rails 8.1 app running in Docker with Propshaft serving a single `application.css`
(nav, flash, form styles). No Tailwind, no bundler, no Foreman. Dev server runs directly
via `bin/rails server` in docker-compose.

## Desired End State

Both `application.css` (existing) and the compiled `tailwind.css` are served on every page.
Adding a Tailwind class to any `.html.erb` file causes the watcher to recompile CSS
automatically on save. Brand tokens (`primary = emerald`, `neutral = stone`) are available
as Tailwind utilities. Existing pages are visually unaffected.

## Key Decisions Made

| Decision | Choice | Why (1 sentence) | Source |
|----------|--------|-------------------|--------|
| CSS framework | Tailwind v3 via `tailwindcss-rails` | Standalone binary, no Node — perfect fit for Propshaft + importmap | Plan |
| Dev watcher | Background process in docker-compose (`& ...`) | Zero new tooling; keeps existing docker-compose command structure | Plan |
| Existing CSS | Coexist unchanged in U-01 | Keeps U-01 scoped to infrastructure; migration happens in U-02..U-05 | Plan |
| Brand palette | Primary = emerald (green), neutral = stone | Warm, nature-friendly feel for a dog-walking marketplace | Plan |
| Font | System font stack (`system-ui, -apple-system`) | Already in place; no external requests or config | Plan |
| Tailwind version | v3 stable | Mature, fully documented, no breaking changes risk for MVP | Plan |

## Scope

**In scope:** `tailwindcss-rails` gem, install generator, `tailwind.config.js` with brand
tokens, layout stylesheet wiring, docker-compose watcher, `.gitignore` entry.

**Out of scope:** Migrating existing CSS, Tailwind plugins (Typography, Forms), web fonts,
CI pipeline changes, Foreman/`bin/dev`.

## Architecture / Approach

The `tailwindcss-rails` gem ships a platform-specific Tailwind CLI binary (via
`tailwindcss-ruby`). The generator creates `app/assets/stylesheets/application.tailwind.css`
as the input and compiles to `app/assets/builds/tailwind.css`, which Propshaft serves.
In dev, the watcher runs as a backgrounded shell process (`&`) alongside `bin/rails server`
in the docker-compose command. In production, `assets:precompile` already calls
`tailwindcss:build` as a prerequisite (gem hook) — no Dockerfile change needed.

## Phases at a Glance

| Phase | What it delivers | Key risk |
|-------|-----------------|----------|
| 1. Gem + install generator | Gem installed, generator run, layout includes `tailwind.css` | Generator may overwrite layout nav/flash — review diff carefully |
| 2. Config + design tokens | `tailwind.config.js` with correct content paths and brand tokens | Wrong content paths → classes silently purged in production |
| 3. Docker watcher | Live CSS recompilation on view save without manual steps | `&` in YAML command string needs careful quoting check |

**Prerequisites:** Docker stack running (`make start`), no outstanding migration conflicts.
**Estimated effort:** ~1 session, 3 phases.

## Open Risks & Assumptions

- The `tailwindcss-ruby` gem downloads the binary during `bundle install` — requires
  internet access in the Docker build (true for both dev and production Render build).
- The install generator's layout changes must be reviewed manually; it may place the
  Tailwind tag before `:app` (want it after, so `application.css` can override during transition).
- `app/assets/builds/` is gitignored (generated); each developer's container rebuilds it
  on `make start`.

## Success Criteria (Summary)

- Both stylesheets load on every page; existing visual design is unchanged
- `class="bg-primary-500"` on any ERB element compiles and renders as expected green
- View edit → watcher recompiles → browser reflects change without manual rebuild
