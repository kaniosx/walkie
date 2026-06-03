<!-- IMPL-REVIEW-REPORT -->
# Implementation Review: F-02 Domain Data Schema — Dog + Walk + State Machine + DB-level Invariants

- **Plan**: context/changes/domain-schema-walks-and-dogs/plan.md
- **Scope**: All 4 phases (complete)
- **Date**: 2026-06-03
- **Verdict**: APPROVED (address F1 before S-05 wires up accept!)
- **Findings**: 0 critical, 2 warnings, 2 observations

## Verdicts

| Dimension | Verdict |
|-----------|---------|
| Plan Adherence | PASS |
| Scope Discipline | PASS |
| Safety & Quality | WARNING |
| Architecture | PASS |
| Pattern Consistency | PASS |
| Success Criteria | PASS |

## Findings

### F1 — accept! skips the role / owner≠walker validations, and the DB can't catch them

- **Severity**: ⚠️ WARNING
- **Impact**: 🔎 MEDIUM — real tradeoff; pause to reason through it
- **Dimension**: Safety & Quality
- **Location**: app/models/walk.rb:33-37 (accept!), 58-65 (swap_state)
- **Detail**: accept! transitions via update_all, which skips AR validations. The validators walker_is_not_owner, owner_has_owner_role, walker_has_walker_role (walk.rb:75-89) never run on the transition path. The DB CHECK constraints only enforce state↔walker-presence and valid-state membership — not owner_id != accepted_by_walker_id, nor walker role. accept!'s WHERE guard is `{}`, so it binds any user id. `walk.accept!(the_owner)` and `walk.accept!(a_user_with_owner_role)` both persist clean (state='accepted' + non-null walker satisfies walks_walker_presence). Latent (no caller yet; controller authz scoped to S-05), but the method comment overstates the guarantee for accept!.
- **Fix A ⭐ Recommended**: Add a cheap pre-guard to accept! — `return false unless walker.walker? && walker.id != owner_id`.
  - Strength: Restores the "binding outside the UI" guarantee for the two invariants the DB can't express. Race-free — role is immutable (User#role_is_immutable) and owner_id fixed at create, so no TOCTOU.
  - Tradeoff: One extra line + a test; trusts the passed-in user object's role.
  - Confidence: HIGH — leans on guarantees already enforced in this repo.
  - Blind spot: None significant for the model layer.
- **Fix B**: Leave model as-is; document the trust boundary and rely on S-05 controller role-gating.
  - Strength: Matches the plan's "controller-level role gating lives in the slices"; zero model change.
  - Tradeoff: accept!'s comment overstates its guarantee; every future caller must gate correctly.
  - Confidence: MED — depends on each caller doing the right thing.
  - Blind spot: Non-controller callers (console, jobs) could bypass.
- **Decision**: FIXED via Fix A — pre-guard added to accept! (walk.rb), regression test added (walk_test.rb)

### F2 — Concurrency test teardown has no rollback safety net + fixed emails

- **Severity**: ⚠️ WARNING
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Reliability (test)
- **Location**: test/models/walk_concurrency_test.rb:9, 25-29
- **Detail**: use_transactional_tests=false means no rollback. Minitest runs teardown even on body failure, so realistic leak risk is narrow (teardown raising, or setup failing mid-way). Fixed emails (race-owner@…, racer#{i}@…) turn any leaked row into a confusing uniqueness collision in a later run. delete_all ordering (walks→dogs→users) is correct for RESTRICT FKs.
- **Fix**: Acceptable as-is for one isolated test; if the class grows, scope deletes by a unique per-run email prefix.
- **Decision**: FIXED — dedicated EMAIL_DOMAIN + purge_fixtures called in setup (self-healing) and teardown; verified by running the test twice consecutively.

### F3 — Walk tests inline User.create! instead of a builder helper

- **Severity**: ◽ OBSERVATION
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Pattern Consistency
- **Location**: test/models/walk_test.rb:5-12 (and constraints/concurrency setups)
- **Detail**: dog_test.rb follows user_test.rb's build_* helper convention, but the Walk tests repeat 4-arg User.create! password boilerplate inline in setup. Works fine; less DRY than the sibling convention.
- **Fix**: Optional — extract build_owner/build_walker helper if it sprawls.
- **Decision**: SKIPPED — low-value churn; inline setups are clear enough.

### F4 — deactivate! runs validations; Walk transitions deliberately don't

- **Severity**: ◽ OBSERVATION
- **Impact**: 🏃 LOW — quick decision; fix is obvious and narrowly scoped
- **Dimension**: Data safety
- **Location**: app/models/dog.rb:17-19
- **Detail**: deactivate! uses update! (validations run); Walk's transitions use update_all (validations skipped). Benign asymmetry — soft-deleting a dog whose name was somehow blanked would raise instead of deactivating.
- **Fix**: No action needed; flagged for awareness.
- **Decision**: SKIPPED — asymmetry is intentional; both choices fit their context.
