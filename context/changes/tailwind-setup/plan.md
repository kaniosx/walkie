# Tailwind CSS Setup + Design Tokens Implementation Plan

## Overview

Install `tailwindcss-rails` (Tailwind v3, standalone binary — no Node/npm required),
configure the project's brand token layer, and wire a live CSS watcher into the
Docker dev environment. This is roadmap slice **U-01**, the foundation all UI
slices (U-02..U-05) build on.

## Current State Analysis

- **Asset pipeline**: Propshaft 1.3.2 + importmap-rails; no bundler, no Node.
  `stylesheet_link_tag :app` in the layout picks up `app/assets/stylesheets/application.css`.
- **CSS today**: ~80 lines of vanilla CSS (nav, flash, form containers).
  Remains untouched in this slice; both stylesheets coexist until U-02..U-05.
- **Container**: `ruby:3.4.9-slim`; WORKDIR `/rails`; host `.` → container `/rails`.
  No Foreman / `bin/dev` in use — dev server runs directly via `bin/rails server`.
- **Production**: `Dockerfile` already calls `bin/rails assets:precompile`;
  `tailwindcss-rails` hooks into this task automatically — no Dockerfile change needed.
- **No Tailwind anywhere yet** (Gemfile, Gemfile.lock, config, views).

### Key Discoveries

- `tailwindcss-rails` downloads a platform-specific standalone binary via `tailwindcss-ruby`
  companion gem; `bundle install` inside the container handles this automatically (linux-x64).
- The generator (`rails tailwindcss:install`) creates `app/assets/builds/` for compiled output.
  Propshaft serves files from this directory, but they are **not** auto-collected by the `:app`
  bundle — they must be included explicitly in the layout.
- `app/assets/builds/tailwind.css` must be gitignored (generated artefact); the generator
  handles this, but verify the entry exists in `.gitignore`.
- In production `assets:precompile` calls `tailwindcss:build` as a prerequisite (added by
  the gem), so the production Dockerfile needs no change.

## Desired End State

- Visiting any page in development: the browser loads both `application.css` and the
  compiled `tailwind.css` (served by Propshaft).
- Editing any `.html.erb` view and saving causes the Tailwind watcher to recompile CSS;
  Turbo picks up the change on next page load (no manual rebuild step).
- A Tailwind utility class added to any view (`class="text-primary-600"`) compiles
  correctly to the output CSS.
- `docker compose exec web bin/rails tailwindcss:build` exits 0 in CI/manual runs.
- No regressions in existing pages (current vanilla CSS still applied).

## What We're NOT Doing

