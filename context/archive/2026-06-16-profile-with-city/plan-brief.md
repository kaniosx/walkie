# S-02: User Profile with City/Postcode — Plan Brief

> Full plan: `context/changes/profile-with-city/plan.md`

## What & Why

Give every Walkie user a profile holding a display name (optional) and a city + postcode (required). FR-005 calls for view/edit of these fields; the locality is load-bearing for the marketplace — S-04 copies the owner's city/postcode onto each walk request, and S-05 filters open requests by city. Capturing it now, required, means later slices never have to handle a user with no locality.

## Starting Point

After S-01 (merged to `main`), users have only `email_address`, `password_digest`, `role`. F-02 already models locality on `walks` as `city` (NOT NULL) + `postcode`. There is no profile screen, and nothing on the user carries a location.

## Desired End State

A signed-in user sees a "Profile" link in the nav, opens a read-only profile (display name, city, postcode, email, role), and can edit the display name + city + postcode. New sign-ups must supply city + postcode. Every user row has non-null city/postcode. Where a name is shown (home, profile), display_name is used if set, else email.

## Key Decisions Made

| Decision | Choice | Why (1 sentence) |
| --- | --- | --- |
| Field model | `city` + `postcode` (mirror walks) | Lets S-04 copy locality straight onto the walk with no mapping |
| Required vs optional | Both `NOT NULL`, **collected at sign-up** | Every user always has a locality → S-04/S-05 need no "is city set?" guard |
| display_name | Optional (nullable), falls back to email | No registration change for it; set later on the profile screen |
| Mandatory enforcement | DB `NOT NULL` + backfill existing rows | True DB-level guarantee (user reversed the lighter "nullable" option) |
| Profile screen | Singular `resource :profile`, show + edit | Matches Rails REST; each user edits only their own (`current_user`) |
| Validation | Presence + length cap, free-text | Matches PRD's deliberately coarse v1 locality (Open Q #6) |
| Home/nav | Profile nav link + home shows display_name | Makes profile reachable and surfaces the new field |
| Tests | Model validations + profile controller integration | Covers the validation rules and the new controller's happy/sad/auth paths |

## Scope

**In scope:** migration (display_name nullable; city/postcode NOT NULL via add→backfill→change-null); User validations + display-name fallback; registration captures city/postcode; profile resource (show/edit/update); nav link; home display_name; model + integration tests.

**Out of scope:** geolocation/radius/map; postcode format validation; city normalization (S-05's job); avatar/bio/phone; password/email change on profile; role editing.

## Architecture / Approach

Pure Rails CRUD on the existing User. Phase 1 is the coupled data layer — migration + model validation + registration capture + test-fixture updates must land together, because adding the NOT-NULL/presence rule breaks every user-creation path that doesn't supply the fields. Phase 2 is the independent profile resource plus nav/home wiring.

## Phases at a Glance

| Phase | What it delivers | Key risk |
| --- | --- | --- |
| 1. Schema + model + sign-up capture | Required city/postcode on users, collected at registration; suite green | Forgetting a user-creating test fixture → red suite; NOT-NULL on populated table needs backfill |
| 2. Profile resource + integration | Profile show/edit/update, nav link, home display_name, tests | Scoping update to current_user only (no cross-user edit); role must stay unpermitted |

**Prerequisites:** S-01 done (merged, PR #25); F-02 done (locality shape on walks).
**Estimated effort:** ~1 session across 2 phases.

## Open Risks & Assumptions

- Backfill placeholder for existing rows assumes no real users yet (roadmap baseline: two test users) — safe to stamp `"Unknown"`/`"00-000"`.
- Reversing the "nullable, edit later" option means re-touching the just-shipped S-01 registration form + its tests — accepted for the stronger DB guarantee.
- `display_label` fallback assumes email is an acceptable public-ish display until a name is set (v1).

## Success Criteria (Summary)

- A new user must supply city + postcode to sign up; every user row has both.
- A signed-in user can view their profile and edit display name + city + postcode, reflected on home.
- Blank city/postcode is rejected; signed-out profile access redirects to sign-in; suite + rubocop + brakeman green.
