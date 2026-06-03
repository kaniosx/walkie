# Follow-ups from impl-review (2026-06-03)

## Install importmap-rails so `bin/ci` / `scan_js` pass (pre-existing gap)

**Source**: F1, impl-review.md — Success Criteria.

**Problem**: `bin/ci`'s `Security: Importmap vulnerability audit` step and the GitHub Actions `scan_js` job both fail (exit 127) because importmap-rails was never installed in this skeleton — there is no `config/importmap.rb`, no `bin/importmap` binstub, and no `app/javascript/`. This predates F-03 and is outside its scope ("not touching existing jobs"). F-03's own Tests step is green locally and remote-verified.

**Action (separate change)**: Run `bin/rails importmap:install` (creates `config/importmap.rb`, `bin/importmap`, `app/javascript/application.js`, adds `javascript_importmap_tags` to the layout), then confirm `bin/importmap audit`, `bin/ci`, and the GHA `scan_js` job all pass. Alternatively, if importmap JS is not wanted for the MVP, remove the importmap audit step from `config/ci.rb` and the `scan_js` job — but that's a product/stack decision.

**Why deferred**: Closing it inside F-03 would expand a tooling change into layout/config/JS scaffolding the plan explicitly excluded.

## Commit db/schema.rb when the first migration lands (F-02)

**Source**: F2, impl-review.md — Reliability (latent).

**Problem**: The GHA `test` job and local CI run `bin/rails db:prepare` against an empty DB. The repo has no migrations and no committed `db/schema.rb` yet, so this is benign today. Once F-02 (walks schema) adds the first migration, if `db/schema.rb` is not committed, CI's `db:prepare` can create an empty DB and the suite fails confusingly (tables missing).

**Action (F-02)**: Ensure `db/schema.rb` is committed alongside the first migration so `db:prepare` loads the schema in CI. No change needed in F-03.

