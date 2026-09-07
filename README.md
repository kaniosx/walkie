# Walkie

Walkie is an MVP dog-walking marketplace. Owners post a walk request; walkers
within a 10km radius (browser-captured geolocation) can accept it, and the
walk moves through `REQUESTED → ACCEPTED → IN_PROGRESS → COMPLETED`.

Owner/walker accept flows and the open-requests list update live per-walker
over Turbo Streams — no page refresh needed to see a new request appear or
disappear.

The product brief lives in `idea-notes.md`; the locked PRD, roadmap, and
tech-stack rationale live in `context/foundation/`.

## Stack

Rails 8.1 · Ruby 3.4.9 · PostgreSQL 17 · Hotwire (Turbo + Stimulus) ·
Propshaft + importmap (no Node bundler) · Solid Queue / Solid Cache / Solid
Cable (DB-backed, no Redis) · Minitest · Kamal for deploy.

## Getting started

Development runs inside Docker via `docker-compose.yml` (services `web` and
`db`):

```sh
make start   # docker compose up — web on :3000, postgres on :5432
```

`db:prepare` runs automatically on container start. If migrations diverge or
the bundle cache goes stale:

```sh
make reset   # interactive: down -v, build --no-cache, up
```

For one-off Rails commands, exec into the `web` container (gems live in the
`bundle_cache` volume, not on the host):

```sh
docker compose exec web bin/rails console
docker compose exec web bin/rails db:migrate
docker compose exec web bin/rails test
docker compose exec web bundle exec rubocop
docker compose exec web bundle exec brakeman --no-pager
```

Run a single test file or line:

```sh
docker compose exec web bin/rails test test/models/walk_test.rb
docker compose exec web bin/rails test test/models/walk_test.rb:42
```

## Project docs

- `context/foundation/prd.md` — locked product requirements
- `context/foundation/roadmap.md` — delivered vs. planned slices
- `context/foundation/tech-stack.md` — why this stack
- `context/foundation/test-plan.md` — defined risks and their test coverage
- `CLAUDE.md` — conventions and tripwires for AI coding agents working in this repo
