---
date: 2026-06-25T00:00:00+02:00
researcher: Claude (claude-sonnet-4-6[1m])
git_commit: dbe36a72193bc7ec56fbbba2f1a8b68be0df942b
branch: main
repository: walkie
topic: "HTTP guardrails — Singleness, cross-account isolation, and IDOR 404"
tags: [research, testing, integration, open_requests, walker_walks, walks, isolation, idor]
status: complete
last_updated: 2026-06-25
last_updated_by: Claude (claude-sonnet-4-6[1m])
---

# Research: HTTP Guardrails — Phase 1 Coverage Audit

**Date**: 2026-06-25
**Git Commit**: dbe36a72193bc7ec56fbbba2f1a8b68be0df942b
**Branch**: main
**Repository**: walkie

## Research Question

Ground rollout Phase 1 of `context/foundation/test-plan.md`. For each of Risks #1,
#3, and #4, trace the real failure path in code, quote relevant lines, assess existing
test coverage, and identify exactly what (if anything) is missing.

---

## Summary

**Two of three risks are already fully covered. One has a single narrow gap.**

| Risk | Finding | New test needed? |
|------|---------|-----------------|
| #1 Singleness HTTP contract | Fully covered by `open_requests_test.rb:55-67` | **No** |
| #3 Cross-account isolation | Owner both sections ✓; Walker past section ✓; Walker **active** section **missing** | **Yes — one test** |
| #4 IDOR 404 contract | Fully covered by `walker_walks_test.rb:63-67` and `:76-81` | **No** |

The `/10x-plan` for Phase 1 has **minimal scope**: add one integration test for the walker
active-section isolation gap, update §6.1 cookbook with the integration-test pattern, and
explicitly document that Risks #1 and #4 are already closed.

---

## Detailed Findings

### Risk #1 — Singleness HTTP Contract

**Failure scenario**: Second walker accepts an already-ACCEPTED walk and receives no
user-visible rejection.

#### Code path

`app/controllers/open_requests_controller.rb`:
```ruby
# line 11
walk = Walk.find(params[:id])   # unscoped — intentional, any walker can see open reqs

# lines 17-21
if walk.accept!(current_user)
  redirect_to open_requests_path, notice: "You accepted the walk for #{walk.dog.name}."
else
  redirect_to open_requests_path, alert: "Sorry, that walk was just accepted by someone else."
end
```

`app/models/walk.rb`:
```ruby
# lines 47-56 — accept! is the atomic compare-and-swap
def accept!(walker)
  return false unless walker.walker? && walker.id != owner_id
  swap_state(from: "requested", to: "accepted", ...)
end

# lines 77-83 — swap_state returns false when affected == 0
def swap_state(from:, to:, guard:, set:)
  attrs = set.merge(state: to, updated_at: Time.current)
  affected = self.class.where(id: id, state: from, **guard).update_all(attrs)
  return false unless affected == 1
  reload
  true
end
```

When a walk is already `accepted`, `swap_state` fires:
`WHERE id=X AND state='requested'` — state is `'accepted'` → 0 rows matched → `affected = 0`
→ `accept!` returns `false` → controller renders the alert.

#### Why the model-layer concurrency test is NOT a substitute

`test/models/walk_concurrency_test.rb` proves one winner at the **DB/model layer** with no
HTTP in the path (`ActiveSupport::TestCase`, `use_transactional_tests = false`, raw threads).
It does not prove that the controller renders a user-visible message or that the flash reaches
the browser. These are different layers.

#### Existing test coverage

`test/integration/open_requests_test.rb:55-67` — **fully covers this risk**:

```ruby
test "accepting an already-accepted walk shows 'already accepted' and does not change it" do
  @match.accept!(@walker2)              # walker2 wins first (model layer, no HTTP)

  sign_in_as "walker@example.com"
  post accept_open_request_path(@match)
  assert_redirected_to open_requests_path
  follow_redirect!
  assert_includes response.body, "just accepted by someone else"   # user-visible message ✓

  @match.reload
  assert @match.accepted?                                           # state unchanged ✓
  assert_equal @walker2.id, @match.accepted_by_walker_id, "original acceptance must stand"  # accepted_by_walker_id unchanged ✓
end
```

This test:
- Makes a real HTTP POST (ActionDispatch::IntegrationTest)
- Follows the redirect and inspects the rendered page body (not just flash value)
- Asserts the user-visible message was rendered
- Asserts both state and `accepted_by_walker_id` are unchanged

**Verdict: CLOSED. No new test required.**

**Test-plan guidance correction**: The plan said "challenge assumption that model-layer
concurrency test covers the HTTP contract." That challenge is warranted — but the HTTP-layer
test already exists and passes it. The two layers are independently tested.

