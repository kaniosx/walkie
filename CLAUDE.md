# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Walkie — MVP of a dog-walking marketplace. Owners post a walk request; walkers within a 10km radius (browser-captured geolocation, `Walk::MATCH_RADIUS_KM`, filtering only — no distance sort) accept it; walks move through `REQUESTED → ACCEPTED → IN_PROGRESS → COMPLETED`. City/postcode-based matching was replaced by this radius match (`L-01`, 2026-09-02) — `postcode` no longer exists on `users` or `walks`. Owner/Walker accept flows and the open-requests list broadcast live per-Walker over Turbo Streams (`R-01`). Out of scope for the MVP: continuous GPS tracking during a walk, WebSockets (beyond Turbo/Action Cable), payments, chat, ratings. The product brief is in `@idea-notes.md`, the locked PRD is `@context/foundation/prd.md`, and `@context/foundation/roadmap.md` tracks delivered vs. planned slices. **The app is built out** — models (`User`, `Dog`, `Walk`, `Session`, `WalkerLocationCache`), controllers (auth, profiles, dogs, walks, open requests), and views exist; see `app/` directly rather than assuming a bare skeleton.

## Stack

Rails **8.1** on Ruby **3.4.9**, PostgreSQL 17, Hotwire (Turbo + Stimulus), Propshaft + importmap (no Node bundler), Solid Queue / Solid Cache / Solid Cable (DB-backed adapters — no Redis), Kamal for deploy, Thruster in front of Puma in prod, Minitest (no RSpec). Lint: `rubocop-rails-omakase` (do not customize without reason — see `.rubocop.yml`). Security: Brakeman + bundler-audit.

## Daily commands

Dev runs **inside Docker** (`docker-compose.yml` → services `web` and `db`):

- `make start` — `docker compose up` (web on `:3000`, postgres on `:5432`; `db:prepare` runs on container start)
- `make reset` — interactive: `down -v` (wipes pg_data + bundle_cache), `build --no-cache`, `up`. Use when migrations diverge or the bundle cache is stale.

For one-off Rails commands, exec into the `web` container — do not run `bin/rails` on the host (gems are inside the container volume `bundle_cache`):

- `docker compose exec web bin/rails console`
- `docker compose exec web bin/rails db:migrate`
- `docker compose exec web bin/rails test` (once tests exist — see tripwires)
- `docker compose exec web bundle exec rubocop`
- `docker compose exec web bundle exec brakeman --no-pager`

Run a single test: `docker compose exec web bin/rails test test/models/walk_test.rb` (Minitest takes file or `file:line`).

## Tripwires (project-specific)

- **Stale DB name from the scaffold.** `docker-compose.yml` and `config/database.yml` still use `bootstrap_scaffold_development` (and `_test`, `_production`). This is a leftover from the bootstrapper — if/when you rename it to `walkie_*`, update **both** files and `make reset` to recreate volumes, otherwise `db:prepare` will silently target the old DB and you'll think nothing's wrong.
- **No `test/` directory yet.** Rails 8's default test scaffolding wasn't generated. Do not claim tests pass before the suite exists; generating models with `bin/rails g` will create the directory as a side effect.
- **`.git.scaffold/` at the repo root** is a sidelined artifact from the bootstrapper's `git-clone` conflict policy (the upstream starter's `.git/` directory, renamed). Safe to delete once you're sure you don't need to diff against the starter; do not commit it.
- **`*.scaffold` siblings** are gitignored on purpose — they're the bootstrapper's conflict-policy outputs (e.g. `README.md.scaffold`). Diff against them for "what the starter shipped vs what's here", then delete.
- **No bundler on host.** `bin/rails`, `bundle`, etc. only work inside the `web` container. The host has no Ruby toolchain managed by this repo.

## Foundation files

`context/foundation/` holds the bootstrap chain's outputs and is the **source of truth** for product/architecture decisions — never overwritten by tooling:

- `prd.md` — locked PRD (consume, don't rewrite ad-hoc; re-run `/10x-prd` to change it)
- `tech-stack.md` — the hand-off that picked this Rails 8 + Solid stack
- `shape-notes.md` — pre-PRD shaping conversation

`context/changes/bootstrap-verification/verification.md` is the one-shot audit log from `/10x-bootstrapper`. `context/archive/` is immutable — never write there.

---

<!-- BEGIN @przeprogramowani/10x-cli -->

## 10xDevs AI Toolkit - Module 3, Lesson 4 (E2E Tests)

**For E2E tests, use the `/10x-e2e` skill.** It is the single source of truth
for the workflow — risk → seed test + rules → generate → review against the five
anti-patterns → re-prompt → verify. The skill's `references/` carry the full
rules, anti-patterns, seed pattern, and prompt-template.

A few hard rules that hold even before you invoke the skill:

- **Locators:** `getByRole` / `getByLabel` / `getByText` first; `getByTestId`
  only when accessibility attributes are ambiguous. Never CSS selectors, XPath,
  or DOM structure.
- **Never `page.waitForTimeout()`.** Wait for state: `toBeVisible()`,
  `waitForURL()`, `waitForResponse()`.
- **Test independence + cleanup.** Each test runs standalone — its own setup,
  action, assertion, and cleanup; unique ids (timestamp suffix) so parallel runs
  and re-runs don't collide.

Two boundaries to keep straight:

- **DOM (snapshot) is the default.** Vision (`--caps=vision`) is a supplement for
  visual-only risks (layout, z-index, animation); for pixel regression prefer
  deterministic tools (`toMatchSnapshot`, Argos, Lost Pixel). VLM model
  selection/cost is a debugging topic (Lesson 5), not testing.
- **Healer helps on selectors, harms on logic.** A changed selector → healer
  re-finds it (route through PR review). A changed business behavior → healer
  masks the bug; that failing-test-to-fix case is Lesson 5.

<!-- END @przeprogramowani/10x-cli -->
