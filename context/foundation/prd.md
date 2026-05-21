---
project: "Walkie"
version: 1
status: draft
created: 2026-05-20
context_type: greenfield
product_type: web-app
target_scale:
  users: small
  qps: low
  data_volume: small
timeline_budget:
  mvp_weeks: 3
  hard_deadline: null
  after_hours_only: true
---

# Walkie — Product Requirements Document

## Vision & Problem Statement

Dog owners need their dog walked at moments they didn't plan for — work runs long, an errand pops up, the owner is unwell, the weather window closes — and the channels available today (messaging friends, phoning neighbours, posting in Facebook groups, scheduling on Rover-like platforms) are all built for advance booking, not the unplanned "now". The cost of failure is concrete: the dog doesn't get walked.

The insight Walkie bets on is that the gap isn't supply — casual walkers (students, flexible workers) are already willing to do an ad-hoc walk for cash — it's the "available right now" signal. A walker who's free this hour can't easily express that to nearby owners, and an owner who needs a walk in the next hour can't easily find them. Existing platforms force both sides through profile setup, scheduling, and conversation before anything can happen. Walkie removes that gate so a walk can be requested, accepted, and completed without out-of-band coordination.

## User & Persona

**Primary persona — Owner.** Anyone with a dog. The owner reaches for Walkie at the moment they realise their dog needs a walk and they cannot do it themselves — the unplanned "now" described in the vision. The owner-side persona is deliberately broad in v1 (see `## Open Questions`); narrowing is deferred until v1 ships and produces evidence about who actually shows up.

**Primary persona — Walker.** Casual / gig walker — typically a student or someone with a flexible schedule who treats this as side income. The walker is not running a pet-care business; they want to flip a switch, see what's available nearby, accept a single walk, and move on. No recurring obligations, no client management.

## Success Criteria

### Primary
- The full request → accept → complete cycle (REQUESTED → ACCEPTED → IN_PROGRESS → COMPLETED) works end-to-end with two real test users (one Owner, one Walker) in a single city, without any out-of-app coordination.

### Secondary
- An Owner can create a walk request in under 30 seconds, measured from opening the app to the request appearing in the active list.