---

### Risk #3 — Cross-Account Isolation

**Failure scenario**: Owner B sees Owner A's walks, or Walker B sees Walker A's walk history.

#### Code path — Owner (WalksController)

`app/controllers/walks_controller.rb`:
```ruby
# lines 5-9
@active_walks = current_user.owned_walks.active.includes(:dog).order(created_at: :desc)
@past_walks   = current_user.owned_walks
                            .where(state: %w[completed cancelled])
                            .includes(:dog, :accepted_by_walker)
                            .order(created_at: :desc)
                            .limit(50)
```

`owned_walks` is declared in `app/models/user.rb:5`:
```ruby
has_many :owned_walks, class_name: "Walk", foreign_key: :owner_id, dependent: :restrict_with_exception
```

Both `@active_walks` and `@past_walks` query `WHERE owner_id = current_user.id`. Scoping
is airtight by construction.

#### Code path — Walker (WalkerWalksController)

`app/controllers/walker_walks_controller.rb`:
```ruby
# lines 9-11 — active section
@walk = Walk.where(accepted_by_walker_id: current_user.id, state: %w[accepted in_progress])
            .includes(:dog)
            .first

# lines 15-18 — past section
@past_walks = Walk.where(accepted_by_walker_id: current_user.id, state: %w[completed cancelled])
                  .includes(:dog, :owner)
                  .order(created_at: :desc)
                  .limit(50)
```

Both scope to `accepted_by_walker_id = current_user.id`. Walker B can only see walks
where Walker B's id was recorded as the accepting walker.

#### Existing test coverage — Owner side

**Active section**: `test/integration/walks_test.rb:33-43`:
```ruby
test "index lists only the current owner's walks" do
  mine  = @dog.walks.create!(owner: @owner, ...)
  other_dog = @other_owner.dogs.create!(name: "Fido", breed: "Beagle")
  theirs = other_dog.walks.create!(owner: @other_owner, ...)

  sign_in_as "owner@example.com"
  get walks_path
  assert_includes     response.body, "Rex"   # own walk IS visible ✓
  assert_not_includes response.body, "Fido"  # other owner's walk is ABSENT ✓
end
```

**Past section**: `test/integration/walks_test.rb:91-102`:
```ruby
test "past walks section does not show another owner's completed walk" do
  # other_owner completes a walk for Fido
  ...
  sign_in_as "owner@example.com"
  get walks_path
  assert_not_includes response.body, "Fido"  # ABSENT ✓
end
```

**Owner isolation: FULLY COVERED.** Both active and past sections assert absence.

#### Existing test coverage — Walker side

**Past section**: `test/integration/walker_walks_test.rb:105-113`:
```ruby
test "walker cannot see another walker's completed walk in history" do
  @walk.start!(@walker)
  @walk.complete!(@walker)

  sign_in_as "walker2@example.com"
  get walker_walks_path
  assert_response :success
  assert_not_includes response.body, "Rex"   # Walker1's completed walk ABSENT from Walker2's view ✓
end
```

**Active section**: ✗ **NOT TESTED.**

No test signs in as Walker2 when Walker1 has an accepted (active) walk and asserts Walker2's
active section does not show it.

The existing test closest to this (`walker_walks_test.rb:28-35`) signs in as **Walker1** who
completed their own walk — it proves a walker with no active walk sees the empty state, but
it never loads Walker2's session while Walker1 has an active walk.

#### The gap

The `@walk` instance variable in the controller uses `.first` — it only exposes the first
matching walk (by `accepted_by_walker_id = current_user.id`). Walker2 would get `nil` for
`@walk` because they never accepted a walk. The scoping is correct, but **no integration
test verifies it by asserting absence from Walker2's perspective while Walker1 has an active
walk**.

Per the risk-map principle: asserting that the current user's walk IS present does not prove
isolation. Only asserting that the other user's walk is ABSENT proves it.

#### What the missing test looks like

One test case in `test/integration/walker_walks_test.rb`, using the existing setup
(`@walk` is already accepted by `@walker`, `@walker2` is already created):

```ruby
test "walker cannot see another walker's accepted walk in active section" do
  # @walk accepted by @walker (from setup) — @walker2 has never accepted a walk
  sign_in_as "walker2@example.com"
  get walker_walks_path
  assert_response :success
  assert_not_includes response.body, "Rex"  # Walker1's active walk must not appear
end
```

No new fixtures, no new setup, no new controller changes. One `assert_not_includes`.

**Verdict: ONE NARROW GAP. Walker active-section isolation test missing.**

---

### Risk #4 — IDOR 404 Contract

