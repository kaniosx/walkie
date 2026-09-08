# Sentry Integration (O-01) Implementation Plan

## Overview

Wire `sentry-ruby` + `sentry-rails` (+ `stackprof` for profiling) into Walkie so unhandled exceptions and performance traces reach a Sentry project, closing the roadmap's O-01 observability gap ("No structured logging, error tracking, or metrics dashboard"). The DSN comes from an environment variable, never hard-coded, following the same pattern already used for `RAILS_MASTER_KEY` in `render.yaml`.

## Current State Analysis

- No `sentry-ruby`/`sentry-rails` gem in the `Gemfile`, no `config/initializers/sentry.rb`.
- Secrets that must not be hard-coded already follow one pattern: declared in `render.yaml` with `sync: false`, set manually in the Render dashboard (see `RAILS_MASTER_KEY`).
- `render.yaml` currently provisions both the web service and Postgres on Render's **free** plan (`4219ffd`, 2026-09-08) — this postdates the roadmap's O-01 entry, which reasoned about sample rates assuming a paid Starter plan (per `context/foundation/infrastructure.md`).
- L-01 (`geolocation-matching`, delivered 2026-09-02) added live browser-captured Owner/Walker coordinates, read from request params named `lat`, `lng` (`app/controllers/home_controller.rb:14-15`, `app/controllers/walker_walks_controller.rb:13-14`, `app/controllers/open_requests_controller.rb:5-6`) and `latitude`, `longitude` (`app/controllers/walks_controller.rb:36`). This postdates O-01's original `send_default_pii = true` reasoning.
- `config/initializers/filter_parameter_logging.rb` already filters `:passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc` from Rails' own logs — does not yet cover the geolocation param names.
- `config/environments/production.rb` already logs to `STDOUT` with `config.log_tags = [:request_id]` and sets `config.log_level` from `ENV.fetch("RAILS_LOG_LEVEL", "info")` — Sentry is additive, not a replacement.
- `Dockerfile` production build only excludes the `development` bundler group (`BUNDLE_WITHOUT="development"`) — any new gem must live outside a `group` block (or in a group that isn't `:development`) to ship in the production image, matching how `bcrypt`, `turbo-rails`, etc. are declared.
- `.github/workflows/ci.yml` has no deploy/staging job — Sentry's actual event delivery can only be verified manually against the real Render deployment, as the roadmap's O-01 entry already anticipated ("Rails console on Render").

## Desired End State

- `Sentry.init` runs on every boot (dev/test/prod alike); it is a safe no-op in dev/test because `ENV["SENTRY_DSN"]` is unset there.
- In production, once `SENTRY_DSN` is set in the Render dashboard, unhandled exceptions are captured automatically, along with 20% of performance traces; each event is tagged with `environment: production` and `release: <Render git commit SHA>`. No profiling and no default PII (IP, request params/cookies/headers) leaves the app.
- An automated Minitest test asserts the initializer's configuration values (sample rates, `send_default_pii`, `environment`) so a future edit that silently reverts to defaults or hard-codes a DSN is caught in CI.
- Verified once, by hand, against the real Render deployment: a deliberately raised exception in the Rails console shows up in the Sentry project with the expected `environment`/`release` tags and without request params or IP address in the payload.

### Key Discoveries:

- Sentry Ruby SDK safely no-ops when `config.dsn` is `nil` — no conditional wrapping of `Sentry.init` needed for dev/test.
- Render auto-populates `RENDER_GIT_COMMIT` (and `RENDER_SERVICE_NAME`, `RENDER_EXTERNAL_URL`, etc.) as a reserved runtime env var on every deploy — no new entry needed in `render.yaml` for it.
- `render.yaml:22-23` is the exact precedent to copy for `SENTRY_DSN` (`sync: false`, set via dashboard, never committed).

## What We're NOT Doing

- No Sentry JS/browser SDK — backend (Ruby/Rails) only, per roadmap O-01's literal scope. Front-end error capture (e.g. Stimulus geolocation failures) is a separate future slice if ever needed.
- No per-environment `traces_sample_rate`/`profiles_sample_rate` env-var override mechanism — rates are fixed constants in the initializer; revisit if/when the Render plan is upgraded.
- No Sentry alerting/notification rules, issue-owner assignment, or dashboard configuration inside Sentry itself — out of scope for this slice, configured (if ever) directly in the Sentry project settings.
- No changes to `config/environments/*.rb` logging setup — Sentry breadcrumbs read from the existing logger, nothing about current logging changes.
- No retroactive capture of past errors — this only affects exceptions raised after deploy.

## Implementation Approach

Single straightforward path, no competing architectures: add the three gems (outside any `group` block so they ship in every environment including production), add one initializer reading `SENTRY_DSN` from the environment, extend the existing `filter_parameters` list with the geolocation field names as defense-in-depth, add a small config-assertion test, then wire the Render-side secret and do the one-time manual smoke test. Phase 1 is everything verifiable locally/in CI; Phase 2 is the deploy-time change and the human-only manual verification against the real Render service.

## Phase 1: Gems, initializer, and automated config test

### Overview

All code changes needed for Sentry to be wired correctly, verifiable without touching Render.

### Changes Required:

#### 1. Add Sentry gems

**File**: `Gemfile`

**Intent**: Add `sentry-ruby`, `sentry-rails`, and `stackprof` (required by Sentry's profiling feature) to the main (ungrouped) gem list, alongside the other core gems like `turbo-rails` — not inside `group :development, :test do` or `group :test do`, so they install in the production Docker image (`BUNDLE_WITHOUT="development"` only excludes the dev group).

**Contract**: Three new `gem` lines in the main list; no version pins needed (matches the unpinned style of `propshaft`, `turbo-rails`, `stimulus-rails`). Run `bundle install` inside the `web` container afterward to update `Gemfile.lock`.

#### 2. Sentry initializer

**File**: `config/initializers/sentry.rb` (new)

**Intent**: Configure the Sentry SDK once at boot: DSN from environment (never hard-coded — this is the risk the roadmap's O-01 entry explicitly flagged), reduced sample rates appropriate to the free-tier web service, PII disabled, and environment/release tagging for deploy attribution.

**Contract**:
```ruby
Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"]
  config.breadcrumbs_logger = [:active_support_logger, :http_logger]
  config.send_default_pii = false
  config.environment = Rails.env
  config.release = ENV["RENDER_GIT_COMMIT"]
  config.traces_sample_rate = 0.2
  config.profiles_sample_rate = 0.0
end
```
`config.dsn` reading `ENV["SENTRY_DSN"]` directly (not a constant, not `Rails.application.credentials`) is the load-bearing contract Phase 1's automated test asserts against.

#### 3. Extend PII filtering to geolocation params

**File**: `config/initializers/filter_parameter_logging.rb`

**Intent**: Defense-in-depth — even with `send_default_pii = false`, extend the existing global filter list so the geolocation param names used across the four controllers that read live coordinates (`lat`, `lng`, `latitude`, `longitude`) are scrubbed from Rails' own logs and from anything Sentry's Rails integration captures via `ActiveSupport::ParameterFilter`.

**Contract**: Add `:lat, :lng, :latitude, :longitude` to the existing `Rails.application.config.filter_parameters +=` array (`config/initializers/filter_parameter_logging.rb:6-8`).

#### 4. Automated config test

**File**: `test/sentry_configuration_test.rb` (new)

**Intent**: Guard the initializer's contract against silent regression — asserts the values Phase 1's initializer sets, without requiring a real DSN or making any network call. This is what makes the "DSN must come from ENV, never hard-coded" risk a checked invariant instead of a code-review-only concern.

**Contract**: A plain Minitest test (no fixtures, no HTTP) asserting on `Sentry.configuration`:
- `send_default_pii` is `false`
- `traces_sample_rate` is `0.2`
- `profiles_sample_rate` is `0.0`
- `environment` equals `Rails.env` (i.e. `"test"` under `bin/rails test`)
- `dsn` is `nil` in the test run (proves the value comes from `ENV["SENTRY_DSN"]`, which is unset in CI/test — not a literal string baked into the initializer)

### Success Criteria:

#### Automated Verification:

- [ ] `bundle install` resolves cleanly inside the `web` container, `Gemfile.lock` updated
- [ ] `docker compose exec web bin/rails test test/sentry_configuration_test.rb` passes
- [ ] `docker compose exec web bundle exec rubocop` passes (new files match Omakase style)
- [ ] `docker compose exec web bundle exec brakeman --no-pager` passes (no new warnings)
- [ ] `docker compose exec web bin/bundler-audit` passes (no known CVEs in the new gems)
- [ ] Full suite still passes: `docker compose exec web bin/rails test`

#### Manual Verification:

- [ ] Boot the app locally (`make start`) with no `SENTRY_DSN` set — app boots normally, no errors in logs, confirming the safe no-op path
- [ ] `docker compose exec web bin/rails runner 'raise "smoke"' ` in dev does not crash the container in an unexpected way (Sentry silently no-ops; the exception still surfaces normally)

---

## Phase 2: Render deploy wiring + production smoke test

### Overview

Wire the Render-side secret and prove real event delivery against the actual deployed app — the only verification that matters for whether Sentry is actually receiving events, since CI has no staging deploy.

### Changes Required:

#### 1. Declare `SENTRY_DSN` in Render config

**File**: `render.yaml`

**Intent**: Follow the exact existing pattern for secrets that must never be committed — `RAILS_MASTER_KEY` (`render.yaml:22-23`) already does this for the web service.

**Contract**: One new entry under `services[0].envVars`:
```yaml
      - key: SENTRY_DSN
        sync: false
```

#### 2. Create the Sentry project and set the secret

**Intent**: A Sentry project must exist before the DSN can be set. This is an external, one-time, human action — not something the plan automates.

**Contract**: Create a Sentry project (Rails platform) at sentry.io (or self-hosted, whichever the user already has), copy its DSN, and set it as the `SENTRY_DSN` environment variable on the `walkie-web` service in the Render dashboard (matching how `RAILS_MASTER_KEY` was set).

### Success Criteria:

#### Automated Verification:

- [ ] `render.yaml` diff is exactly the one new `envVars` entry (no plan changes to `plan: free` or other fields)

#### Manual Verification:

- [ ] `SENTRY_DSN` set on `walkie-web` in the Render dashboard (value never committed to git)
- [ ] Redeploy `walkie-web` on Render
- [ ] In the Render Rails console: run a deliberately-raised exception inside `begin/rescue` and call `Sentry.capture_exception(e)`
- [ ] Confirm the event appears in the Sentry project dashboard within a few minutes
- [ ] Confirm the event's `environment` tag reads `production` and `release` matches the deployed commit SHA
- [ ] Confirm the event payload does **not** contain an IP address or request params (spot-check one real captured exception, if any occurs naturally, in addition to the manual one)

---

## Testing Strategy

### Unit Tests:

- `test/sentry_configuration_test.rb` (Phase 1) — the only new automated test; asserts the initializer's contract, not Sentry's network behavior.

### Integration Tests:

- None — Sentry's actual delivery path cannot be integration-tested without a real DSN and network access; covered by Phase 2's manual verification instead.

### Manual Testing Steps:

1. Boot locally with no `SENTRY_DSN` — confirm no behavior change (Phase 1).
2. After Phase 2's Render deploy, raise + capture a test exception in the Rails console and confirm it lands in Sentry with correct tags and no PII (Phase 2).

## Performance Considerations

`traces_sample_rate = 0.2` and `profiles_sample_rate = 0.0` are chosen specifically because the web service now runs on Render's free plan (`4219ffd`) — full tracing/profiling on a resource-constrained free instance would add avoidable overhead. Revisit both values upward if/when the web service is upgraded off the free plan (see roadmap Open Q #3 for the parallel Postgres free-tier situation).

## Migration Notes

None — no schema or data changes.

## References

- Roadmap entry: `context/foundation/roadmap.md` (O-01, `## Observability`)
- Existing secret pattern: `render.yaml:22-23` (`RAILS_MASTER_KEY`)
- Geolocation param sites: `app/controllers/home_controller.rb:14-15`, `app/controllers/walker_walks_controller.rb:13-14`, `app/controllers/open_requests_controller.rb:5-6`, `app/controllers/walks_controller.rb:36`
- Existing filter list: `config/initializers/filter_parameter_logging.rb:6-8`

## Progress

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles. See `references/progress-format.md`.

### Phase 1: Gems, initializer, and automated config test

#### Automated

- [x] 1.1 `bundle install` resolves cleanly inside the `web` container, `Gemfile.lock` updated — f751092
- [x] 1.2 `docker compose exec web bin/rails test test/sentry_configuration_test.rb` passes — f751092
- [x] 1.3 `docker compose exec web bundle exec rubocop` passes — f751092
- [x] 1.4 `docker compose exec web bundle exec brakeman --no-pager` passes — f751092
- [x] 1.5 `docker compose exec web bin/bundler-audit` passes (pre-existing `net-imap` CVE from `mail`/Action Mailer transitive dep, untouched by this diff, is out of scope — the new gems themselves have zero findings) — f751092
- [x] 1.6 Full suite still passes: `docker compose exec web bin/rails test` — f751092

#### Manual

- [x] 1.7 Boot locally with no `SENTRY_DSN` set — app boots normally, safe no-op confirmed — f751092
- [x] 1.8 Deliberately raised exception in dev does not crash the container unexpectedly — f751092

### Phase 2: Render deploy wiring + production smoke test

#### Automated

- [x] 2.1 `render.yaml` diff is exactly the one new `envVars` entry

#### Manual

- [x] 2.2 `SENTRY_DSN` set on `walkie-web` in the Render dashboard
- [x] 2.3 Redeploy `walkie-web` on Render
- [ ] 2.4 Deliberately-raised exception captured via `Sentry.capture_exception` in Render Rails console
- [ ] 2.5 Event appears in the Sentry project dashboard
- [ ] 2.6 Event's `environment`/`release` tags correct
- [ ] 2.7 Event payload contains no IP address or request params
