<!-- IMPL-REVIEW-REPORT -->
# Implementation Review: Static Walker↔Owner Distance Display

- **Plan**: context/changes/walker-owner-distance-display/plan.md
- **Scope**: Phase 1-4 of 4 (full plan)
- **Date**: 2026-09-07
- **Verdict**: NEEDS ATTENTION
- **Findings**: 0 critical, 2 warnings, 1 observation

## Verdicts

| Dimension | Verdict |
|-----------|---------|
| Plan Adherence | PASS |
| Scope Discipline | WARNING |
| Safety & Quality | WARNING |
| Architecture | PASS |
| Pattern Consistency | WARNING |
| Success Criteria | PASS |

## Findings

### F1 — broadcast crashes if a walk's own coordinates are nil

- **Severity**: ⚠️ WARNING
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Safety & Quality
- **Location**: app/models/walk.rb:147
- **Detail**: Phase 1 changed `distance_km_to` from silently-wrong 0.0-math to returning `nil` on any missing coordinate. `broadcast_open_requests_locality` still does `distance_km_to(...) <= MATCH_RADIUS_KM` with no nil check, so it now raises `NoMethodError` instead of the old (harmless) wrong number. A persisted Walk can't get nil lat/lng through the normal validated create path, but the model's own test suite proves it's reachable via `update_columns` (walk_test.rb:179) — bypassing validations the way `update_all` already does elsewhere in this model.
- **Fix**: `next if (d = distance_km_to(location[:latitude], location[:longitude])).nil? || d > MATCH_RADIUS_KM`
- **Decision**: FIXED

### F2 — nested distance turbo-frame reconnects on every broadcast

- **Severity**: ⚠️ WARNING
- **Impact**: 🔎 MEDIUM — real tradeoff; pause to reason through it
- **Dimension**: Pattern Consistency
- **Location**: app/views/walker_walks/_current_walk.html.erb:22-26
- **Detail**: The new `walker_current_walk_distance` frame (with `data-controller: walker-location`) sits inside the div that `Walk#broadcast_walker_current_walk` (walk.rb:160) replaces wholesale on every accept!/start!/complete!. Each such broadcast tears down and reconnects the Stimulus controller, re-triggering geolocation + a follow-up fetch just to refresh one line. `open_requests/index.html.erb:6-7` wraps its broadcast target from the *outside* with the same controller, so it initializes once per page load. Doesn't break anything already verified (Phase 3's manual checks covered initial page load, which never touches this broadcast path) — this only fires when the screen is open in a second tab/device during a transition.
- **Fix A ⭐ Recommended**: Leave as-is for now
  - Strength: Narrow blast radius (only affects a rare multi-tab/device scenario), no user-facing bug, and Phase 3's manual verification already passed on the primary flow.
  - Tradeoff: The inconsistency with the open_requests pattern persists as a minor footgun for the next person extending this view.
  - Confidence: MED — haven't tested the multi-tab scenario live, only traced the code path.
  - Blind spot: Whether a future feature makes this broadcast fire more often (e.g. more frequent walker-side updates), which would raise the cost of the churn.
- **Fix B**: Hoist the walker-location frame to wrap the broadcast target
  - Strength: Matches the open_requests pattern exactly; the frame initializes once and survives broadcasts untouched.
  - Tradeoff: Touches the boundary between two mechanisms (initial-load capture vs. live broadcast) that were each manually verified separately — restructuring risks a regression in either without re-running both manual checks.
  - Confidence: MED — the restructuring itself is a well-understood pattern (already proven at open_requests/index.html.erb), but this view's frame nesting is one level deeper.
  - Blind spot: Haven't manually re-verified either flow post-restructure.
- **Decision**: SKIPPED (chose Fix A — left as-is; narrow blast radius, no user-facing bug)

### F3 — unplanned but justified eager-load fix in the broadcast path

- **Severity**: 📝 OBSERVATION
- **Impact**: 🏃 LOW — informational only
- **Dimension**: Scope Discipline
- **Location**: app/models/walk.rb:169
- **Detail**: Phase 4's plan text names only the two controllers for the `:accepted_by_walker` eager-load fix. `broadcast_owner_active_walks` (Walk's private broadcast method, rendering the same two partials via Turbo Streams) was also fixed in the same commit — disclosed in the commit message, and correctly closes an N+1 gap the plan itself missed. No action needed. Separately, git history shows commit 7246852 (Phase 1) also bundled an unrelated full README.md rewrite and a roadmap.md update alongside the plan's own model change. The roadmap update is directly relevant documentation; the README rewrite is unrelated cleanup incidentally riding along. Already merged to main; no action recommended beyond awareness for future commit hygiene.
- **Decision**: ACKNOWLEDGED — no action needed
