---
change_id: tailwind-setup
title: Tailwind CSS setup + design tokens (U-01)
status: archived
created: 2026-06-25
updated: 2026-06-25
archived_at: 2026-06-25T13:25:18Z
---

## Notes

Foundation slice for the UI/UX polish stream (roadmap U-01).
Installs tailwindcss-rails (v3, standalone binary — no Node/npm needed),
wires the dev watcher as a background process in docker-compose,
and defines the brand token layer (primary = emerald, neutral = stone,
system font stack).

Existing application.css (~80 lines) stays unchanged; Tailwind output
coexists as a separate stylesheet until U-02..U-05 migrate each flow.
