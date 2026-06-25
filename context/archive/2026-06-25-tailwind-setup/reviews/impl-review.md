<!-- IMPL-REVIEW-REPORT -->
# Implementation Review: Tailwind CSS Setup + Design Tokens

- **Plan**: `context/changes/tailwind-setup/plan.md`
- **Scope**: Wszystkie 3 fazy
- **Date**: 2026-06-25
- **Verdict**: NEEDS ATTENTION
- **Findings**: 0 critical, 2 warnings, 2 observations

## Verdicts

| Dimension | Verdict |
|-----------|---------|
| Plan Adherence | PASS |
| Scope Discipline | WARNING |
| Safety & Quality | WARNING |
| Architecture | PASS |
| Pattern Consistency | WARNING |
| Success Criteria | PASS |

## Success Criteria

**Automated:** rubocop Gemfile ✅ | tailwindcss:build ✅ | docker compose config ✅ | .gitignore ✅

**Manual:** 1.5 ✅ 1.6 ✅ 2.4 ✅ 2.5 ✅ 3.2 ✅ 3.3 ✅ 3.4 ✅

## Findings

### F1 — Procfile.dev + bin/dev: martwy kod, ryzyko dezorientacji

- **Severity**: ⚠️ WARNING
- **Impact**: 🔎 MEDIUM — warto się zatrzymać; ryzyko realne
- **Dimension**: Scope Discipline / Safety & Quality
- **Location**: bin/dev:1-18, Procfile.dev:1-2
- **Detail**: Generator stworzył Procfile.dev i bin/dev jako side-effecty. bin/dev próbuje gem install foreman na hoście bez Ruby toolchain (CLAUDE.md: "No bundler on host"). Deweloper może uruchomić bin/dev i dostać broken env oderwane od Dockera.
- **Fix A ⭐ Recommended**: Usuń oba pliki (`git rm bin/dev Procfile.dev`)
  - Strength: Eliminuje confusion gap; docker-compose.yml jest jedynym entry pointem.
  - Tradeoff: Generator odtworzy je przy następnym tailwindcss:install.
  - Confidence: HIGH — CLAUDE.md wprost zabrania uruchamiania bundlera na hoście.
  - Blind spot: None significant.
- **Fix B**: Zastąp bin/dev no-op skryptem z komentarzem
  - Strength: Jawna dokumentacja "nie używaj".
  - Tradeoff: Procfile.dev nadal by pozostał.
  - Confidence: MEDIUM.
  - Blind spot: Partial fix.
- **Decision**: FIXED via Fix A — 05e8ea5

### F2 — docker-compose: brak obsługi sygnałów dla background watchera

- **Severity**: ⚠️ WARNING
- **Impact**: 🔎 MEDIUM — warto się zatrzymać; realny tradeoff
- **Dimension**: Safety & Quality
- **Location**: docker-compose.yml:26
- **Detail**: `bin/rails tailwindcss:watch &` nie przechwytuje PID. Na docker compose stop watcher może zostać zombie. Jeśli watcher crashuje, CSS przestaje się aktualizować bez widocznego błędu.
- **Fix A ⭐ Recommended**: Dodaj trap dla PID watchera
  ```
  bin/rails tailwindcss:watch & TAILWIND_PID=$!
  trap "kill $TAILWIND_PID 2>/dev/null" EXIT INT TERM
  bin/rails server -b 0.0.0.0 -p 3000
  ```
  - Strength: Standardowy bash pattern, gwarantuje reap przy EXIT/INT/TERM.
  - Tradeoff: Komplikuje linię komendy w YAML.
  - Confidence: HIGH.
  - Blind spot: Nie rozwiązuje braku auto-restartu watchera po crashu.
- **Fix B**: Pozostaw bez zmian — akceptuj ryzyko dev-only
  - Strength: Zero złożoności.
  - Tradeoff: Confusing UX gdy watcher cicho umiera.
  - Confidence: LOW.
  - Blind spot: Nie wiemy jak często watcher crasha.
- **Decision**: FIXED via Fix A — 90fe985

### F3 — Content glob może przeoczyć partiale bez `.html` w nazwie

- **Severity**: 💬 OBSERVATION
- **Impact**: 🏃 LOW — szybka decyzja; zmiana oczywista
- **Dimension**: Pattern Consistency
- **Location**: config/tailwind.config.js:5
- **Detail**: `./app/views/**/*.html.erb` nie łapie `_tag.erb` (brak `.html`). Gem default używa `**/*.{erb,haml,html,slim}`. Ponadto `app/javascript/` nie istnieje jeszcze.
- **Fix**: Zmień na `'./app/views/**/*.{html,erb}'`
- **Decision**: FIXED — 941e76f

### F4 — inter-font.css nadal precompiluje się w produkcji

- **Severity**: 💬 OBSERVATION
- **Impact**: 🏃 LOW — szybka decyzja; zmiana oczywista
- **Dimension**: Pattern Consistency
- **Location**: config/environments/production.rb (brak wpisu)
- **Detail**: Gem dodaje inter-font.css do assets.precompile przez initializer, nawet bez linka w layoucie. Nieużywany plik w manifeście produkcyjnym.
- **Fix**: Dodaj do config/environments/production.rb: `config.assets.precompile -= %w[inter-font.css]`
- **Decision**: FIXED — 9b1816c
