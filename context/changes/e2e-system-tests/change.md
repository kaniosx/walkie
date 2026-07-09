---
change_id: e2e-system-tests
title: Add Rails System Tests (Capybara + Selenium) and a first browser-level e2e test
status: impl_reviewed
created: 2026-07-08
updated: 2026-07-09
archived_at: null
---

## Notes

User asked for "any e2e test" to exist in the project. This repo has no Node
toolchain (Propshaft + importmap, no Node bundler per CLAUDE.md), so
Playwright (the `/10x-e2e` skill's native tooling) was rejected in favor of
Rails' built-in System Tests (Capybara + Selenium, headless Chrome) — no
Node needed, runs via `bin/rails test:system` alongside the existing
Minitest suite.

Scope, as agreed with the user:
1. Add `capybara` + `selenium-webdriver` gems (test group).
2. Install Chromium in `Dockerfile.dev` so the `web` container can drive a
   real headless browser.
3. Rebuild the `web` image and `bundle install`.
4. Generate `test/application_system_test_case.rb` (Rails standard base
   class, headless Chrome driver).
5. Write ONE system test for a real full-journey flow — "Owner creates a
   walk request" (sign in → fill form → submit → see it listed) — through
   an actual rendered page, distinct from the existing ActionDispatch
   integration tests which don't exercise a real browser/JS layer.
6. Verify green, then a deliberate-break check (temporarily break the flow,
   confirm the test catches it, revert).

This is NOT part of the `context/foundation/test-plan.md` phased rollout
(that plan explicitly says "e2e | none planned" for v1, since the four core
flows are already covered by integration tests). This change is a
standalone infra + first-test addition requested directly by the user,
adapting `/10x-e2e`'s principles (risk-tied, role-based locators, real
boundaries, deliberate-break verification) to Capybara/Selenium since the
skill itself is Playwright-only.
