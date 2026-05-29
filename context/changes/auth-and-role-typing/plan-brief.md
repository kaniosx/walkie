# F-01: Rails 8 Auth + Role-Typed Accounts — Plan Brief

> Full plan: `context/changes/auth-and-role-typing/plan.md`

## What & Why

Build Walkie's authentication foundation: bcrypt-hashed passwords, session-based sign-up/sign-in/sign-out, and a **binding role** (Owner XOR Walker) chosen at registration and immutable afterward. This is roadmap **F-01** — the first foundation on the critical path; every other slice needs an authenticated user with a role, so nothing user-facing can ship until this lands.

## Starting Point

A bare Rails 8.1.3 / Ruby 3.4.9 skeleton: only `ApplicationRecord` and a bare `ApplicationController`, routes limited to `/up`, no `db/migrate/`, no `test/` dir, and `bcrypt` commented out in the `Gemfile`. Rails 8's `bin/rails generate authentication` covers ~80% of the plumbing but omits sign-up, names the email column `email_address`, and exposes `Current.user` (not `current_user`).

## Desired End State

A visitor can sign up as Owner or Walker, sign in, and sign out; the chosen role is persisted, required, and unchangeable after creation; `current_user` and `require_authentication` are available app-wide; and a core Minitest suite covers the security-load-bearing behavior. Green test suite + clean rubocop/brakeman/bundler-audit + a working browser round-trip confirm it.

## Key Decisions Made

| Decision | Choice | Why (1 sentence) | Source |
| --- | --- | --- | --- |
| F-01 ↔ S-01 scope line | Thin registration in F-01 | Exercises the role column end-to-end so the foundation is truly testable; S-01 polishes UX | Plan |
| Role modeling | String-backed `enum`, NOT NULL, no default | Readable in DB dumps, reorder-safe, gives predicates/scopes; PRD's "one or the other" fits an enum | Plan |
| Naming contracts | Keep `email_address` + `Current.user`, add `current_user` helper | Stays on the generator's golden path while satisfying the roadmap's named hook | Plan |
| Password reset | Keep generated code, leave email inert | Honors §Access Control structurally without pulling an email dependency (FR-003) into v1 | Plan |
| Role immutability | Model-level readonly after create | Enforces "no role switching" outside the UI, cheaply and testably | Plan |
| Test scope | Core auth tests now, SimpleCov to F-03 | Auth is security-critical and shouldn't merge untested; F-03 later just measures the suite | Plan |
| DB-name tripwire | Left out of scope | Rename forces a volume wipe orthogonal to auth; tracked as a risk | Plan |

## Scope

**In scope:** User model + bcrypt; Session model + auth concern; `current_user`/`require_authentication`; string-enum `role` (required, immutable); thin sign-up path; sign-in/out; core auth tests.

**Out of scope:** Polished sign-up/sign-in UX (S-01); working password-reset email; domain models / authorization (F-02, slices); SimpleCov/CI (F-03); DB rename; STI / dual-role / role switching.

## Architecture / Approach

Run the Rails 8 auth generator for the golden-path scaffold, then make three additive changes: (1) a string-enum `role` column with a model-level immutability guard, (2) a thin `RegistrationsController` (`new`/`create`) that whitelists `role` only at registration and starts a session, (3) model + integration tests. Every generator default that becomes a downstream contract surface is preserved; only the roadmap-named `current_user` hook is added.

## Phases at a Glance

| Phase | What it delivers | Key risk |
| --- | --- | --- |
| 1. Auth foundation scaffold | Generator run, bcrypt bundled, auth concern + `current_user` wired, reset mailer inert | Bundle/Docker layer not refreshed → app won't boot with `has_secure_password` |
| 2. Role-typed User model | `role` migration (NOT NULL), enum, immutability guard | Role permitted on an update path later → silent role switching |
| 3. Sign-up (registration) path | RegistrationsController + route + minimal form + root landing | `role` accidentally whitelisted on a non-registration param path |
| 4. Guardrail verification & hardening | Auth-redirect + session round-trip tests; rubocop/brakeman/bundler-audit clean | Protected route missing the auth before-action → silent exposure |

**Prerequisites:** Docker stack runnable (`make start`); commands run via `docker compose exec web …` (no host toolchain).
**Estimated effort:** ~1–2 sessions across 4 phases (generator does the heavy lifting; tests are the bulk of the hand-written work).

## Open Risks & Assumptions

- **DB-name tripwire** (`bootstrap_scaffold_*` in `docker-compose.yml` + `database.yml`) is deliberately untouched here — must be cleared in a later change before it causes silent wrong-DB targeting.
- **bcrypt bundle refresh**: the running container's `bundle_cache` volume may need `bundle install` or a `make reset` after the generator uncomments the gem.
- **Password reset is structurally present but non-functional** until SMTP is configured — acceptable for the 2-test-user smoke, but not a real launch.
- Assumes the Rails 8.1 generator contract matches the documented behavior (User/Session/Current/Authentication/SessionsController/PasswordsController + routes); verify the generated files in Phase 1 before layering on top.

## Success Criteria (Summary)

- A visitor can sign up choosing Owner or Walker, sign in, and sign out — full browser round-trip works.
- The chosen role is persisted, required at creation, and cannot be changed afterward (verified by tests).
- Anonymous access to a protected route redirects to sign-in; `current_user`/`require_authentication` are available app-wide; suite + rubocop + brakeman + bundler-audit all clean.
