# UI Layout Shell + Role-Aware Navigation Implementation Plan

## Overview

Style the global application layout with Tailwind CSS: responsive navbar with role-aware links
and mobile hamburger menu, flash message area with auto-dismiss. This is roadmap slice **U-02**,
the shared shell that all subsequent UI slices (U-03..U-05) build on.

## Current State Analysis

- **Layout**: `app/views/layouts/application.html.erb` — nav is inline (no partial), flash is two
  bare `tag.div` calls, no `javascript_importmap_tags` (Stimulus not loaded in browser).
- **Vanilla CSS nav**: `application.css:17-23` defines `nav {}` and `nav a {}` — will be removed
  and replaced by Tailwind utilities. Flash classes (`.flash-alert`, `.flash-notice`) are kept.
- **JavaScript**: zero Stimulus controllers exist; `app/javascript/` directory does not exist;
  `config/importmap.rb` has no explicit file (uses Rails defaults). Stimulus and Turbo gems are
  installed but Stimulus is not wired into the browser.
- **Routes**: `root_path`, `new_session_path`, `new_registration_path`, `profile_path`,
  `dogs_path`, `walks_path`, `open_requests_path`, `walker_walks_path`, `session_path` (DELETE).
- **Auth helpers**: `authenticated?` and `current_user` from `Authentication` concern,
  `current_user.owner?` / `current_user.walker?` from User model.

### Key Discoveries

- `app/views/layouts/application.html.erb:22-23` — stylesheet tags present but no JS tag.
  Stimulus cannot fire until `javascript_importmap_tags` is added.
- `config/importmap.rb` likely doesn't exist (agent found none) — Phase 1 must create it so
  Turbo and Stimulus are pinned and loadable.
- The `eagerLoadControllersFrom` pattern (stimulus-rails) auto-registers any controller file added
  to `app/javascript/controllers/` by filename convention — no manual registration per controller.
- `data-turbo-permanent` on the flash container preserves it across Turbo navigations but also
  prevents Turbo from injecting NEW flash messages from server responses into that container.
  Net effect: use turbo-permanent + Stimulus dismiss so flash shown once is auto-cleared after 4s,
  and new flashes on next navigation naturally render (Turbo replaces the permanent container only
  when its ID matches the server-rendered element with the same ID).

## Desired End State

- Every page loads `application.js` via importmap; browser console shows no Stimulus errors.
- Desktop navbar: logo on left, role-aware links in middle, Profile + Sign out on right;
  unauthenticated: logo + Sign in + Sign up.
- Mobile (< `md`): logo + hamburger icon; tapping hamburger slides in / shows vertical nav menu.
- Flash messages appear with Tailwind-styled colours, auto-dismiss after 4 seconds.
- `docker compose exec web bin/rails rubocop --no-color` passes on all new/edited files.

## What We're NOT Doing

- No PWA, no service worker, no push notifications.
- No full-page animations beyond Tailwind transitions on the mobile menu.
- Not migrating flash CSS classes (`.flash-alert`, `.flash-notice`) to Tailwind utilities yet —
  kept in `application.css` to reduce scope; U-03..U-05 will clean them up per-flow.
- Not adding breadcrumbs, page titles in the nav, or user avatars.
- Not adding Turbo Streams for flash injection (overkill for MVP).

## Implementation Approach

Three sequential phases: first wire Stimulus into the browser (infrastructure), then build the nav
partial with the hamburger controller, then handle flash with auto-dismiss. The `eagerLoadControllersFrom`
helper auto-discovers controllers by filename, so phases 2 and 3 only add new files — no index.js
changes needed per controller.

## Critical Implementation Details

- **`data-turbo-permanent` gotcha**: a permanent element is preserved by Turbo only when the new
  page response contains a matching element with the same `id`. The flash container must have a
  stable `id="flash-container"` in both the layout and the server response. If the server response
  omits the ID, Turbo discards the permanent element and flash is lost. Confirm by checking that
  the flash partial always renders the wrapper div with `id="flash-container"`, even when there
  are no messages (empty but present).
- **importmap pin order**: `@hotwired/turbo-rails` must be pinned before `application` so Turbo
  is available when `application.js` imports it.

---

## Phase 1: JavaScript Infrastructure

### Overview

Create `config/importmap.rb`, the `app/javascript/` directory structure, and add
`javascript_importmap_tags` to the layout. This makes Turbo and Stimulus available in the browser
for the first time.

### Changes Required

#### 1. config/importmap.rb

**File**: `config/importmap.rb`

**Intent**: Pin Turbo, Stimulus, and the controllers directory so the browser can load them
via importmap.

**Contract**: Must contain at minimum:
```ruby
pin "application", preload: true
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js", preload: true
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js", preload: true
pin_all_from "app/javascript/controllers", under: "controllers"
```

#### 2. app/javascript/application.js

**File**: `app/javascript/application.js`

**Intent**: Entry point — imports Turbo and all Stimulus controllers.

**Contract**:
```js
import "@hotwired/turbo-rails"
import "controllers"
```

#### 3. app/javascript/controllers/application.js

