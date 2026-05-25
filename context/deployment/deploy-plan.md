---
project: Walkie
deployed_at: 2026-05-25
platform: Render
region: frankfurt
status: live
url: https://walkie-web.onrender.com
runner: docker (./Dockerfile)
context_type: mvp-smoke
tech_stack_ref: context/foundation/tech-stack.md
infra_ref: context/foundation/infrastructure.md
---

## Outcome

Walkie's first end-to-end deploy is live on Render. `https://walkie-web.onrender.com/up` returns `HTTP/2 200` with Rails 8's health-check body (`<body style="background-color: green">`). `/` returns `404` — expected, `config/routes.rb` is still empty (no domain controllers exist yet).

This is a **smoke deploy on free-tier Postgres** — a deliberate deviation from `infrastructure.md` (which rejected the free tier for production due to 60s cold start + 30-day expire). It exists to validate the deploy pipeline end-to-end before any real MVP traffic.

## What's deployed

| | |
|---|---|
| Platform | Render |
| Region | Frankfurt (`fra`) |
| Web Service | `walkie-web` — runtime: Docker, plan: Starter ($7/mo) |
| Database | `walkie-postgres` — plan: **free**, PG 17, 1 GB |
| Image source | `./Dockerfile` at repo root (Rails 8 default with Thruster + Puma) |
| Deploy mode | Render Blueprint (`render.yaml` is the source of truth) |
| Auto-deploy | **off** (manual gate; toggle in service Settings when ready) |
| Healthcheck | `/up` (Rails 8 default) |

## Secrets wired

| Variable | Source | Set how |
|---|---|---|
| `DATABASE_URL` | `fromDatabase: walkie-postgres / connectionString` | Auto-populated by Render Blueprint |
| `RAILS_MASTER_KEY` | `config/master.key` (local file, `.gitignore`d) | Manually pasted in dashboard during Blueprint apply (`sync: false`) |
| `RAILS_LOG_LEVEL` | `info` | render.yaml literal |
| `WEB_CONCURRENCY` | `2` | render.yaml literal |
| `RAILS_MAX_THREADS` | `3` | render.yaml literal |

## What's intentionally NOT wired

- **`SOLID_QUEUE_IN_PUMA`** — omitted. `config/puma.rb:38` reads `if ENV["SOLID_QUEUE_IN_PUMA"]` which is truthy for any non-empty string (including `"false"`). Setting any value enables Solid Queue, and 5 worker threads collide with the `pool: 3` from `RAILS_MAX_THREADS=3`, causing boot crash. The Rails 8 convention is "set to truthy when on, omit when off". Re-add with `value: "true"` together with the Postgres upgrade (see Follow-ups).
- **Auto-deploy on push** — kept `autoDeploy: false`. Re-enable after first manual deploy through a few cycles confirms nothing else surprises.
- **Preview deploys** — Pro-tier feature; not needed for solo MVP.
- **Manual approval per deploy** — service Settings toggle; revisit when auto-deploy is on.
- **Billing alerts** — set thresholds at $30/$40 once we move off free Postgres.
- **Render MCP server** — optional agent integration, defer to after first stable week.

## Verification proof (2026-05-25)

```
$ curl -sI https://walkie-web.onrender.com/up
HTTP/2 200
x-runtime: 0.003884
server: cloudflare (Render origin behind CF edge)
strict-transport-security: max-age=63072000; includeSubDomains
x-frame-options: SAMEORIGIN
x-content-type-options: nosniff

$ curl -sI https://walkie-web.onrender.com/
HTTP/2 404 (no routes — expected)

$ curl -s https://walkie-web.onrender.com/up
<!DOCTYPE html><html><body style="background-color: green"></body></html>
```

Confirms: Rails boots, Postgres connection works (`db:prepare` in entrypoint succeeded with Solid stack migrations), `RAILS_MASTER_KEY` decrypts credentials so `secret_key_base` is available, Thruster proxies port 80 → Puma 3000 correctly, HSTS / security headers from Rails 8 defaults are intact.

## Deploy commits (audit trail)

| Commit | Purpose |
|---|---|
| `066bb6e` | Switch Postgres plan `basic-1gb` → `free` for first MVP smoke deploy |
| `910dbca` | (failed attempt) Set `SOLID_QUEUE_IN_PUMA: "false"` — turned out to be truthy in Ruby |
| `2cc8311` | Remove `SOLID_QUEUE_IN_PUMA` entirely; inline comment documents the gotcha |

## Accepted risks (active now)

These three from `infrastructure.md`'s Risk Register are **active** because of the free-tier choice:

1. **Solid Queue × free-tier connection pool** — mitigated by **disabling Solid Queue entirely** for now. Background jobs do not process. Acceptable because the repo has no models, no jobs.
2. **Postgres 30-day auto-expire** — provisioned 2026-05-25 → expires ~2026-06-24 with 14-day grace. **Calendar reminder needed at T-7 (2026-06-17)** for upgrade decision.
3. **Cold start ~60s breaks PRD "request-to-live in 30s"** criterion — acceptable for smoke; the PRD criterion is measured against the production tier, not the smoke tier.

## Follow-ups (in priority order)

1. **Calendar reminder 2026-06-17** — decide upgrade path (Basic-256MB $7 or Basic-1GB $20 per `infrastructure.md`). `infrastructure.md` recommends Basic-1GB because of the Solid Queue interaction.
2. **Re-enable Solid Queue with Postgres upgrade.** Steps:
   - Add `config/queue.yml` with concurrency capped to fit pool size.
   - Bump `RAILS_MAX_THREADS` so `pool >= max(puma_threads, solid_queue_threads)` per process.
   - Add `SOLID_QUEUE_IN_PUMA: "true"` back to `render.yaml`.
3. **Rename `bootstrap_scaffold_*` → `walkie_*`** in `docker-compose.yml` + `config/database.yml`. Dev/test only — prod uses `DATABASE_URL` so not blocking. CLAUDE.md tripwire.
4. **Delete `.git.scaffold/`** from repo root once diff against starter is no longer needed.
5. **Toggle `autoDeploy: true`** in `render.yaml` after a few manual deploys confirm stability. Combine with branch protection on `main` so agent-generated commits go through PR review.
6. **Pre-deploy migrations** — when domain models exist, decide whether migrations run in `buildCommand` (current default, dies the build on failure) or use Render's pre-deploy hook (Standard plan and above). For solo MVP, keeping migrations in entrypoint via `db:prepare` is fine; revisit when migrations get large/destructive.

## How this was deployed (replay)

For future-me when the platform changes or this needs to be reproduced:

1. Cleaned out any prior Walkie resources from Render dashboard (started from empty workspace).
2. `render.yaml` committed and pushed to `main` (commits above).
3. Render Dashboard → New + → Blueprint → connected `walkie` repo, branch `main`.
4. Render parsed `render.yaml`, prompted for `RAILS_MASTER_KEY` (the one `sync: false` secret) — pasted from `config/master.key`.
5. Render provisioned `walkie-postgres` (free, ~1 min on free tier to become Available).
6. Once DB was Available, Web Service build kicked off automatically (Dockerfile-based, ~4 min for first build including `bundle install` from cold).
7. First deploy crashed on Solid Queue boot (see commits above). Two iteration cycles resolved it.
8. After commit `2cc8311` synced via Blueprint, deploy went green. Verification ran 2026-05-25 ~07:51 UTC.
