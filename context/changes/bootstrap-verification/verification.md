---
bootstrapped_at: 2026-05-21T14:28:57Z
starter_id: rails
starter_name: Ruby on Rails
project_name: walkie
language_family: ruby
package_manager: bundle
cwd_strategy: subdir-then-move
bootstrapper_confidence: verified
phase_3_status: ok
audit_command: bundle audit check --update
---

## Hand-off

Verbatim copy of `context/foundation/tech-stack.md` frontmatter:

```yaml
starter_id: rails
package_manager: bundle
project_name: walkie
hints:
  language_family: ruby
  team_size: solo
  deployment_target: fly
  ci_provider: github-actions
  ci_default_flow: auto-deploy-on-merge
  bootstrapper_confidence: verified
  path_taken: standard
  quality_override: false
  self_check_answers: null
  has_auth: true
  has_payments: false
  has_realtime: false
  has_ai: false
  has_background_jobs: false
```

### Why this stack (from hand-off body)

Solo learner shipping a two-sided dog-walking marketplace MVP in 3 weeks of
after-hours work. Rails is the recommended default for `(web, ruby)` and fits
the PRD priors tightly: ActiveRecord + migrations cover the dog / walk / user
models, the linear walk state machine (REQUESTED → ACCEPTED → IN_PROGRESS →
COMPLETED) drops cleanly into a Rails model with validations plus a
transactional guard for the single-Walker-acceptance race, the built-in
`bin/rails generate authentication` covers FR-001 to FR-005, and role
separation is enforced via scoped queries and controller filters. Fly is the
starter's verified deployment default; CI on GitHub Actions with auto-deploy
on merge matches a solo / short-timeline build. One heads-up: Rails carries
`typed: false` in the agent-friendly registry — Ruby's discipline leans on
conventions + tests rather than static types — so the agent compensation
(documenting Rails conventions in `CLAUDE.md` / `AGENTS.md` after bootstrap)
matters more here than on a TypeScript stack.

## Pre-scaffold verification

| Signal      | Value                                                  | Severity | Notes                                                                                  |
| ----------- | ------------------------------------------------------ | -------- | -------------------------------------------------------------------------------------- |
| npm package | not run                                                | n/a      | non-JS starter; `cmd_template` invokes `rails new`, not a `create-*` npm CLI           |
| GitHub repo | not run                                                | n/a      | card `docs_url` is `https://guides.rubyonrails.org` (documentation portal, not a GitHub repo) |

No recency signal was available from either source. Rails is a verified
starter in the registry and ships from system gems already installed on
this machine (`rails --version` → Rails 8.1.3), so the absence of a network
recency check is not a concern for this run.

## Scaffold log

**Resolved invocation**: `rails new .bootstrap-scaffold --database postgresql --skip-bundle --skip-test`
**Strategy**: subdir-then-move
**Exit code**: 0
**Files moved**: 22 top-level entries (10 files, 12 directories) moved from `.bootstrap-scaffold/` up into cwd
**Conflicts (.scaffold siblings)**: `.git.scaffold/` (rails ran `git init -b main` inside the temp directory; cwd's existing `.git/` won per the conflict matrix, scaffold's empty fresh repo was sidelined as `.git.scaffold/`)
**.gitignore handling**: append-merged — cwd's prior contents (single `.` line) preserved at the top, followed by a `# from rails` separator and the full rails-generated ignore set
**.bootstrap-scaffold cleanup**: deleted (move-up left the directory empty)

### Files moved (top-level)

Files: `README.md`, `Rakefile`, `.ruby-version`, `config.ru`, `.gitattributes`, `Gemfile`, `Dockerfile`, `.dockerignore`, `.rubocop.yml`, `.git.scaffold/` (renamed from `.git/`)

Directories: `app/`, `bin/`, `config/`, `db/`, `lib/`, `log/`, `public/`, `script/`, `storage/`, `tmp/`, `vendor/`, `.github/`

Preserved in cwd (existing-wins or special-cased): `context/` (canonical, scaffold never touches it), `CLAUDE.md` (cwd-owned), `idea-notes.md`, `skills-lock.json`, `.vscode/`, `.claude/`, `.git/` (your existing repo history is untouched).

## Post-scaffold audit

**Tool**: `bundle audit check --update`
**Status**: failed to run
**Reason**: `bundler-audit` gem is not installed system-wide (the bundler subcommand `audit` reported `Could not find command "audit"`), and the scaffold ran with `--skip-bundle`, so no `Gemfile.lock` exists yet for the audit tool to consume.

**Recommended manual follow-up**:

1. Install dependencies: `bundle install` (creates `Gemfile.lock`).
2. Install the audit gem: `gem install bundler-audit`.
3. Re-run the audit: `bundle audit check --update`.

Alternatively, the rails scaffold shipped `bin/bundler-audit` and `config/bundler-audit.yml` — after `bundle install`, `./bin/bundler-audit check --update` will work via the project's bundle.

**Partial output**:

```
Could not find command "audit".
(exit status 15)
```

## Hints recorded but not acted on

| Hint                       | Value             |
| -------------------------- | ----------------- |
| bootstrapper_confidence    | verified          |
| quality_override           | false             |
| path_taken                 | standard          |
| self_check_answers         | null              |
| team_size                  | solo              |
| deployment_target          | fly               |
| ci_provider                | github-actions    |
| ci_default_flow            | auto-deploy-on-merge |
| has_auth                   | true              |
| has_payments               | false             |
| has_realtime               | false             |
| has_ai                     | false             |
| has_background_jobs        | false             |

These hints were read by bootstrapper and copied here for audit-trail
completeness; v1 does not act on them. A future skill (M1L4 — agent
context / "Memory Architecture") will consume these values to shape
`CLAUDE.md` / `AGENTS.md`, scaffold CI workflow files based on
`ci_provider` and `ci_default_flow`, and compensate for any
`bootstrapper_confidence: best-effort` or `quality_override: true` flags.

## Next steps

Next: a future skill will set up agent context (CLAUDE.md, AGENTS.md). For now, your project is scaffolded and verified — happy hacking.

Useful manual steps in the meantime:

- Your existing `.git/` is untouched. The scaffold's fresh `git init` landed at `.git.scaffold/`; review and delete it (`rm -rf .git.scaffold/`) once you have confirmed nothing of value lives there.
- Review any `.scaffold` siblings the conflict policy created and decide which version of each file to keep.
- Run `bundle install` to install dependencies and generate `Gemfile.lock`. Then `gem install bundler-audit` (or `./bin/bundler-audit` via bundle) to enable the security audit that was skipped in this run.
- Set up your Postgres database: `bin/rails db:create db:migrate` (rails was scaffolded with `--database postgresql`; ensure `psql` is on PATH and a local Postgres server is reachable).
- Address audit findings per your project's risk tolerance once `bundle audit check --update` is runnable — the full breakdown will be in this log on the next bootstrap run, or you can run the command manually now.
