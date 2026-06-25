# Test Plan

> Phased test rollout for this project. Strategy is frozen at the top
> (§1–§5); cookbook patterns at the bottom (§6) fill in as phases ship.
> Read before writing any new test.
>
> Refresh: re-run `/10x-test-plan --refresh` when stale (see §8).
>
> Last updated: 2026-06-25

---

## 1. Strategy

Tests follow three non-negotiable principles for this project:

1. **Cost × signal.** The cheapest test that gives a real signal for the
   risk wins. Do not promote to e2e because e2e "feels safer." Do not put a
   vision model on top of a deterministic visual diff that already catches
   the regression.
2. **User concerns are first-class evidence.** Risks anchored in "<the
   team is worried about X, and the failure would surface somewhere in
   <area>>" carry the same weight as PRD lines or hot-spot data.
3. **Risks are scenarios, not code locations.** This plan documents *what
   could fail* and *why we believe it's likely* — drawn from documents,
   interview, and codebase *signal* (churn, structure, test base). It does
   NOT claim to know which line owns the failure. That knowledge is
   produced by `/10x-research` during each rollout phase. If the plan and
   research disagree about where the failure lives, research is the
   ground truth.

Hot-spot scope used for likelihood weighting: `app/`, `test/` — 102 commits/30d.
Churn reflects implementation of S-04–S-09 over 30 days, not instability;
treat as signal for where the code is newest and least settled.

---

## 2. Risk Map