**File**: `app/javascript/controllers/application.js`

**Intent**: Creates and exports the Stimulus Application singleton.

**Contract**:
```js
import { Application } from "@hotwired/stimulus"
const application = Application.start()
application.debug = false
window.Stimulus = application
export { application }
```

#### 4. app/javascript/controllers/index.js

**File**: `app/javascript/controllers/index.js`

**Intent**: Eager-loads all controllers from this directory using stimulus-rails helper, so any
`*_controller.js` file added to `controllers/` is auto-registered without touching this file.

**Contract**:
```js
import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
eagerLoadControllersFrom("controllers", application)
```

#### 5. app/views/layouts/application.html.erb — add JS tag

**File**: `app/views/layouts/application.html.erb`

**Intent**: Add `javascript_importmap_tags` to `<head>` so the importmap and application.js
are loaded on every page.

**Contract**: Add after the two `stylesheet_link_tag` lines:
```erb
<%= javascript_importmap_tags %>
```

### Success Criteria

#### Automated Verification

- `docker compose exec web bundle exec rubocop --no-color config/importmap.rb` exits 0
- `docker compose exec web bin/rails assets:precompile` exits 0 (confirms importmap valid)

#### Manual Verification

- Open browser DevTools → Console on any page; no uncaught JS errors; Stimulus logs "Starting" or similar
- DevTools → Sources → verify `application.js` is loaded from importmap

**Implementation Note**: Pause after Phase 1 manual verification before proceeding to Phase 2.

---

## Phase 2: Navigation Partial + Stimulus + Tailwind

### Overview

Extract the inline nav to `_nav.html.erb`, apply Tailwind classes for desktop and mobile layouts,
create `nav_controller.js` for the hamburger toggle, and remove the now-redundant vanilla CSS.

### Changes Required

#### 1. app/javascript/controllers/nav_controller.js

**File**: `app/javascript/controllers/nav_controller.js`

**Intent**: Toggle the mobile menu open/closed when the hamburger button is clicked.
Also close the menu when focus leaves the nav (clicking outside).

**Contract**:
- `data-controller="nav"` on the outer `<nav>` element
- `data-nav-target="menu"` on the mobile menu container div
- Action `data-action="click->nav#toggle"` on the hamburger `<button>`
- `toggle()` method: adds/removes `hidden` class on the menu target; also toggles
  `aria-expanded` on the button for a11y
- `close()` method: adds `hidden` and sets `aria-expanded="false"`; connected to
  `click@window->nav#closeOutside` to dismiss when clicking elsewhere

#### 2. app/views/layouts/_nav.html.erb

**File**: `app/views/layouts/_nav.html.erb` (new partial)

**Intent**: Self-contained nav component with responsive desktop/mobile layout.

**Contract**: The partial renders:
- A `<nav>` element with `data-controller="nav"` and Tailwind classes for white background,
  bottom border, horizontal padding.
- **Desktop layout** (visible at `md:` breakpoint):
  - Left: "Walkie" logo link (`root_path`)
  - Center/right: role-based links in a horizontal `<ul>`:
    - Unauthenticated: Sign in (`new_session_path`) + Sign up (`new_registration_path`)
    - Authenticated Owner: My dogs (`dogs_path`) + My requests (`walks_path`) + Profile (`profile_path`)
    - Authenticated Walker: Open requests (`open_requests_path`) + My walk (`walker_walks_path`) + Profile (`profile_path`)
  - Far right: Sign out `button_to` (`session_path`, method: :delete) — only when authenticated
- **Mobile layout** (visible below `md:`):
  - Row: logo + hamburger `<button>` (right-aligned), `aria-expanded` toggled by controller
  - Below the row: a `<div data-nav-target="menu">` with `hidden` class by default,
    containing the same links as desktop in a stacked vertical list
- All link items use consistent Tailwind spacing + hover classes (`hover:text-primary-600` or similar)

#### 3. app/views/layouts/application.html.erb — render partial, remove inline nav

**File**: `app/views/layouts/application.html.erb`

**Intent**: Replace the inline `<nav>…</nav>` block with a `render` call to the new partial.

**Contract**: Replace lines 27-40 (the `<nav>` block) with:
```erb
<%= render "layouts/nav" %>
```

#### 4. app/assets/stylesheets/application.css — remove nav styles

**File**: `app/assets/stylesheets/application.css`

**Intent**: Remove the two nav rule blocks (`nav {}` and `nav a {}`) that Tailwind utilities
now replace. Do not touch flash, form, or body rules.

**Contract**: Delete lines 17-23 (the `nav {}` block) and lines 25-29 (the `nav a {}` block).

### Success Criteria

#### Automated Verification

- `docker compose exec web bundle exec rubocop --no-color app/views/layouts/` exits 0
- `docker compose exec web bin/rails tailwindcss:build` exits 0 (nav classes compile)

#### Manual Verification

- Desktop (≥ 768px): nav shows logo + role-appropriate links + Sign out; no horizontal overflow
- Mobile (< 768px): hamburger visible; clicking opens vertical menu; clicking outside closes it
- Unauthenticated user sees Sign in + Sign up in nav (both desktop and mobile)
- Sign out button works (POST delete, redirects to sign-in)
- `aria-expanded` toggles correctly on hamburger button (DevTools Elements check)

