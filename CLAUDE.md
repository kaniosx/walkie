# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Walkie — MVP of a dog-walking marketplace. Owners post a walk request, available walkers in the same city/postcode accept it; walks move through `REQUESTED → ACCEPTED → IN_PROGRESS → COMPLETED`. Out of scope for the MVP: realtime GPS, WebSockets, payments, chat, ratings. The product brief is in `@idea-notes.md` and the locked PRD is `@context/foundation/prd.md`. **The codebase is currently an empty Rails skeleton** — `app/models`, `app/controllers`, `config/routes.rb` are bare; no domain models, controllers, or views have been written yet. Feature work starts from zero.

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

## 10xDevs AI Toolkit - Module 2, Lesson 3

Review AI-generated code before merge with the **implementation review chain**:

```
/10x-implement -> /10x-impl-review -> triage -> (/10x-lesson | fix | skip | disagree)
```

`/10x-impl-review` is the lesson focus. Review is a quality gate, not an instruction to fix every finding.

### Task Router - Where to start

| Skill | Use it when |
| --- | --- |
| **Code review (lesson focus)** | |
| `/10x-impl-review <change-id>` | You have implemented code and want a structured review before merge. The skill checks plan adherence, scope discipline, safety and quality, architecture, pattern consistency, and success criteria, then presents findings for triage. |
| **Recurring lesson outcome** | |
| `/10x-lesson` | A finding reveals a recurring project rule or agent failure pattern. Record it in `context/foundation/lessons.md` instead of treating it as a one-off note. |

### Triage discipline

- Severity says how bad the finding is. Impact says how much the decision matters now.
- Valid outcomes: fix now, fix differently, skip, accept as risk, record as recurring rule (`/10x-lesson`), disagree.
- Fix critical findings. Do not burn hours on low-impact observations just because the agent found them.
- Conscious skipping of low-impact findings is a valid review outcome, not negligence.
- If you disagree with a finding, record why. Wrong agent reasoning is also signal.

### Review boundaries

- This lesson reviews implemented code. It does not create the plan, execute new phases, or teach CI review.
- Testing strategy and quality gates are introduced in Module 3.
- Do not use `/10x-contract` as a triage outcome in this lesson.

### Paths used by this lesson

- `context/changes/<change-id>/plan.md` - expected implementation contract
- `context/changes/<change-id>/reviews/` - review output
- `context/foundation/lessons.md` - recurring lessons

Skills must not write to `context/archive/`. Archived changes are immutable; if a resolved target path starts with `context/archive/`, abort with: "This change is archived. Open a new change with `/10x-new` instead."

<!-- END @przeprogramowani/10x-cli -->