The top failure scenarios this project must protect against, ordered by
risk = impact × likelihood. Risks are failure scenarios in user / business
terms, not test names. The Source column cites the *evidence that surfaced
this risk* — never a specific file as "where the failure lives" (that is
research's job, see §1 principle #3).

| # | Risk (failure scenario) | Impact | Likelihood | Source (evidence — not anchor) |
|---|---|---|---|---|
| 1 | Second Walker accepts an already-ACCEPTED walk and receives no user-visible rejection — Singleness violated at the HTTP contract level | High | Medium | Interview Q1; PRD §Guardrails "single-Walker acceptance…binding outside the UI, not advisory hints"; roadmap §S-05 Risk "the genuine race is owned by walk_concurrency_test" |
| 2 | A Walker attempts a state transition for which the walk is not in the required state, and the controller returns a misleading or silent HTTP response — user cannot tell the action failed | High | Medium | Interview Q3 (state transition is where confidence is lowest); PRD §NFR "no externally observable path that lets a walk skip, repeat, or reverse states"; hot-spot dir `app/models/` (5 changes/30d on walk logic) |
| 3 | Owner B authenticates and sees walks created by Owner A in their history, or Walker B's history includes walks accepted by Walker A — cross-account data exposed | High | Medium | PRD §NFR "role separation never leaks"; roadmap §S-08 Risk "test must include Owner B cannot see Owner A's walk"; hot-spot dir `app/controllers/` (6 changes/30d on walk controller) |
| 4 | Walker B sends a start or complete action targeting a walk accepted by Walker A — the controller does not return 404, leaking the walk's existence to an unauthorized actor | High | Low | PRD §Guardrails (role separation); PRD US-03 "only the Walker who accepted the walk can move its state forward"; archived slice `walker-starts-and-completes-walk` (scoped find stated to produce 404s on foreign/completed walks) |
| 5 | PRD ≥80% coverage guardrail is advisory-only — COVERAGE_MIN defaults to 0; a regression in a core flow (create-request, accept, start, complete) can ship without the gate catching it | Medium | High | PRD §Success Criteria §Guardrails "≥ 80% test coverage on the four core flows"; `test/test_helper.rb` comment "dormant-but-wired coverage gate…once the flows it scopes to exist"; roadmap §F-03 |

### Risk Response Guidance

| Risk | What would prove protection | Must challenge | Context `/10x-research` must ground | Likely cheapest layer | Anti-pattern to avoid |
|---|---|---|---|---|---|
| #1 | POST accept on an ACCEPTED walk → user-visible "already accepted" alert; walk state and accepted_by_walker_id unchanged after the call | Do not assume the model-level concurrency test covers the HTTP contract — they test different layers; the model test proves DB integrity, the HTTP test must prove the user-visible outcome | Does any integration test cover the false-return path of the accept action? What does the controller assert on that branch? | Integration test (sequential HTTP; parallel race is already proven at the model layer) | Asserting walk state unchanged without also verifying the user-visible error message was actually rendered |
| #2 | Illegal transition attempt (e.g. complete on a REQUESTED walk, or start on an already-COMPLETED walk) → controller returns a clear error flash, not a silent 200 redirect | Do not assume DB rejection equals adequate user protection; the controller HTTP response is what the user sees, not what the DB rejected | What does the controller do when start!/complete! return false — does it redirect silently, flash an error, or return a 4xx? | Integration test (HTTP response + flash message for each false-return branch) | Only testing the happy path; never testing the false-return branch of the controller action |
| #3 | Owner B GETs /walks → zero rows from Owner A visible. Walker B GETs /walker_walks → zero rows from Walker A's history visible | Do not stop at asserting the right user's rows are present; only the absence of the wrong user's rows proves isolation | Exact query scoping in both controllers for active and past sections (are both sections scoped to current_user?) | Integration test (two-user setup; assert absence of cross-account rows in each section) | Asserting current user's rows ARE present without also asserting other users' rows are ABSENT |
| #4 | Walker B POSTs /walker_walks/:id/start where :id belongs to Walker A → HTTP 404 specifically; walk state unchanged | Do not accept "model guard makes HTTP test redundant" — the HTTP 404 is the client-visible security contract, independent of data integrity | Does WalkerWalksController use a scoped find that produces 404 on miss, or an unscoped find with a separate authorization check that might return a different status? | Integration test (assert HTTP 404 specifically, not just that state is unchanged) | Checking state unchanged without asserting the HTTP response code was 404 |
| #5 | `COVERAGE_MIN=80 bin/rails test` fails when a core flow has a coverage gap; CI enforces the env var as a required step | Do not assume a high total coverage percentage means the four core flows are covered — a high aggregate can mask zero coverage on a specific controller | Current actual SimpleCov line + branch % for the four core flow groups (Walk model, WalksController, OpenRequestsController, WalkerWalksController) | CI gate (enable the existing env var; no new test files required for the gate itself) | Measuring total coverage % without per-group breakdown from SimpleCov |

---

## 3. Phased Rollout

Each row is a discrete rollout phase that will open its own change folder
via `/10x-new`. Status moves left-to-right through the values below; the
orchestrator updates Status as artifacts appear on disk.

| # | Phase name | Goal (one line) | Risks covered | Test types | Status | Change folder |
|---|---|---|---|---|---|---|
| 1 | HTTP guardrails | Verify the Singleness HTTP contract, cross-account isolation, and the IDOR 404 contract at the integration layer | #1, #3, #4 | integration | complete | context/changes/testing-http-guardrails/ |
| 2 | State machine feedback | Verify the controller HTTP response for each false-return path in start, complete, and accept | #2 | integration + model | not started | — |
| 3 | Coverage gate wiring | Activate COVERAGE_MIN=80 in CI; verify per-group SimpleCov breakdown; make gate a required CI step | #5 | CI configuration | not started | — |

**Status vocabulary** (parser literals):

| Value | Meaning |
|---|---|
| `not started` | No change folder for this rollout phase yet. |
| `change opened` | `context/changes/<id>/` exists with `change.md`; research not done. |
| `researched` | `research.md` exists in the change folder. |
| `planned` | `plan.md` exists with a `## Progress` section. |
| `implementing` | Progress section has at least one `[x]` and at least one `[ ]`. |
| `complete` | Progress section is fully `[x]`. |

---

## 4. Stack

The classic test base for this project. No AI-native tools are planned;
the product has no AI/ML component (PRD §Non-Goals), and the risks are
fully addressable with deterministic integration and model tests.

| Layer | Tool | Version | Notes |
|---|---|---|---|
| unit + integration | Minitest | 6.0.6 | Built into Rails 8.1; `ActionDispatch::IntegrationTest` for HTTP-layer tests; `ActiveSupport::TestCase` for model tests |
| coverage | SimpleCov | 0.22.0 | Configured with `rails` profile + branch coverage; `COVERAGE_MIN` env var wired, defaults to `0` (dormant until Phase 3 activates it) |
| lint | RuboCop (rubocop-rails-omakase) | 1.86.2 | `docker compose exec web bundle exec rubocop` |
| security | Brakeman + bundler-audit | 8.0.5 | `docker compose exec web bundle exec brakeman --no-pager` |
| e2e | none planned | — | Turbo-driven UI; ActionDispatch integration tests cover the HTTP contract for all four core flows; no Capybara JS driver or Playwright needed for v1 risks |

**Stack grounding tools (current session):**
- Docs: none — no Context7 or framework docs MCP available in this session; checked: 2026-06-25
- Search: none — no Exa.ai or web search MCP available in this session; checked: 2026-06-25
- Runtime/browser: none — no Playwright MCP detected; checked: 2026-06-25
- Provider/platform: Slack, Linear, Notion MCPs present but not relevant to test tooling; checked: 2026-06-25

---

## 5. Quality Gates

The full set of gates that must pass before a change reaches production.
"Required after §3 Phase N" means the gate is enforced once that rollout
phase lands; before that, the gate is planned but not binding.

| Gate | Where | Required? | Catches |
|---|---|---|---|
| lint (RuboCop) | local + CI | required | style drift, omakase violations |
| security scan (Brakeman + bundler-audit) | local + CI | required | known CVEs, insecure patterns |
| unit + integration (Minitest) | local + CI | required after §3 Phase 1 | logic regressions in state machine and scoping queries |
| coverage floor (COVERAGE_MIN=80) | local + CI | required after §3 Phase 3 | core flows lacking test coverage, as specified in PRD §Guardrails |
| e2e on critical flows | — | not planned for v1 | integration tests cover all four core flows; promote to e2e if a Turbo-driven race cannot be expressed as an HTTP integration test |

---

## 6. Cookbook Patterns

How to add new tests in this project. Each sub-section is filled in once
the relevant rollout phase ships; before that, the sub-section reads
"TBD — see §3 Phase N."

### 6.1 Adding an integration test (HTTP-layer contract)

**Class**: `ActionDispatch::IntegrationTest`; files under `test/integration/`.

**Sign-in**: each test file defines a `sign_in_as(email)` helper that posts to `session_path` with a plaintext password — use inline `setup do` fixtures, not YAML; `has_secure_password` needs a real password, not a digest.

**Three core assertion patterns**:
- `assert_not_includes response.body, "name"` — absence proves cross-account isolation; always assert the wrong user's resource is absent, not just that the right user's resource is present
- `assert_response :not_found` — proves HTTP 404 for IDOR contract tests (scoped `where(...).find(id)` raises `RecordNotFound` → `ApplicationController#not_found`)
- `follow_redirect!` then `assert_includes response.body, "..."` — proves flash content is rendered after a redirect (inspect the body, not just the `flash` hash)

**Reference tests**: cross-account isolation → `walker_walks_test.rb:105-113`, `walks_test.rb:33-43`; IDOR 404 → `walker_walks_test.rb:63-67`, `:76-81`; flash after redirect → `open_requests_test.rb:55-67`.

### 6.2 Adding a model test (state machine or constraint)

TBD — see §3 Phase 2 for the state machine false-return pattern (illegal transition → model method returns false → controller path to test).

### 6.3 Enabling and verifying the coverage gate

TBD — see §3 Phase 3 for the COVERAGE_MIN=80 activation pattern and per-group SimpleCov breakdown verification.

### 6.4 Per-rollout-phase notes

(Fills in after each phase ships — anything surprising the rollout taught about test setup, fixture patterns, or edge cases worth knowing before adding similar tests.)

---

## 7. What We Deliberately Don't Test

Exclusions agreed during the rollout (Phase 2 interview, Q5). Future
contributors should respect these unless the underlying assumption changes.

- **Password reset flow** — the flow is present in the UI but email sending is inert in v1 (no mailer configured); there is no observable side effect to assert. Re-evaluate if an email adapter is added. (Source: Phase 2 interview Q5.)
- **Navigation link presence** — nav structure is stable and exercised by the existing `navigation_test.rb`; per-link assertions beyond what already exists are brittle and low-signal for v1. Re-evaluate if nav undergoes a structural redesign or a role-gating change. (Source: Phase 2 interview Q5.)

---

## 8. Freshness Ledger

- Strategy (§1–§5) last reviewed: 2026-06-25
- Stack versions last verified: 2026-06-25
- AI-native tool references last verified: 2026-06-25 (none in use)

Refresh (`/10x-test-plan --refresh`) when:

- a new top-3 risk surfaces from the roadmap or archive,
- a recommended tool's `checked:` date is older than three months,
- the project's tech stack changes (new framework, new test runner),
- §7 negative-space no longer matches what the team believes.
