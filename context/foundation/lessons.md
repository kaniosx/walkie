# Lessons Learned

> Append-only register of recurring rules and patterns. Re-read at start by /10x-frame, /10x-research, /10x-plan, /10x-plan-review, /10x-implement, /10x-impl-review.

## SimpleCov's coverage gate silently no-ops under `bin/rails test`

- **Context**: test/test_helper.rb — wiring a SimpleCov `minimum_coverage` gate for a Minitest suite run via `bin/rails test` (the runner `bin/ci` and GitHub Actions both invoke).
- **Problem**: SimpleCov's `minimum_coverage` registers an `at_exit` that sets a non-zero exit on a coverage miss, but Minitest's autorun installs a *later* `at_exit` calling `exit exit_code`, which overrides SimpleCov's status. The gate works under bare `ruby -Itest` but silently passes (exit 0) under `bin/rails test` — so a "wired" coverage gate can be decorative without anyone noticing.
- **Rule**: When enforcing a SimpleCov `minimum_coverage` gate in a Rails Minitest suite, re-assert the exit status inside `Minitest.after_run` (runs before Minitest's final `exit`): guard with `SimpleCov.result?`, then `Kernel.exit(SimpleCov.result_exit_status(SimpleCov.result))` when non-zero. Verify the gate actually fails by forcing a high threshold (e.g. COVERAGE_MIN=95 → expect non-zero exit) — don't trust that `minimum_coverage` alone gates CI.
- **Applies to**: Rails + Minitest + SimpleCov coverage gates (test_helper.rb, CI runners).
