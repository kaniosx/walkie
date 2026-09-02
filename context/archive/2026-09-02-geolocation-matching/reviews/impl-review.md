<!-- IMPL-REVIEW-REPORT -->
# Implementation Review: Geolocation-Radius Walker↔Owner Matching

- **Plan**: context/changes/geolocation-matching/plan.md
- **Scope**: Full plan (Phases 1–5)
- **Date**: 2026-09-02
- **Verdict**: NEEDS ATTENTION
- **Findings**: 0 critical, 3 warnings, 4 observations

## Verdicts

| Dimension | Verdict |
|-----------|---------|
| Plan Adherence | PASS |
| Scope Discipline | WARNING |
| Safety & Quality | WARNING |
| Architecture | PASS |
| Pattern Consistency | PASS |
| Success Criteria | PASS |

## Findings

### F1 — Malformed lat/lng params crash with an unhandled 500

- **Severity**: WARNING
- **Impact**: LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Safety & Quality
- **Location**: app/controllers/open_requests_controller.rb:7-9, app/controllers/home_controller.rb:14-16
- **Detail**: `params[:lat]`/`params[:lng]` are passed straight into `Walk.open_nearby` as SQL bind values and into `WalkerLocationCache.write` (which calls `.to_f`) with no numeric validation. A request with a non-numeric value (e.g. `?lat=abc&lng=1`, trivial to construct outside the JS flow) makes Postgres fail casting the bind param, raising `ActiveRecord::StatementInvalid` — unrescued anywhere in `ApplicationController` (only `RecordNotFound` is rescued) — so it surfaces as a raw 500. No test exercises this path.
- **Fix**: Coerce with `Float(params[:lat], exception: false)` / `Float(params[:lng], exception: false)` in both controllers; treat a `nil` result the same as absent params (fall through to the existing "getting your location" / placeholder branch) instead of hitting the DB or cache with unparseable input.
- **Decision**: FIXED — added `coerce_coordinate` to `ApplicationController`, used it in both `OpenRequestsController#index` and `HomeController#index`; added regression tests to `test/integration/open_requests_test.rb` and `test/controllers/home_controller_test.rb`.

### F2 — Postcode-removal migration isn't safely reversible against a populated `users` table

- **Severity**: WARNING
- **Impact**: MEDIUM — real tradeoff; pause to reason through it
- **Dimension**: Safety & Quality
- **Location**: db/migrate/20260902102033_remove_postcode_from_users_and_walks.rb
- **Detail**: `remove_column :users, :postcode, :string, null: false` auto-generates a down-migration of `add_column :users, :postcode, :string, null: false` with no default. If this migration is ever rolled back against a database with existing `users` rows, it fails with a `NOT NULL` violation. `walks.postcode` (nullable) has no such issue — only the `users` side is affected.
- **Fix A ⭐ Recommended**: Make the irreversibility explicit — add a comment above the `users` column removal noting postcode is permanently retired (per the plan: "postcode removal has nothing to preserve"), and/or raise `ActiveRecord::IrreversibleMigration` in an explicit `down` instead of relying on Rails' auto-inverse.
  - Strength: Matches the actual design intent already stated in the plan; turns a confusing NOT-NULL error deep in Postgres into a clear, intentional failure message if anyone ever tries to roll back.
  - Tradeoff: A genuine emergency rollback still isn't possible — but it silently isn't possible today either, so this just makes that honest instead of surprising.
  - Confidence: HIGH — standard Rails pattern for a deliberately one-way migration.
  - Blind spot: Haven't checked whether this app's Kamal deploy process ever performs automatic migration rollbacks.
- **Fix B**: Give the down-migration a default so re-adding the column succeeds on a populated table (`add_column :users, :postcode, :string, default: "", null: false` in an explicit `down`).
  - Strength: Preserves true reversibility.
  - Tradeoff: Reintroduces a meaningless empty-string default across every existing row — contradicts the "removed for good" intent and pollutes data if it's ever actually invoked.
  - Confidence: MEDIUM — works mechanically but fights the feature's actual design.
  - Blind spot: None significant.