**Failure scenario**: Walker B sends start/complete on Walker A's walk and gets something
other than 404 (leaking the walk's existence or allowing mutation).

#### Code path

`app/controllers/walker_walks_controller.rb`:
```ruby
# line 24 — start action
walk = Walk.where(accepted_by_walker_id: current_user.id, state: :accepted).find(params[:id])

# line 34 — complete action
walk = Walk.where(accepted_by_walker_id: current_user.id, state: :in_progress).find(params[:id])
```

Both use a chained `where(...).find(id)`. Rails behavior: `find` with a `where` scope raises
`ActiveRecord::RecordNotFound` when no record matches **both** the where clause and the id.

`app/controllers/application_controller.rb:4-5`:
```ruby
rescue_from ActiveRecord::RecordNotFound, with: :not_found
```
```ruby
# lines 13-15
def not_found
  render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
end
```

When Walker B attempts start/complete on Walker A's walk:
- `WHERE accepted_by_walker_id = walker_b.id AND state = 'accepted' AND id = walk_a.id`
- Walk A's `accepted_by_walker_id = walker_a.id ≠ walker_b.id` → 0 rows → `RecordNotFound`
- ApplicationController rescues → renders 404.html with HTTP status 404
- Walk state is never touched (find raised before any action ran)

#### Why the "model guard makes HTTP test redundant" challenge fails

The HTTP 404 is the **client-visible security contract**. The model's `start!` guard (checking
`accepted_by_walker_id` in the WHERE clause) produces the same outcome, but the HTTP 404
is independently produced by the scoped find — the model method is never called. Verifying
only the model guard would not prove the HTTP response code. The integration tests verify
the right thing.

#### Existing test coverage

`test/integration/walker_walks_test.rb:63-67`:
```ruby
test "walker cannot start another walker's accepted walk: responds 404" do
  sign_in_as "walker2@example.com"
  post start_walker_walk_path(@walk)
  assert_response :not_found   # asserts HTTP 404 specifically ✓
end
```

`test/integration/walker_walks_test.rb:76-81`:
```ruby
test "walker cannot complete another walker's in_progress walk: responds 404" do
  @walk.start!(@walker)
  sign_in_as "walker2@example.com"
  post complete_walker_walk_path(@walk)
  assert_response :not_found   # asserts HTTP 404 specifically ✓
end
```

Both tests:
- Use `ActionDispatch::IntegrationTest` (real HTTP layer)
- Assert `assert_response :not_found` — HTTP 404 specifically
- Do NOT merely check state unchanged (which would be insufficient per the risk guidance)

**Verdict: FULLY COVERED. No new test required.**

Note: Neither test asserts walk state unchanged after the 404 — but this is correct. The 404
means `find` raised `RecordNotFound` before the action could execute `start!`/`complete!`.
Walk state cannot have changed. Adding a state-unchanged assertion would be a vacuous check
(no code path can modify state after RecordNotFound is raised).

---

## Code References

| File | Line(s) | What's there |
|------|---------|-------------|
| `app/controllers/open_requests_controller.rb` | 11 | Unscoped `Walk.find(params[:id])` — intentional for open requests |
| `app/controllers/open_requests_controller.rb` | 17-21 | `accept!` true/false branch; alert text is "just accepted by someone else" |
| `app/controllers/walker_walks_controller.rb` | 24 | Scoped find for start: `where(accepted_by_walker_id: current_user.id, state: :accepted).find(id)` |
| `app/controllers/walker_walks_controller.rb` | 34 | Scoped find for complete: `where(accepted_by_walker_id: current_user.id, state: :in_progress).find(id)` |
| `app/controllers/walker_walks_controller.rb` | 9-11 | Active walk query: scoped by `accepted_by_walker_id = current_user.id` |
| `app/controllers/walker_walks_controller.rb` | 15-18 | Past walks query: scoped by `accepted_by_walker_id = current_user.id` |
| `app/controllers/walks_controller.rb` | 5-9 | Both walk sections use `current_user.owned_walks` (FK: `owner_id`) |
| `app/controllers/application_controller.rb` | 4, 13-15 | `rescue_from RecordNotFound` → renders 404.html with `:not_found` |
| `app/models/walk.rb` | 47-56 | `accept!` — atomic compare-and-swap; returns false when state ≠ requested |
| `app/models/walk.rb` | 77-83 | `swap_state` — `WHERE id AND state AND guard` → `update_all`; false when affected ≠ 1 |
| `app/models/user.rb` | 5 | `owned_walks` association (`FK: owner_id`) |
| `test/integration/open_requests_test.rb` | 55-67 | Singleness HTTP contract test — alert rendered + state unchanged |
| `test/integration/walker_walks_test.rb` | 63-67 | IDOR 404 for start |
| `test/integration/walker_walks_test.rb` | 76-81 | IDOR 404 for complete |
| `test/integration/walker_walks_test.rb` | 105-113 | Walker past-section isolation (asserts absence) |
| `test/integration/walks_test.rb` | 33-43 | Owner active-section isolation (asserts absence) |
| `test/integration/walks_test.rb` | 91-102 | Owner past-section isolation (asserts absence) |
| `test/models/walk_concurrency_test.rb` | 8-10 | DB/model-layer concurrency proof (separate layer from HTTP tests) |

