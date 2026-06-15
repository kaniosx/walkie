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

## 10xDevs AI Toolkit - Module 3, Lesson 1

Open Module 3 by producing a **durable, risk-first quality contract** before any test is written — then drive each rollout phase through the standard change chain.

```
PRD + roadmap + archive
        │
        ▼
   /10x-test-plan  ──►  context/foundation/test-plan.md  (strategy §1–§5 frozen + cookbook §6 grows)
        │
        ▼  (one rollout phase at a time, /clear between handoffs)
   /10x-new ──► /10x-research ──► /10x-plan ──► /10x-implement
```

`/10x-test-plan` is a **stateful orchestrator**, not a one-shot generator. On first run it writes the phased rollout to `context/foundation/test-plan.md`. On every subsequent run it re-derives state from on-disk artifacts and presents the next handoff. The lesson focus is **strategy and rollout sequencing, not configuration**. Hooks, MCP servers, and CI YAML are configured in later lessons of this module.

### Task Router - Where to start

| Skill | Use it when |
| --- | --- |
| **Quality strategy as a rules-file (lesson focus)** | |
| `/10x-test-plan` | You have a PRD (and ideally a roadmap and a few archived slices) and you are about to write the project's first tests, or you noticed that AI-generated tests are landing on helpers while critical flows go uncovered. First invocation runs discovery (PRD + roadmap + archive + hot-spot scan), a 5-question user interview, and a synthesis pass with a mandatory challenger check, then writes `test-plan.md` in `context/foundation/` with a risk map (5–7 failure scenarios), a phased rollout table, a stack table, a quality-gates table, a cookbook section (`§6`, fills in as phases ship), and a negative-space section (what we deliberately don't test). Subsequent invocations advance the rollout one handoff at a time. |
| `/10x-test-plan --status` | A `test-plan.md` already exists and you want a compact snapshot of where the rollout stands — which phases are `not started`, `change opened`, `researched`, `planned`, `implementing`, or `complete`, and what the next action is. Does no work; safe to run any time. |
| `/10x-test-plan --refresh` | A `test-plan.md` already exists and one of: a new top-3 risk surfaced from the roadmap or archive, a tool's `checked:` date is older than three months, the project's tech stack changed, or §7 negative-space no longer matches what the team believes. Opens a new `test-plan-refresh-<YYYY-MM-DD>` change folder rather than editing the guide in place. |

### Rollout chain — what happens after the guide is written

The guide's §3 *Phased Rollout* table is the orchestrator's state. For each non-`complete` row the orchestrator selects the next handoff based on which artifacts exist in `context/changes/<change-id>/`:

| State on disk | Next handoff | Status transitions to |
| --- | --- | --- |
| change folder missing | `/10x-new <change-id>` | `change opened` |
| `change.md` only | `/10x-research` (with a risks-to-verify brief) | `researched` |
| `+ research.md` | `/10x-plan` (with cost × signal + cookbook-update constraints) | `planned` |
| `+ plan.md` with pending `## Progress` items | `/10x-implement <change-id> phase <N>` | `implementing` / `complete` |
| `+ plan.md` fully `[x]` | Mark §3 row `complete`; loop to next pending row | — |

Each handoff is a **STOP point**. The orchestrator copies the next command to the clipboard, asks the user to `/clear` and run it, then exits. Re-invoke `/10x-test-plan` (no arguments) to advance.

### Risk-first prioritization rules

- Risks are **failure scenarios in user / business terms**, not test names. "Logged-out user reaches paid content via stale token" is a risk; "test the login form" is not.
- 5 to 7 risks. Fewer is too coarse; more makes prioritization useless.
- Impact and likelihood are user/business ratings, not technical complexity.
- Every risk traces to a source: PRD section, archived slice, roadmap entry, Phase 2 interview question, hot-spot **directory** with churn count, or a tech-stack constraint. No invented risks.
- **Signal, not knowledge.** §2 cites *evidence that raised the risk*, never a file as "where the failure lives." File:line anchors, function names, schema names, and module names are forbidden in §2 — they belong in `/10x-research`'s output, produced per rollout phase against current code. The plan is a QA spec; it is not a code audit.
- Coverage is not the metric. **Risk coverage** is the metric.

### Dual-layer mapping rules

- Classic layer first: the cheapest test that gives a real signal wins. Promote to e2e only when no cheaper layer covers the risk.
- AI-native layer second, and only where it adds signal classic tests do not give cheaply.
- Every AI-native row has a **"When NOT to use"** line. If you cannot write one, drop the row.
- Every tool name carries a `checked: <YYYY-MM-DD>` date. Tool names are examples of the category, not endorsements.
- Both layers must be non-empty in the final guide if the project warrants them. Classic-only is a 2020 plan; AI-native-only is hype. AI-native phases are not mandatory — include them only when the brief justified them under cost × signal.

### Quality gates rules

- Required gates (lint, typecheck, unit+integration, e2e on critical flows) must map to actual CI steps. If a required gate is not yet wired, mark it as `required after §3 Phase <N>` and let the named rollout phase wire it.
- Post-edit hook is **recommended local**, not a CI substitute.
- Multimodal visual review is **selective**, applied to 1–3 critical screens, not to every page.
- Vision-driven fallback (Anthropic Computer Use or OpenAI CUA) is reserved for DOM-unreachable surfaces; expensive per action.

### Cookbook patterns (§6) — fills in over time

`test-plan.md` is both a phased strategy and a **growing cookbook**. §6 starts as placeholders (`TBD — see §3 Phase <N>`) and fills in incrementally — each rollout phase's plan ends with a sub-phase that updates the relevant §6 entry (location, naming, reference test, run command). After Module 3 completes, §6 becomes the canonical answer to "how do I add a test for X in this project?" — and is what `/10x-tdd` reads in Lesson 2.

### Lesson boundaries

- Do not write test code. That is Lesson 2 (`/10x-tdd` and unit-test authoring).
- Do not configure hooks, hook lifecycle, or debugging hooks. That is Lesson 3.
- Do not configure MCP servers, Playwright API, e2e code, or multimodal scenario code. That is Lesson 4.
- Do not run the bug-to-fix-to-regression-test workflow. That is Lesson 5.
- Do not author CI/CD pipelines from scratch or write GitHub Actions YAML. The guide names gates; configuration is owned by Module 1 Lesson 5 and Module 2 Lesson 5.
- Do not benchmark multimodal models. Cite criteria (cost, latency, agent-friendliness), never a ranking.
- Do not read the codebase for knowledge (call graphs, schemas, "which file owns this failure"). That is `/10x-research`'s job, per rollout phase.

### Paths used by this lesson

- `context/foundation/test-plan.md` — the quality contract produced and maintained by `/10x-test-plan`
- `context/foundation/prd.md` — primary risk source
- `context/foundation/roadmap.md` — likelihood weighting
- `context/foundation/tech-stack.md` — stack input (when present)
- `context/archive/<change-id>/plan.md` — implemented risk surface
- `context/changes/<change-id>/` — per-rollout-phase change folder (one per row in §3)

<!-- END @przeprogramowani/10x-cli -->