**Implementation Note**: Pause after Phase 2 manual verification before proceeding to Phase 3.

---

## Phase 3: Flash Messages + Auto-Dismiss

### Overview

Add a Stimulus `flash` controller that removes each flash div after 4 seconds, and wrap flash
messages in a `data-turbo-permanent` container with a stable ID.

### Changes Required

#### 1. app/javascript/controllers/flash_controller.js

**File**: `app/javascript/controllers/flash_controller.js`

**Intent**: Auto-dismiss the flash element after a configurable delay (default 4000ms).

**Contract**:
- `data-controller="flash"` on each flash `<div>`
- `data-flash-delay-value="4000"` (optional override)
- `connect()`: calls `setTimeout(() => this.element.remove(), this.delayValue)`
- Value: `static values = { delay: { type: Number, default: 4000 } }`

#### 2. app/views/layouts/application.html.erb — update flash section

**File**: `app/views/layouts/application.html.erb`

**Intent**: Wrap flash messages in a `data-turbo-permanent` container with a stable `id`
so the container survives Turbo Drive navigations. Wire each flash div to the Stimulus controller.

**Contract**: Replace the current two bare flash lines with:
```erb
<div id="flash-container" data-turbo-permanent>
  <%= tag.div(flash[:alert],
        class: "flash-alert",
        data: { controller: "flash" }) if flash[:alert] %>
  <%= tag.div(flash[:notice],
        class: "flash-notice",
        data: { controller: "flash" }) if flash[:notice] %>
</div>
```
The `id="flash-container"` must be stable and present in every response so Turbo recognises
the permanent element correctly (see Critical Implementation Details above).

### Success Criteria

#### Automated Verification

- `docker compose exec web bundle exec rubocop --no-color app/views/layouts/application.html.erb` exits 0

#### Manual Verification

- Submit a form that produces a flash (e.g., sign in with wrong password → alert appears)
- Flash auto-dismisses after ~4 seconds without page reload
- Navigate to another page via Turbo Drive; a new flash on that page appears and auto-dismisses
- Flash container `id="flash-container"` visible in DevTools Elements even when no flash active

**Implementation Note**: Pause after Phase 3 manual verification. This is the full acceptance
test for the slice.

---

## Testing Strategy

### Automated Tests

No new Minitest tests for this slice. Infrastructure validation:
- `rubocop` on all new/edited files
- `tailwindcss:build` exits 0 (nav classes compile)
- `assets:precompile` exits 0 (importmap valid)

### Manual Testing Steps

1. Sign in as Owner → verify nav shows "My dogs", "My requests", "Profile", Sign out
2. Sign in as Walker → verify nav shows "Open requests", "My walk", "Profile", Sign out
3. Sign out → verify nav shows "Sign in", "Sign up"
4. Resize browser to < 768px → verify hamburger appears; click → menu opens; click outside → menu closes
5. Submit form with error → flash appears → wait 4s → auto-dismissed
6. Navigate to another page → new flash shows if applicable

## Performance Considerations

The importmap adds one `<script type="importmap">` inline tag and several `<link rel="modulepreload">`
tags — negligible overhead on server-rendered pages. The Stimulus app initialises in < 5ms.

## References

- Roadmap: `context/foundation/roadmap.md` — U-02 (ui-layout-and-nav)
- GitHub issue: #32
- Tailwind config: `config/tailwind.config.js`
- Foundation: `context/archive/2026-06-25-tailwind-setup/`
- Related slices: U-03 (auth screens), U-04 (owner dashboard), U-05 (walker dashboard)

---

## Progress

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles.

### Phase 1: JavaScript Infrastructure

#### Automated

- [x] 1.1 `rubocop config/importmap.rb` exits 0 — 965750d
- [x] 1.2 `assets:precompile` exits 0 — 965750d

#### Manual

- [x] 1.3 Browser console shows no JS errors; Stimulus loaded — 965750d
- [x] 1.4 DevTools Sources confirms application.js loaded — 965750d

### Phase 2: Navigation Partial + Stimulus + Tailwind

#### Automated

- [x] 2.1 `rubocop app/views/layouts/` exits 0
- [x] 2.2 `tailwindcss:build` exits 0

#### Manual

- [x] 2.3 Desktop nav: logo + role links + sign out visible
- [x] 2.4 Mobile: hamburger opens/closes menu; aria-expanded toggles
- [x] 2.5 Unauthenticated: Sign in + Sign up in nav
- [x] 2.6 Sign out works (redirect to sign-in)

### Phase 3: Flash Messages + Auto-Dismiss

#### Automated

- [ ] 3.1 `rubocop app/views/layouts/application.html.erb` exits 0

#### Manual

- [ ] 3.2 Flash appears after form action; auto-dismisses in ~4s
- [ ] 3.3 Turbo navigation: new flash on destination page appears correctly
- [ ] 3.4 Flash container `id="flash-container"` present in DOM even without messages
