# Frame Brief: Displaying distance between Walker and Owner on the UI

> Framing step before /10x-plan. This document captures what is *actually*
> at issue, separated from what was initially assumed.

## Reported Observation

User wants the numeric distance between Walker and Owner visible on the UI —
on both the open-requests list (Walker) and the active-walk screen (both
roles) — updating live, without a page refresh.

## Initial Framing (preserved)

- **User's stated cause or approach**: This is a small, low-risk addition on
  top of L-01 (`geolocation-matching`) — coordinates for both sides are
  already captured, and a Haversine distance calculation already exists
  server-side (`Walk#distance_km_to`, `app/models/walk.rb:150-157`) for
  broadcast-eligibility. Rendering that existing number to the user felt
  categorically different from "a map" or "ranking."
- **User's proposed direction**: Add it as a new roadmap item, same shape as
  L-01.
- **Pre-dispatch narrowing**: User confirmed (1) it belongs on **both**
  screens — open-requests list and active-walk screen — as one unified
  feature, not scoped to one persona/screen; (2) it must be **live** —
  auto-updating without a refresh, not computed once at page load.

## Dimension Map

1. **Non-goal identity** — does this hit the already-partially-reversed
   "map / proximity ranking" non-goal (Open Q#6, reversed in part by L-01),
   or the separately-declared, still-fully-intact "live GPS" non-goal
   (§Non-Goals "Real-time UI layer")? ← user's initial framing assumed the
   former
2. **Technical build scope** — does a "live" distance number require the
   same infrastructure as continuous GPS tracking (one-shot geolocation vs.
   `watchPosition`, per-walk position storage, a new broadcast channel), or
   can it be delivered as a page-load-time calculation?
3. **Precedent transfer** — do R-01's and L-01's reversal justifications
   ("infra already in the stack," "purely additive," "more runway") transfer
   to continuous location tracking?
4. **Product-hypothesis fit** — does a live distance reading serve the
   "binding IS the confirmation, no out-of-app coordination" thesis the PRD
   bets on, or is it orthogonal to what the north star (S-05) already proved?

## Hypothesis Investigation

| Hypothesis | Evidence | Verdict |
| --- | --- | --- |
| **Dim 1**: This is the same gray-zone non-goal L-01 already partly reversed | `prd.md:193` bundles "no radius, no map, no proximity ranking" in one Open-Q#6-linked bullet — L-01 reversed only the radius-filter half (`roadmap.md:446`, `:504`: "map, proximity ranking... stays parked"). But `prd.md:192` is a **separate, distinct** bullet: "Real-time UI layer (live GPS, live map, live walk-status push, in-app chat, push notifications) — v1 has no real-time push of any kind." R-01 (`roadmap.md:432`) reversed only the "live walk-status push" clause of *this* bullet; "live GPS" was never touched by either reversal. CLAUDE.md (project instructions, independently maintained, current) still lists "continuous GPS tracking during a walk" as explicitly out of scope. The user's confirmed requirement — live, auto-updating — lands on this second, untouched bullet, not the one L-01 already partly opened. | STRONG (this is a different, unreversed non-goal, not L-01's gray zone) |
| **Dim 2**: "Live" distance ≈ "continuous GPS tracking" infra, not a small addition | Current location capture is one-shot only: `navigator.geolocation.getCurrentPosition` (not `watchPosition`), `app/javascript/controllers/walker_location_controller.js:12`. `WalkerLocationCache` (`app/models/walker_location_cache.rb`) is a 10-minute-TTL, single-process `Rails.cache` read on page load — no per-walk association, no timestamp, explicitly flagged in its own code comment as single-worker-only. No Solid Queue recurring job exists (`app/jobs/` has only the stock `application_job.rb`; no `config/recurring.yml`). Delivering "live" requires: repeating capture (`watchPosition` or polling), a durable per-walk storage path, and a new broadcast channel (e.g. `[walk, :location]`) — the exact same server/client mechanism a live-map view would need, just rendered as text instead of a marker. | STRONG |
| **Dim 3**: R-01/L-01 precedent transfers to continuous GPS tracking | L-01's own frame brief (`context/archive/2026-09-02-geolocation-matching/frame.md:56`) already found that R-01's "more runway" justification does **not** transfer to geolocation-adjacent work requiring new infrastructure, because R-01's safety conditions were "no new infra dependency" + "purely additive, touches no other non-goal" — geolocation failed the first condition even for a one-shot radius filter. Continuous GPS tracking fails that same condition more severely (new capture mechanism, new storage, new channel) and additionally has no `Owner:`/`By:` governance tag anywhere in the PRD's Open Questions the way Open Q#6 (geolocation) did — meaning it isn't even flagged as "reconsider post-v1," unlike geolocation was before L-01 touched it. | STRONG (precedent does not transfer, and transfers even less than it did for L-01) |
| **Dim 4**: Live distance serves the core product hypothesis | `prd.md:149-153` (Business Logic): "the rule's output IS the confirmation... no out-of-app message exchange is required." `prd.md:192`'s own stated reasoning for the real-time-UI non-goal: "the 'no out-of-app coordination' insight is meant to be proved with status transitions seen on refresh, not live telemetry." No PRD user story, success criterion, or guardrail mentions distance/proximity awareness as something either party needs to complete a walk — the north star (S-05) already validated the hypothesis without it. | STRONG (no articulated value case in the PRD's own success criteria) |

