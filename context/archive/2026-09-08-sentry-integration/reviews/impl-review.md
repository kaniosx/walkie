<!-- IMPL-REVIEW-REPORT -->
# Implementation Review: Sentry Integration (O-01)

- **Plan**: context/changes/sentry-integration/plan.md
- **Scope**: Full plan (Phase 1 of 2, Phase 2 of 2)
- **Date**: 2026-09-08
- **Verdict**: NEEDS ATTENTION
- **Findings**: 0 critical, 1 warning, 1 observation

## Verdicts

| Dimension | Verdict |
|-----------|---------|
| Plan Adherence | PASS |
| Scope Discipline | PASS |
| Safety & Quality | PASS |
| Architecture | PASS |
| Pattern Consistency | PASS |
| Success Criteria | WARNING |

## Findings

### F1 — Production delivery/PII-scrubbing never actually observed

- **Severity**: ⚠️ WARNING
- **Impact**: 🔬 HIGH — architectural stakes; think carefully before deciding
- **Dimension**: Success Criteria
- **Location**: context/changes/sentry-integration/plan.md:23, 154-157 (Progress 2.4-2.7)
- **Detail**: The plan's "Desired End State" promises a hand-verified real event in Sentry with correct `environment`/`release` tags and no PII. That verification never happened — Render's free plan has no console (the planned trigger mechanism), and rather than substitute another trigger, the plan was closed without observing a single real event. Config values are unit-tested (mocked, no network); gems/rubocop/brakeman/bundler-audit are clean; `SENTRY_DSN` is set and a redeploy happened. But nothing confirms an exception actually reaches Sentry, carries correct tags, or that `send_default_pii = false` + the `filter_parameters` extension actually keep IP/lat/lng out of a real payload. A typo'd DSN, initializer load-order issue, or gap in PII suppression would pass every check run so far.
- **Fix A ⭐ Recommended**: Accept as a documented, known gap (already the decision made this session).
  - Strength: Zero extra work; `change.md` already records this explicitly as a closed-with-caveat decision.
  - Tradeoff: O-01's actual goal (errors reach a dashboard someone can act on) stays unproven until a real incident occurs.
  - Confidence: HIGH — matches the explicit choice already made earlier in this conversation.
  - Blind spot: No visibility into whether/when a natural exception will occur to close this gap organically.
- **Fix B**: Add a temporary, self-removing debug route to force one real event now.
  - Strength: Closes the actual gap — proves the whole pipeline (delivery + tags + PII scrubbing), not just config values.
  - Tradeoff: Another manual deploy/revert cycle on the free plan; briefly exposes an extra route (mitigate with a secret-token query-param gate).
  - Confidence: MEDIUM — straightforward to build, but declined twice this session already.
  - Blind spot: Haven't scoped the exact route/token implementation.
- **Decision**: ACCEPTED (Fix A) — documented known gap, no code change

### F2 — bundler-audit CVEs are pre-existing, unrelated to new gems

- **Severity**: 💡 OBSERVATION
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Safety & Quality
- **Location**: Gemfile.lock (net-imap transitive dep via mail/ActionMailer)
- **Detail**: Re-ran `bin/bundler-audit`: 3 CVEs on `net-imap` 0.6.4, all transitive via `mail`/Action Mailer, untouched by this diff — matches what Progress 1.5 already documented as out of scope. No new CVEs from the Sentry gems. Not actionable within this plan.
- **Fix**: No action needed within this change; track separately if/when the repo does a broader dependency-CVE sweep.
- **Decision**: SKIPPED