### Guardrails
- **Role separation never leaks.** Owners only see their own walks in Owner views; Walkers only see the public list of open requests plus their own accepted walks. No accidental cross-role exposure of data.
- **Single-Walker acceptance + linear state machine.** A walk in REQUESTED state is accepted by at most one Walker (no double-acceptance race). Walks only ever move REQUESTED → ACCEPTED → IN_PROGRESS → COMPLETED. Both invariants are binding outside the UI, not advisory hints.
- **Test coverage.** ≥ 80% test coverage on the four core flows (create request, accept request, start walk, complete walk), with unit or integration tests covering the most important business cases. (Carried over verbatim from the user's idea-notes.)

## User Stories

### US-01: Owner creates a walk request

- **Given** a signed-in Owner with at least one dog on their account and a set city / postcode
- **When** they open Walkie and tap "Walk my dog" for one of their dogs
- **Then** a new walk request is created in REQUESTED state, visible in their own walk history and visible to Walkers in the same city / postcode on the active-requests list

#### Acceptance Criteria
- The end-to-end interaction from opening the app to the request being live takes under 30 seconds for a logged-in Owner with one dog (Secondary success criterion).
- The request is invisible to Owners other than the creator.
- The request is invisible to Walkers in a different city / postcode.
- An Owner with no dogs cannot create a request; the action is gated until a dog is added.

### US-02: Walker accepts an open walk request

- **Given** a signed-in Walker viewing the active-requests list filtered to their city / postcode
- **When** they tap "Accept" on a request that is in REQUESTED state and was not created by them
- **Then** the request transitions to ACCEPTED, is bound to this specific Walker, and disappears from every other Walker's active-requests list

#### Acceptance Criteria
- If two Walkers tap "Accept" on the same request near-simultaneously, exactly one succeeds; the other receives an "already accepted" outcome and the request does not enter an inconsistent state.
- A Walker cannot accept a request they themselves created (defensive — Walkers cannot create requests in v1, but the rule applies regardless).
- A Walker cannot accept a request that is not in REQUESTED state.
- The Owner who created the request sees the status update to ACCEPTED on their own history view.

### US-03: Walker completes a walk

- **Given** a signed-in Walker who previously accepted a walk and started it (status IN_PROGRESS)
- **When** they tap "End walk"
- **Then** the walk transitions to COMPLETED and remains visible in both parties' walk history as a finished walk

#### Acceptance Criteria
- Only the Walker who accepted the walk can move its state forward; no other Walker and no Owner can change the state.
- State transitions are linear (REQUESTED → ACCEPTED → IN_PROGRESS → COMPLETED). Any attempt to skip, reverse, or re-enter a prior state is rejected beyond the UI layer.
- Once COMPLETED, the walk no longer appears as an active item on either side's UI but remains in the immutable history of both.

## Functional Requirements

### Authentication & profile

- FR-001: A visitor can sign up as an Owner with email + password. Priority: must-have
  > Socrates: Counter-argument considered: "Owners should be invitable via a one-time link from a Walker, not self-sign-up." Resolution: kept; the two-sided model requires symmetric onboarding, and hard role separation at sign-up is locked.

- FR-002: A visitor can sign up as a Walker with email + password. Priority: must-have
  > Socrates: Counter-argument considered: "Walkers should be pre-vetted / invited, not open self-sign-up — strangers walking your dog is a real trust/safety concern." Resolution: kept; v1 explicitly excludes verification, and the trust gap is a known limitation surfaced in `## Open Questions`.

- FR-003: A registered user can sign in with email + password. Priority: must-have
  > Socrates: Counter-argument considered: "Passwordless (magic link) would lower friction." Resolution: kept; passwordless adds an email-sending dependency to v1 and was rejected on that basis.

- FR-004: A signed-in user can sign out. Priority: must-have
  > Socrates: Counter-argument considered: "Sign-out is trivial and doesn't need an FR." Resolution: kept; making it explicit prevents a missing sign-out from being silently shipped.

- FR-005: A signed-in user can view and edit their own profile (display name, city / postcode). Priority: must-have
  > Socrates: Counter-argument considered: "City / postcode should come from device geolocation, not a profile field." Resolution: kept; manual city / postcode is a v1 simplification, with geolocation matching deferred to a later release.

### Dog management (Owner)

- FR-006: An Owner can add a dog (name + basic details) to their account. Priority: must-have
  > Socrates: Counter-argument considered: "A dog doesn't need to be a stored entity — a request could just say 'walk needed' with no dog reference." Resolution: kept; the dog is the entity the marketplace coordinates around, and without it Walkie reduces to a generic gig list.

- FR-007: An Owner can edit their own dog's details. Priority: must-have
  > Socrates: Counter-argument considered: "Edit is overkill for v1 — Owners can delete and re-add if details change." Resolution: kept; basic dog management (including edit) is explicitly in scope.

- FR-008: An Owner can remove their own dog. Priority: must-have
  > Socrates: Counter-argument considered: "Removing a dog with past walks should keep the history intact, not erase it — losing history is a foot-gun." Resolution: kept; the user-observable behaviour of remove-on-a-dog-with-history is surfaced as an `## Open Questions` entry for a future decision.

### Walk request lifecycle

- FR-009: An Owner can create a walk request for one of their own dogs, putting it in REQUESTED state. Priority: must-have
  > Socrates: Counter-argument considered: "Requests should support scheduled time, not just 'now'." Resolution: kept as now-only; supporting scheduled time would weaken the "available right now" insight the product is betting on, and scheduling is out of v1 scope.

- FR-010: An Owner can cancel a walk request they created while it is still in REQUESTED state. Priority: must-have
  > Socrates: Counter-argument considered: "Owner should also be able to cancel after a Walker accepted — life changes, plans shift." Resolution: kept for v1 as REQUESTED-only; post-accept cancellation is surfaced in `## Open Questions` as a future-scope decision.

- FR-011: A Walker can see the list of open (REQUESTED) walk requests filtered to their own city / postcode. Priority: must-have
  > Socrates: Counter-argument considered: "City / postcode is too coarse — a Walker on the wrong side of a big city sees walks they can't realistically reach." Resolution: kept as written for v1; geolocation matching is deferred to a later release, with the ergonomic gap surfaced in `## Open Questions`.

- FR-012: A Walker can accept an open walk request that is not theirs, transitioning it REQUESTED → ACCEPTED. Exactly one Walker may successfully accept a given request. Priority: must-have
  > Socrates: Counter-argument considered: "The concurrency invariant is hard to test reliably; v1 could accept best-effort first-write-wins." Resolution: kept; the single-Walker-acceptance invariant is a Guardrail and is non-negotiable.

- FR-013: The Walker who accepted a walk can transition it ACCEPTED → IN_PROGRESS ("Start walk"). Priority: must-have
  > Socrates: Counter-argument considered: "ACCEPTED and IN_PROGRESS could be collapsed into one state." Resolution: kept; the four explicit states are load-bearing, and the distinction encodes "Walker physically has the dog", which is a real operational signal.

- FR-014: The Walker who accepted a walk can transition it IN_PROGRESS → COMPLETED ("End walk"). Priority: must-have
  > Socrates: Counter-argument considered: "Completion should require Owner confirmation, not just Walker self-report — otherwise a Walker could mark COMPLETED without doing the walk." Resolution: kept for v1; the user accepted the counter as the strongest concern, and Owner-confirmation flow is surfaced in `## Open Questions` for a future release (linked to broader trust / verification work).

### History

- FR-015: An Owner can see their own past and current walks. Priority: must-have
  > Socrates: Counter-argument considered: "History view is bloat — current / active walks would be enough for v1." Resolution: kept; walk history is explicitly in scope.

- FR-016: A Walker can see their own past and current walks. Priority: must-have
  > Socrates: Counter-argument considered: "Walker history is bloat — Walkers don't need to revisit completed walks in v1." Resolution: kept; symmetric with FR-015.

## Non-Functional Requirements

- A user-initiated action in the walk lifecycle (open the active-requests list, accept a request, start a walk, end a walk) produces a visible result within 2 seconds at the product's outer boundary.
- Any view rendered to a signed-in Owner contains no walk that the Owner did not create. Any view rendered to a signed-in Walker contains no other Walker's bound work.
- There is no externally observable path that lets a walk skip, repeat, or reverse states; the only observable sequence of transitions is REQUESTED → ACCEPTED → IN_PROGRESS → COMPLETED (or REQUESTED → cancelled-by-Owner, per FR-010).
- No personal data of any user (profile fields, dog details, walk history) is observable to any other signed-in user except where a specific FR makes it visible (e.g. a Walker viewing an open request necessarily sees the Owner's dog and city).

## Business Logic

Walkie binds a one-off walk request to exactly one nearby available Walker, in real time, without out-of-app coordination.

The rule consumes three user-facing inputs: an Owner's open request (created right now, for a specific dog), the Owner's location (city / postcode), and a Walker's expressed availability (a Walker is "available" if they are signed in, in the same city / postcode, and choose to act on the request). The output the rule produces is a single binding: one walk request becomes the responsibility of exactly one Walker, observed by both parties as a state transition from REQUESTED to ACCEPTED.

The user encounters the rule at the moment of acceptance. An Owner who taps "Walk my dog" is committing to whichever Walker first claims their request; a Walker who taps "Accept" on a visible request is committing to that walk and to nobody else's. After acceptance, no other Walker can take the same walk and no out-of-app message exchange is required to confirm the binding — the rule's output IS the confirmation. The walk then proceeds through IN_PROGRESS to COMPLETED under the same single-Walker binding.

Four properties are load-bearing for the rule and must hold in every implementation:

- **Singleness** — at most one Walker is ever bound to a given request.
- **Locality** — only Walkers in the same city / postcode as the request see it as actionable.
- **Immediacy** — the request is for "now"; scheduling, future-dated requests, and recurring arrangements are out of scope.
- **Self-sufficiency** — the binding is the coordination signal. No SMS, phone call, or chat is needed for the walk to proceed.

## Access Control

Walkie is multi-user. Every interaction with the marketplace happens behind authentication; there are no anonymous flows.

**Sign-in.** Email + password. No third-party identity providers and no passwordless / magic-link in v1.

**Account types.** Two distinct types chosen at sign-up — `Owner` and `Walker`. A user is one or the other; a person who wants to do both creates two accounts. Dual-role accounts and role switching are explicitly out of v1 scope.

**Role → capability matrix** (v1):

| Capability                                       | Owner | Walker |
|--------------------------------------------------|:-----:|:------:|
| Manage own profile                               |   ✓   |   ✓    |
| Add / edit / remove own dog                      |   ✓   |        |
| Create a walk request for an own dog             |   ✓   |        |
| Cancel a walk request they created               |   ✓   |        |
| See the public list of open walk requests        |       |   ✓    |
| Accept an open walk request (not their own)      |       |   ✓    |
| Progress / complete an accepted walk             |       |   ✓    |
| See own walk history                             |   ✓   |   ✓    |

**Unauthenticated access.** Limited to sign-up, sign-in, and password reset. Any other route redirects to sign-in.

## Non-Goals

### Functional non-goals

- **Native mobile apps** — v1 is a web app only. Reason: keeps the build to a single surface; mobile-browser support is enough for the happy path.
- **Payments / money flow** — no money moves through Walkie v1. Reason: payments multiply trust, compliance, and dispute machinery the MVP can't carry.
- **Identity verification, ratings / reviews, insurance, trust & safety machinery** — v1 has none of these. Reason: a real trust system is a project of its own. The resulting gap is accepted as a v1 limitation (see `## Open Questions`).
- **Real-time UI layer (live GPS, live map, live walk-status push, in-app chat, push notifications)** — v1 has no real-time push of any kind. Reason: the "no out-of-app coordination" insight is meant to be proved with status transitions seen on refresh, not live telemetry.
- **Advanced geolocation matching** — v1 filters strictly by city / postcode; no radius, no map, no proximity ranking. Reason: explicitly deferred (see `## Open Questions`).
- **AI / ML algorithms anywhere in the product** — no models, no ranking, no scoring in v1. Reason: the domain rule is deterministic — first-Walker-claims-it — and intentionally so.
- **Advanced Walker-availability scheduling** — no calendars, no recurring slots, no expressed availability windows. Reason: a Walker is "available" iff they sign in and act on a visible request; this is load-bearing for the "available right now" insight.

### Non-functional non-goals

- **No real-time UI updates.** Owners and Walkers see status changes by refreshing the relevant view or navigating to it, not via push.
- **No offline support.** Walkie is online-only in v1.

## Open Questions

1. **Owner persona is not narrowed.** v1 is deliberately open to "anyone with a dog". Risk: design tradeoffs (busy urban professional vs. elderly / mobility-limited owner) will repeatedly surface and have to be re-decided per feature; without a sharp first user the product risks a generic "Uber for dogs" framing. Resolve by: picking a primary owner persona before lock, or accepting the breadth as a deliberate product bet. Owner: user. By: before v2 scope is set.

2. **Walker-side insight beyond the "available right now" signal.** Candidates parked for later: local-first matching (walks within walking distance of where the Walker already is) and no-advance-commitment (one-off walks only, no recurring clients). Owner: user. By: post-v1.

3. **Walker trust / verification is out of v1 scope.** FR-002 lets any visitor self-sign-up as a Walker. This is a deliberate v1 limitation and a real product risk. Owner: user / downstream design. By: before any real (non-test) Owner uses Walkie.

4. **What happens to walk history when an Owner removes a dog (FR-008)?** Should removing a dog that has past walks erase the history, keep the history visible but hide the dog, or keep both visible? Surfaced during the Socratic challenge on FR-008. Owner: downstream implementation planning. By: before FR-008 is implemented.

5. **Post-accept cancellation (FR-010).** v1 lets Owners cancel only while REQUESTED. A real Owner need — life changes after a Walker has accepted — is unmet. Owner: future-scope decision. By: post-v1 planning.

6. **Coarse city / postcode filtering (FR-011).** A city-wide filter doesn't reflect actual Walker reachability. Geolocation matching is deferred to a later release; the ergonomic gap is accepted in v1. Owner: future-scope decision. By: post-v1 planning.

7. **Owner confirmation of walk completion (FR-014).** v1 trusts Walker self-report on completion; there is no mechanism preventing a Walker from marking COMPLETED without doing the walk. Owner: future-scope decision, linked to broader trust / verification work. By: post-v1 planning.