## Narrowing Signals

- User confirmed (pre-dispatch): the feature covers **both** screens, framed
  as one feature — ruling out a scoped-down, single-screen reading.
- User confirmed: it must be **live**, not computed once at page load — this
  is the single most decisive signal. Had the answer been "static, per page
  load," this frame would land very differently (see below).

## Cross-System Convention

Every prior non-goal reversal in this project (R-01, L-01) was scoped to
exactly the clause it touched, justified with existing infra + purely-additive
reasoning, and explicitly recorded as a conscious user decision in the
roadmap. "Live GPS" is the one clause inside the bundled real-time-UI non-goal
(`prd.md:192`) that neither reversal touched — R-01 stayed inside
"walk-status push" only. CLAUDE.md, the actively maintained project-instruction
file (not a frozen v1 PRD snapshot), independently restates "continuous GPS
tracking during a walk" as current, deliberate scope — this isn't a stale
non-goal nobody revisited, it's one the project has kept re-affirming.

## Reframed (or Confirmed) Problem Statement

> **The actual problem to plan around is not "add a small distance number
> next to L-01's radius filter."** Because the user needs it live, the real
> decision is whether to reverse "continuous GPS tracking during a walk" —
> a non-goal distinct from, and never touched by, either prior reversal
> (R-01, L-01) — which requires materially new infrastructure (continuous
> capture, per-walk storage, a new broadcast channel), not a UI-only
> addition.

This is functionally the same build this session already scoped for the
earlier "live map showing the walker with the dog" idea — the map itself
turns out to be the cheap part (a Leaflet import); the expensive, non-goal-
crossing part is the continuous-tracking pipeline underneath, and that part
is identical whether the surface is a map or a number. A **static** distance
(computed once per page load from data already captured for L-01, same
precedent class as L-01/R-01) would sidestep the "live GPS" non-goal entirely
and could reasonably ride on L-01's already-accepted precedent — but that is
a different, smaller feature than what was confirmed above.

## Confidence

**HIGH** — PRD text, CLAUDE.md's independently maintained scope statement,
L-01's own prior precedent-transfer analysis, and the user's decisive
pre-dispatch answer (live + both screens) all converge on the same
conclusion.

## What Changes for `/10x-plan`

If the user still wants **live** distance, `/10x-plan` should treat this as
two separable decisions, not one: (a) a conscious, documented reversal of
"continuous GPS tracking during a walk" (mirroring how R-01/L-01 recorded
their non-goal reversals explicitly), sized as new infra (repeating capture +
per-walk storage + broadcast channel) — not a UI decoration; and (b) only
once (a) is decided, whatever UI renders the number (or a map) is genuinely
the cheap part. If a **static**, page-load-computed distance would actually
satisfy the need, that is a materially smaller feature riding on L-01's
existing precedent, with no new non-goal reversal required — worth offering
back to the user as an explicit alternative before committing to "live."

## Decision (post-frame)

User chose the static path: a distance number computed once per page load
from data already captured for L-01, not a live/auto-updating reading. This
avoids reversing "continuous GPS tracking during a walk" entirely — the
feature rides on L-01's existing precedent rather than opening a new,
previously-untouched non-goal. Ready for `/10x-plan` on that reduced scope.

## References

- Source files:
  - `app/models/walk.rb:150-157` (`distance_km_to`, existing internal calc)
  - `app/models/walker_location_cache.rb` (one-shot, 10-min TTL, single-process cache)
  - `app/javascript/controllers/walker_location_controller.js:12` (one-shot `getCurrentPosition`)
  - `app/jobs/` (no custom jobs), no `config/recurring.yml`
- `context/foundation/prd.md:192` (§Non-Goals "Real-time UI layer," incl. "live GPS"), `:193` (§Non-Goals "Advanced geolocation matching"), `:149-153` (Business Logic — binding is the confirmation), `:199` (non-functional "No real-time UI updates," reversed by R-01), `:204-216` (Open Questions incl. #6)
- `context/foundation/roadmap.md:432` (R-01 outcome — reversed only "live walk-status push"), `:446`, `:453-454`, `:504` (L-01 outcome/risk/parked note — map/ranking stays parked)
- `context/archive/2026-09-02-geolocation-matching/frame.md:56` (L-01's own precedent-transfer finding — reused here as Step 5 cross-check)
- `CLAUDE.md` — "Out of scope for the MVP: continuous GPS tracking during a walk, WebSockets (beyond Turbo/Action Cable), payments, chat, ratings."
- Related research: none prior (new `context/changes/walker-owner-distance-display/`)