- **Decision**: FIXED via Fix A — split into explicit `up`/`down`, `down` raises `ActiveRecord::IrreversibleMigration` with a comment pointing back to the plan.

### F3 — Scope extensions beyond the plan's literal text (all justified in commit messages)

- **Severity**: OBSERVATION
- **Impact**: LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Scope Discipline
- **Location**: app/assets/tailwind/application.css (052db01); app/views/dogs/index.html.erb (6f5810b); app/views/open_requests/_list.html.erb + app/views/home/index.html.erb `data-turbo-frame="_top"` additions (dce4628); test/test_helper.rb (f174384); config/brakeman.ignore fingerprint churn (052db01)
- **Detail**: A handful of changes fall outside the plan's literal "Changes Required" text: a pre-existing Tailwind v3→v4 directive bug fix (unrelated, opportunistic, was blocking all system tests); the same geolocation-gating treatment applied to a second "Walk my dog" button on `dogs/index.html.erb` not named in the plan; `data-turbo-frame="_top"` added to the Accept button and "See open walk requests" link once those controls got nested inside Phase 4's new turbo-frames (required for correct navigation scoping); and the `Rails.cache.clear` test-suite fix (see F-adjacent note below). Every one of these is explained in its commit message and none violate the plan's "What We're NOT Doing" boundaries.
- **Fix**: None needed — informational only, already well-documented in commit history.
- **Decision**: SKIPPED

### F4 — Per-in-radius-walker requery inside the broadcast fan-out

- **Severity**: OBSERVATION
- **Impact**: LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Safety & Quality
- **Location**: app/models/walk.rb:127-142
- **Detail**: For every in-radius walker found, `broadcast_open_requests_locality` issues a full `Walk.open_nearby(...).includes(:dog)` query — N DB round-trips per broadcast event (N = same-city walkers with a live cache entry). Synchronous and bounded, consistent with R-01's existing broadcast design; this is beyond the plan's stated cost model (which only discusses `cable` table row growth) but acceptable at the PRD's target scale.
- **Fix**: None needed now; revisit if walker density per city grows significantly (matches the plan's own stated caveat).
- **Decision**: SKIPPED

### F5 — No `(role, city)` composite index backing the broadcast fan-out scan

- **Severity**: OBSERVATION
- **Impact**: LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Safety & Quality
- **Location**: app/models/walk.rb:128 (`User.walker.where(city: city).find_each`)
- **Detail**: Only `users.email_address` is indexed (`db/schema.rb:48`), so this scan is sequential. Already flagged and explicitly accepted in the plan's own Performance Considerations section — not a new gap introduced by implementation.
- **Fix**: None needed — already an accepted tradeoff in the plan.
- **Decision**: SKIPPED

### F6 — Geolocation error handler collapses all error codes into one generic message

- **Severity**: OBSERVATION
- **Impact**: LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Safety & Quality
- **Location**: app/javascript/controllers/owner_location_controller.js, app/javascript/controllers/walker_location_controller.js
- **Detail**: Both Stimulus controllers' `getCurrentPosition` error callback shows the same "location required" message regardless of `error.code` — `PERMISSION_DENIED`, `POSITION_UNAVAILABLE`, and `TIMEOUT` are all indistinguishable to the user. Minor UX imprecision, not a functional bug.
- **Fix**: Optionally branch on `error.code` for a more specific message; not required for MVP.
- **Decision**: SKIPPED

## Success criteria verification

- `bin/rails db:migrate:status` — all 10 migrations `up`, clean.
- `bin/rails test` — 127 runs, 527 assertions, 0 failures.
- `bin/rails test:system` — 11 runs, 68 assertions, 0 failures (includes the new two-session live-broadcast test).
- `bundle exec rubocop` — 83 files inspected, no offenses.
- `bundle exec brakeman --no-pager` — 0 security warnings.
- All Manual Verification items across all 5 phases are checked `[x]` in the plan's Progress section, each with observable evidence in the corresponding commit (browser-tested flows described in commit messages / this session's confirmed manual pass for Phase 5).
