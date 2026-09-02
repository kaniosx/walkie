# Frame Brief: Locality matching — city/postcode exact match vs. geolocation radius

> Framing step before /10x-plan. This document captures what is *actually*
> at issue, separated from what was initially assumed.

## Reported Observation

`Walk.open_in_locality` (`app/models/walk.rb:20-23`) filters open (REQUESTED)
walk requests to Walkers via an **exact match on both `city` and `postcode`**.
A Walker in the same city but a different postcode sees zero open requests
from that city. PRD FR-011's Socratic note and Open Question #6
(`context/foundation/prd.md:120-121`, `:214`) already name this as a known,
accepted v1 limitation — "a Walker on the wrong side of a big city sees walks
they can't realistically reach."

## Initial Framing (preserved)

- **User's stated cause or approach**: The matching mechanism itself is too
  coarse/imprecise (exact string match on city+postcode); the fix is
  geolocation-based radius matching (real coordinates, distance calculation).
- **User's proposed direction**: Replace/extend `open_in_locality` with
  geolocation-radius matching before `/10x-plan`, citing R-01
  (`realtime-walk-status-updates`) — a recent reversal of a different PRD
  non-goal justified by "the MVP has more runway than the original 3-week
  budget assumed" — as precedent for reconsidering this non-goal too.
- **Pre-dispatch narrowing**: User's own answers to the pre-dispatch
  questions: (1) this is "anticipated from the PRD text," not an observed
  incident with real or test users; (2) "no real users yet" — so there's no
  data on Walker-supply density per city/postcode to evaluate against; (3) the
  concern is scoped to the FR-011 filter only, not the FR-005 city/postcode
  input field's data quality.

## Dimension Map

The observation could originate at any of these dimensions:

1. **Precision-of-matching** (user's initial framing) — is exact
   city+postcode itself the binding constraint on marketplace friction right
   now?
2. **Evidence/timing** — is this anticipatory reasoning ahead of any real-user
   data, at a stage where real launch is already blocked on something else
   entirely?
3. **Precedent validity** — does the R-01 "MVP has more runway" justification
   actually transfer to geolocation, or did R-01's reversal rest on
   preconditions that don't hold here?
4. **Non-goal entanglement** — does geolocation-based matching (specifically a
   natural distance-sort pairing) cross into the separately declared "no
   ranking/scoring" non-goal?

## Hypothesis Investigation

| Hypothesis | Evidence | Verdict |
| --- | --- | --- |
| **Dim 1**: Precision-of-matching is the live problem to solve now | FR-011 Socratic note (`prd.md:120-121`) and Open Q#6 (`prd.md:214`) frame the gap as an *accepted v1 limitation*, explicitly deferred ("Owner: future-scope decision. By: post-v1 planning"). No document or user statement shows it has actually blocked anyone; user confirmed this is anticipated from PRD text, not observed friction. | WEAK |
| **Dim 2**: Premature relative to other real-launch blockers | `roadmap.md:461` (Open Roadmap Q#2) / `prd.md:208` (PRD Open Q#3): Walker trust/verification is explicitly tagged as blocking "any real launch beyond the two-test-user smoke." `prd.md:9` — `target_scale.users: small`. No text describes geolocation matching as producing user-facing value before that gate clears — there is no "real launch" audience yet for it to serve. Owner-persona breadth (Open Q#1, `roadmap.md:460`) is explicitly *not* a launch blocker (only v2-scoping), leaving Walker trust as the one binding gate, unrelated to locality granularity. | STRONG |
| **Dim 3**: R-01 precedent transfers cleanly to geolocation | R-01's justification pairs "more runway" with two conditions specific to real-time UI's own risk profile: no new infra dependency (Turbo Streams/Solid Cable "already in the stack," `context/archive/2026-08-21-realtime-walk-status-updates/change.md:18-20`) and purely-additive/touches-no-other-non-goal (repeated 4× across roadmap/change/plan docs). Geolocation has **no existing coordinates/geocoding infra** anywhere in `Gemfile` or `db/schema.rb` — the opposite of R-01's condition. Open Q#6 also carries an explicit PRD-native governance tag ("Owner: future-scope decision. By: post-v1 planning") that the non-functional "no real-time UI" non-goal never had (that section carries no Owner/By fields at all) — R-01 didn't override a PRD-assigned decision gate; geolocation still has one, unaddressed. | STRONG (precedent does NOT transfer) |
| **Dim 4**: Distance-based matching stays clean of the ranking non-goal | `prd.md:193`: "no radius, no map, **no proximity ranking**" — the ranking clause is embedded in the *same bullet* as the radius non-goal (repeated verbatim in `roadmap.md:473`). Filter-by-radius alone is textually clean — no document links pure filtering to ranking/determinism, and the PRD's four load-bearing Business Logic properties (`prd.md:155-160`) don't mention sort order. But sort/display by distance — the natural UX pairing with "nearby" results — directly matches "no proximity ranking." Current FIFO order (`walk.rb:109`) is documented as a UX "minor choice," not load-bearing for Singleness, but that doesn't resolve the separate textual non-goals question. | STRONG (for the sorting sub-piece; filtering alone is clean) |

## Narrowing Signals

- User confirmed (pre-dispatch): "anticipated from the PRD text" — not an
  observed incident with real or test users.
- User confirmed: "no real users yet" — there is no supply-density data to
  argue the postcode split is the binding constraint over sheer Walker
  scarcity.
- User confirmed: scope is FR-011 filter only — narrows the investigation away
  from input-data-quality concerns, which sharpened the dimension map onto
  timing/precedent/non-goal questions rather than data-quality ones.

## Cross-System Convention

Every PRD Open Question carries explicit `Owner:` / `By:` governance fields
(`prd.md:204-216`) — the project's convention for "deferred, needs a decision
later." R-01 reversed a *non-functional* non-goal, a category that carries no
such fields at all, and its own documentation independently supplied two
narrow justifications (no new dependency, purely additive) before treating the
reversal as safe (`context/archive/2026-08-21-realtime-walk-status-updates/change.md:12-20`).
Geolocation matching (Open Q#6) has an explicit, still-unaddressed Owner/By
gate, and fails both of R-01's independent safety conditions (new dependency
required; touches a second non-goal via sorting). The convention this project
follows — respect the Owner/By gate, verify the specific risk profile before
generalizing a precedent — argues against treating "more runway" alone as
sufficient license to reopen Open Q#6 the way it was sufficient for R-01.

## Reframed (or Confirmed) Problem Statement

> **The actual problem to plan around is not "build geolocation matching
> now."** Walkie has no real users yet, and the project's own documents
> identify Walker trust/verification (PRD Open Q#3 / Roadmap Open Q#2) — not
> locality-matching precision — as the one item explicitly blocking real
> launch. Locality precision is a real, PRD-acknowledged v1 limitation, but
> every document that mentions it defers it to "post-v1 planning," and the
> R-01 precedent invoked to justify picking it up now doesn't transfer:
> geolocation needs new infrastructure R-01 didn't require, and a natural
> extension of it (distance sorting) would cross a second, separately-declared
> non-goal ("no proximity ranking") that R-01 never touched.

This isn't a rejection of geolocation matching as a future idea — the PRD
itself treats it as a legitimate post-v1 direction (Open Q#6). The reframe is
about **timing and precedent**: nothing in this project's own documents
supports building it *now*, ahead of the thing that's actually gating real
launch, and the specific argument offered (the R-01 analogy) doesn't hold up
under its own stated conditions.

## Confidence

**HIGH** — three independent read-only investigations converged with
file:line/document:section citations; the reframe matches the PRD's own
explicit governance tags (Owner/By fields on Open Questions); and it is
consistent with the user's own pre-dispatch answers (anticipatory reasoning,
no real users, FR-011-only scope).

## What Changes for `/10x-plan`

If the user still wants to proceed with geolocation matching despite this, the
plan should treat it as **two entangled decisions**, not one: (a) the
radius-filter mechanism itself, and (b) whether to add distance-based sort —
which would require consciously and explicitly relaxing the "no proximity
ranking" non-goal (mirroring how R-01's `change.md` recorded "scope decided
with the user before planning"), not extending the geolocation non-goal in
passing. Absent that explicit decision, the higher-leverage next move
consistent with the project's own stated priorities is Walker
trust/verification (Open Q#2/#3), since that's the one item literally gating
real launch.

## References

- Source files:
  - `app/models/walk.rb:20-23` (`open_in_locality` scope), `:108-116`
    (broadcast query + FIFO order)
  - `context/foundation/prd.md:120-121` (FR-011 Socratic note), `:193-194`
    (Non-Goals: geolocation + AI/ML/ranking), `:155-160` (Business Logic
    load-bearing properties), `:204-216` (Open Questions incl. #1, #3, #6)
  - `context/foundation/roadmap.md:417-424` (R-01 outcome/reason/risk),
    `:460-462` (Open Roadmap Questions #1-#3), `:473`, `:486` (Parked —
    geolocation matching)
  - `context/archive/2026-08-21-realtime-walk-status-updates/change.md:12-20`
  - `context/archive/2026-06-17-walker-accepts-request/plan-brief.md:118`
    (FIFO order documented as "minor choice")
  - `app/models/walk.rb:80-88` (`swap_state` — Singleness enforced
    independent of query order)
- Related research: none prior (`context/changes/geolocation-matching/` new)
- Investigation agents: R-01 precedent check (agent `aa098f36f771aae69`),
  ranking non-goal entanglement (agent `ae76e1dc4474d9616`), real-launch
  blocker/timing (agent `a6766b7c2431df6f0`)