---

## Architecture Insights

**Scoped-find pattern as the primary IDOR defense.** `WalkerWalksController` uses
`Walk.where(accepted_by_walker_id: current_user.id, state: ...).find(id)` for start and
complete. This combines authorization (`accepted_by_walker_id`), state validation (`state`),
and resource lookup into a single query. Failure mode is `RecordNotFound` → 404, not a
conditional branch. The comment at `walks_controller.rb:14-17` explicitly notes this choice
and contrasts it with the intentionally-unscoped `Walk.find` in `OpenRequestsController`.

**WalkerWalksController false-return branch is a race path.** For `start!`, the scoped
find already requires `state: :accepted`. If the find succeeds, `start!`'s `swap_state`
should always update 1 row (the walk is `accepted` and owned by this walker). The `else`
branch (`alert: "This walk can no longer be updated."`) can only fire if the walk transitions
between the find and the `start!` call (a race). This is different from `accept!`, where the
false-return is the normal sequential case (second walker arrives after first). This is a
relevant finding for Phase 2 research.

**ApplicationController's rescue_from as the 404 backstop.** All `RecordNotFound`
exceptions — whether from scoped finds, missing records, or cross-account attempts — funnel
through the same `not_found` handler. This means the 404 behavior is centralized and consistent
across all controllers. Adding a new scoped find to any controller automatically inherits this
behavior.

**Lessons.md note (SimpleCov gate):** The existing `test_helper.rb` already implements the
`Minitest.after_run` workaround documented in lessons.md to prevent SimpleCov's minimum_coverage
from silently no-oping under `bin/rails test`. Phase 3 (coverage gate wiring) is ready to
activate — only the ENV var needs to be set.

---

## Historical Context

- `context/archive/walker-walk-history/` — the slice that added `WalkerWalksController` with
  `@past_walks` query and the walker history tests (including `walker_walks_test.rb:105-113`
  which covers the walker past-section isolation).
- `context/archive/owner-walk-history/` — the slice that added the Owner past-section scoping
  and `walks_test.rb:91-102`.
- `test/models/walk_concurrency_test.rb` — created in an earlier slice to prove DB-level
  Singleness. Explicitly noted in its class comment that the HTTP-layer test belongs to a
  later slice (S-05). The HTTP test now exists at `open_requests_test.rb:55-67`, closing
  that stated gap.

---

## Open Questions

None blocking Phase 1. The scope is fully determined: one new test case.

**Phase 2 note (not blocking Phase 1):** The `WalkerWalksController` start/complete false-return
branch is a race path, not a normal sequential path — unlike `accept!`'s false-return which is
the expected sequential outcome when a second walker arrives late. Research for Phase 2 should
determine whether the current behavior (state mismatch → 404, not flash) is the intended UX,
and whether the plan's "state machine feedback" tests should cover the 404 path or a sequential
illegal-transition path (e.g., an owner tries to start a walk directly). The controller for
`start`/`complete` has no sequential illegal-transition path reachable by a legitimate user
(the scoped find would 404 first).

---

## Plan Guidance for `/10x-plan`

Phase 1 is almost entirely already done. The plan should:

1. **Document closed risks** — explicitly record that Risks #1 and #4 are closed by existing
   tests. No duplication.

2. **Add the one missing test** — one test case in `test/integration/walker_walks_test.rb`:
   - Sign in as `walker2`
   - GET `walker_walks_path` (while `@walk` is accepted by `@walker`)
   - `assert_not_includes response.body, "Rex"`
   - Uses existing `setup` — no new fixtures or infrastructure needed.

3. **Update §6.1 cookbook** — document the integration test pattern:
   - `ActionDispatch::IntegrationTest` subclass
   - Inline user/fixture creation (no YAML fixtures — `has_secure_password` needs real passwords)
   - Sign in via `post session_path, params: { email_address: ..., password: ... }`
   - Follow redirects manually via `follow_redirect!` when verifying flash/body content
   - `assert_not_includes` for absence tests; `assert_response :not_found` for 404s
   - Pattern for cross-account isolation: create two users A and B, sign in as B, assert A's
     resource does NOT appear.

4. **Mark §3 Phase 1 complete** after the test is added and passing.

The implementation sub-phase is trivial (one test), but the cookbook update and gap-closure
documentation are the durable deliverables.