- Migrating existing `application.css` to Tailwind utilities (that's U-02..U-05).
- Adding Tailwind Typography, Forms, or other plugins.
- Loading a web font (system font stack retained).
- Configuring CI (no GitHub Actions changes).
- Running Foreman / `bin/dev` (docker-compose bg-process approach instead).

## Implementation Approach

Use the `tailwindcss-rails` gem (v3) which ships a standalone Tailwind CLI binary.
The generator scaffolds the necessary files; we then customise the config for the
brand token layer. The dev watcher runs as a background shell process alongside
`bin/rails server` inside the existing docker-compose command string.

## Critical Implementation Details

- **Build order in docker-compose command**: `tailwindcss:watch` must be started _before_
  `bin/rails server` so the initial CSS build fires before the server accepts requests.
  Use the shell backgrounding pattern: `bin/rails tailwindcss:watch & bin/rails server …`.
- **Layout stylesheet ordering**: The Tailwind compiled stylesheet must be included _after_
  `stylesheet_link_tag :app` so Tailwind's resets and utilities can be overridden by
  project-specific styles in `application.css` if needed during the transition period.
- **`tailwindcss:install` generator side-effects**: The generator may create `Procfile.dev`
  and may overwrite the layout. Review every changed file before committing; keep
  `application.css` and existing layout nav/flash markup intact.

---

## Phase 1: Add Gem + Run Install Generator

### Overview

Add `tailwindcss-rails` to the Gemfile, install the bundle inside the container, then
run the generator which scaffolds `tailwind.config.js`, the input CSS, the build
directory, and updates the layout and `.gitignore`.

### Changes Required

#### 1. Gemfile

**File**: `Gemfile`

**Intent**: Add `tailwindcss-rails` as a runtime gem so it's available in all environments.

**Contract**: Add after the `importmap-rails` line:
```ruby
gem "tailwindcss-rails"
```

#### 2. Bundle install (container)

**File**: n/a — shell command

**Intent**: Install the gem and download the tailwindcss-ruby standalone binary for linux-x64.

**Contract**: Run inside the running container:
```
docker compose exec web bundle install
```

#### 3. Run the install generator (container)

**File**: generates multiple files (see below)

**Intent**: Scaffold all Tailwind boilerplate in one step.

**Contract**: Run inside the container:
```
docker compose exec web bin/rails tailwindcss:install
```

Expected generated / modified files:
- `app/assets/stylesheets/application.tailwind.css` — input file with `@tailwind` directives
- `app/assets/builds/.keep` — creates the builds output directory
- `tailwind.config.js` — default config (we customise in Phase 2)
- `.gitignore` — `app/assets/builds/` entry added
- `app/views/layouts/application.html.erb` — generator may add stylesheet tag (review!)
- `Procfile.dev` — generator may create this; can be committed or ignored, but do NOT
  change docker-compose.yml to use it (that's Phase 3)

#### 4. Layout stylesheet inclusion

**File**: `app/views/layouts/application.html.erb`

**Intent**: Ensure the compiled Tailwind CSS is served alongside the existing stylesheet.
The generator may handle this; verify and adjust if needed.

**Contract**: The `<head>` section must contain both tags in this order:
```erb
<%= stylesheet_link_tag :app, "data-turbo-track": "reload" %>
<%= stylesheet_link_tag "tailwind", "data-turbo-track": "reload" %>
```
If the generator placed `"tailwind"` before `:app`, swap the order so `application.css`
can override Tailwind resets where needed during the coexistence period.

### Success Criteria

#### Automated Verification

- `docker compose exec web bundle exec rubocop --no-color Gemfile` exits 0
- `docker compose exec web bin/rails tailwindcss:build` exits 0 and produces
  `app/assets/builds/tailwind.css`
- `git diff --name-only | grep -E 'application\.html\.erb'` — confirm layout change
- `.gitignore` contains `/app/assets/builds/`

#### Manual Verification

- Start `make start` and visit any page; browser DevTools Network shows both
  `application.css` and `tailwind.css` loaded (HTTP 200)
- Existing nav and flash styling is visually unchanged

**Implementation Note**: Pause after Phase 1 manual verification before proceeding to Phase 2.

---

## Phase 2: Customise Config + Design Tokens

### Overview

Replace the generated default `tailwind.config.js` with a project-specific config that
sets correct content paths and extends the theme with brand tokens
(primary = emerald, neutral = stone, system font).

### Changes Required

#### 1. tailwind.config.js

**File**: `tailwind.config.js`

**Intent**: Scope content scanning to Rails view paths and extend the default theme with
Walkie's brand token layer so utility classes like `text-primary-600` and `bg-stone-50`
compile to the output CSS.

**Contract**: Replace generated content with:
```js
const colors = require('tailwindcss/colors')

module.exports = {
  content: [
    './app/views/**/*.html.erb',
    './app/helpers/**/*.rb',
    './app/javascript/**/*.js',
  ],
  theme: {
    extend: {
      colors: {
        primary: colors.emerald,
        neutral: colors.stone,
      },
      fontFamily: {
        sans: ['system-ui', '-apple-system', 'sans-serif'],
      },
    },
  },
  plugins: [],
}
```

#### 2. app/assets/stylesheets/application.tailwind.css

**File**: `app/assets/stylesheets/application.tailwind.css`

**Intent**: Ensure the input file has all three Tailwind layers so reset, component, and
utility classes are all present in the compiled output.

**Contract**: File must contain exactly:
```css
@tailwind base;
@tailwind components;
@tailwind utilities;
```
The generator usually creates this correctly; verify and leave unchanged if so.

### Success Criteria

#### Automated Verification

- `docker compose exec web bin/rails tailwindcss:build` exits 0
- `grep -c 'emerald' app/assets/builds/tailwind.css` returns > 0 (token compiled)
- `grep 'text-primary' app/assets/builds/tailwind.css` — verify custom token compiles
  (add `class="text-primary-600"` temporarily to a view, rebuild, grep, then remove)
- `docker compose exec web bundle exec rubocop --no-color tailwind.config.js` — N/A
  (JS file; skip rubocop)

#### Manual Verification

- `class="bg-primary-100 text-primary-800"` on any ERB element renders with green
  background after watcher rebuild (visual check in browser)
- Remove test class after verification — do not commit it

**Implementation Note**: Pause after Phase 2 manual verification before proceeding to Phase 3.

---

## Phase 3: Wire Dev Watcher in docker-compose

### Overview

Update the docker-compose.yml `web` service command to start the Tailwind watcher as a
background shell process before starting the Rails server. This gives live CSS recompilation
on view file saves without adding new tooling.

### Changes Required

#### 1. docker-compose.yml — web command

**File**: `docker-compose.yml`

**Intent**: Run `tailwindcss:watch` as a background process so CSS recompiles automatically
when views change, without blocking the Rails server startup.

**Contract**: Change the `command:` block of the `web` service from:
```yaml
command: >
  bash -c "rm -f tmp/pids/server.pid &&
           bin/rails db:prepare &&
           RAILS_ENV=test bin/rails db:prepare &&
           bin/rails server -b 0.0.0.0 -p 3000"
```
To:
```yaml
command: >
  bash -c "rm -f tmp/pids/server.pid &&
           bin/rails db:prepare &&
           RAILS_ENV=test bin/rails db:prepare &&
           bin/rails tailwindcss:watch &
           bin/rails server -b 0.0.0.0 -p 3000"
```
The `&` backgrounds the watcher; the Rails server remains the foreground process.
`docker compose stop` will terminate both.

### Success Criteria

#### Automated Verification

- `docker compose config` exits 0 (valid YAML)

#### Manual Verification

- `make start` boots successfully; logs show both Tailwind watcher output and Puma output
- Edit any `.html.erb` view, save; watcher log line appears; reload the browser page
  — new class compiles without manual `tailwindcss:build`
- `docker compose stop` terminates cleanly (no zombie processes)

**Implementation Note**: Pause after Phase 3 manual verification. This is the full acceptance
test for the slice.

---

## Testing Strategy

### Automated Tests

No new Minitest tests for this slice. Tailwind is infrastructure; correctness is verified
by:
- Build command exit codes (Phases 1–2)
- YAML validity (`docker compose config`)
- CSS content grep (Phase 2)

### Manual Testing Steps

1. `make start` — confirm both watcher and server start
2. Visit `/` in browser, open DevTools → Network; verify `tailwind.css` returns HTTP 200
3. Add `class="bg-primary-500 text-white p-4"` to any view, save, reload — green box visible
4. Remove test class, rebuild, confirm it disappears from compiled CSS
5. Commit; run pre-commit hook — rubocop on Gemfile passes, no test files to run

## Performance Considerations

The Tailwind standalone binary adds ~1–2 seconds to container startup (initial build).
Subsequent watch-mode rebuilds are typically < 500ms. In production, `assets:precompile`
adds one Tailwind build (~1–3s) to the Docker image build time — acceptable.

## Migration Notes

- `app/assets/builds/` is gitignored; each developer's container rebuilds it on `make start`.
- When deploying to Render, ensure the production Docker build has internet access during
  `bundle install` so `tailwindcss-ruby` can download the linux-x64 binary.
- U-02..U-05 will migrate individual pages from vanilla CSS to Tailwind utilities.
  `application.css` can be progressively emptied as each flow is migrated.

## References

- Roadmap: `context/foundation/roadmap.md` — U-01 (tailwind-setup)
- tailwindcss-rails gem: https://github.com/rails/tailwindcss-rails
- Related slices: U-02 (ui-layout-and-nav), U-03..U-05 (dashboards)
- Tech stack: `context/foundation/tech-stack.md`

---

## Progress

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles.

### Phase 1: Add Gem + Run Install Generator

#### Automated

- [x] 1.1 `rubocop Gemfile` exits 0 — 4b56861
- [x] 1.2 `tailwindcss:build` exits 0 and produces `app/assets/builds/tailwind.css` — 4b56861
- [x] 1.3 `git diff --name-only` confirms layout updated — 4b56861
- [x] 1.4 `.gitignore` contains `/app/assets/builds/` — 4b56861

#### Manual

- [ ] 1.5 Browser DevTools shows both `application.css` and `tailwind.css` loaded (HTTP 200)
- [ ] 1.6 Existing nav and flash styling visually unchanged

### Phase 2: Customise Config + Design Tokens

#### Automated

- [x] 2.1 `tailwindcss:build` exits 0 after config update — 5c56305
- [x] 2.2 `grep -c 'emerald' app/assets/builds/tailwind.css` > 0 — 5c56305
- [x] 2.3 Temporary `text-primary-600` class compiles; removed after check — 5c56305

#### Manual

- [x] 2.4 `bg-primary-100 text-primary-800` renders as green in browser
- [x] 2.5 Test class removed and absent from compiled CSS after rebuild

### Phase 3: Wire Dev Watcher in docker-compose

#### Automated

- [x] 3.1 `docker compose config` exits 0

#### Manual

- [x] 3.2 `make start` boots; logs show watcher + Puma
- [x] 3.3 View edit → watcher recompiles → class visible in browser without manual rebuild
- [x] 3.4 `docker compose stop` terminates cleanly
