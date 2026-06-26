<!-- IMPL-REVIEW-REPORT -->
# Implementation Review: UI Layout Shell + Role-Aware Navigation

- **Plan**: `context/changes/ui-layout-and-nav/plan.md`
- **Scope**: Wszystkie 3 fazy
- **Date**: 2026-06-26
- **Verdict**: NEEDS ATTENTION
- **Findings**: 0 critical, 6 warnings, 1 observation

## Verdicts

| Dimension | Verdict |
|-----------|---------|
| Plan Adherence | WARNING |
| Scope Discipline | WARNING |
| Safety & Quality | WARNING |
| Architecture | PASS |
| Pattern Consistency | WARNING |
| Success Criteria | PASS |

## Findings

### F1 — flash_controller: setTimeout nie czyszczony w disconnect()

- **Severity**: ⚠️ WARNING
- **Impact**: 🏃 LOW — szybka decyzja; fix oczywisty
- **Dimension**: Safety & Quality
- **Location**: app/javascript/controllers/flash_controller.js:7
- **Detail**: setTimeout ID jest odrzucane. Na Turbo back-navigation connect() odpala drugi raz, tworząc duplikowany timer. Callback na odłączonym węźle DOM jest bezpieczny ale zbędny.
- **Fix**: Zapisz `this.timer = setTimeout(...)` i dodaj `disconnect() { clearTimeout(this.timer) }`
- **Decision**: FIXED — ec35dac

### F2 — Brak handlera klawisza ESC dla hamburger menu

- **Severity**: ⚠️ WARNING
- **Impact**: 🔎 MEDIUM — realny tradeoff; a11y gap
- **Dimension**: Safety & Quality
- **Location**: app/javascript/controllers/nav_controller.js (brak), _nav.html.erb (brak keydown)
- **Detail**: ARIA APG disclosure menu wymaga ESC → zamknij + focus na trigger. Użytkownicy klawiaturowi nie mogą zamknąć menu.
- **Fix**: Dodaj `data-action="keydown.esc@window->nav#close"` w szablonie; w `close()` dodaj `if (this.hasHamburgerTarget) this.hamburgerTarget.focus()`
- **Decision**: FIXED — ec35dac

### F3 — Hamburger dostępny przez querySelector zamiast Stimulus target

- **Severity**: ⚠️ WARNING
- **Impact**: 🏃 LOW — szybka decyzja; fix oczywisty
- **Dimension**: Pattern Consistency
- **Location**: nav_controller.js:7,20; _nav.html.erb:40
- **Detail**: `this.element.querySelector("[data-nav-hamburger]")` używane zamiast `static targets`. Niespójne z `data-nav-target="menu"`. Wywołanie w `toggle()` bez null-check może rzucić TypeError.
- **Fix**: `static targets = ["hamburger", "menu"]`; zmień `data-nav-hamburger` na `data-nav-target="hamburger"`; zamień querySelector na `this.hamburgerTarget`
- **Decision**: FIXED — ec35dac

### F4 — Brak aria-controls na hamburger button

- **Severity**: ⚠️ WARNING
- **Impact**: 🏃 LOW — szybka decyzja; 2 atrybuty
- **Dimension**: Safety & Quality
- **Location**: app/views/layouts/_nav.html.erb:40-49
- **Detail**: Brak `aria-controls` wskazującego na menu div. Screen readery nie wiedzą który element jest kontrolowany przez ten przycisk.
- **Fix**: Dodaj `id="nav-mobile-menu"` do menu div + `aria-controls="nav-mobile-menu"` do button
- **Decision**: FIXED — ec35dac

### F5 — Flash tag.div: fragility na przyszłe model-error interpolation

- **Severity**: ⚠️ WARNING
- **Impact**: 🔎 MEDIUM — warto zapamiętać; nie blokuje teraz
- **Dimension**: Safety & Quality
- **Location**: app/views/layouts/application.html.erb:31-34
- **Detail**: `tag.div(flash[:alert])` jest safe przy obecnych string-literal flash. Ryzyko pojawi się gdy ktoś ustawi `flash[:alert] = string.html_safe` — wtedy treść nie zostanie escaped.
- **Fix**: Odnotuj jako lesson dla przyszłych contributerów; brak zmian kodu teraz
- **Decision**: FIXED + ACCEPTED-AS-RULE (lessons.md) — ec35dac

### F6 — data-turbo-permanent usunięte vs kontrakt planu

- **Severity**: ⚠️ WARNING
- **Impact**: 🔎 MEDIUM — świadoma dewjacja; udokumentuj
- **Dimension**: Plan Adherence
- **Location**: app/views/layouts/application.html.erb:30
- **Detail**: Plan specyfikował `data-turbo-permanent` na flash container. Usunięto celowo (flash nie wyświetlały się — Turbo zachowywał pusty permanent container). Dewjacja słuszna i potwierdzona manualnie, ale nieudokumentowana.
- **Fix A ⭐ Recommended**: Dodaj addendum w planie Phase 3 wyjaśniające dlaczego turbo-permanent pominięto
  - Strength: Żadnych zmian kodu; plan zostaje historical truth.
  - Tradeoff: Plan lekko rozbieżny z oryginalnym kontraktem.
  - Confidence: HIGH — zachowanie potwierdzone manualnie.
  - Blind spot: None significant.
- **Fix B**: Przywróć data-turbo-permanent i przetestuj wszystkie redirect flows
  - Strength: Spójność z planem.
  - Tradeoff: Wymaga weryfikacji że każda response zawiera #flash-container.
  - Confidence: MEDIUM.
  - Blind spot: Nie testowano wszystkich redirect flows.
- **Decision**: FIXED via Fix A — ec35dac

### F7 — public/icon.svg dodany bez wpisu w planie

- **Severity**: 💬 OBSERVATION
- **Impact**: 🏃 LOW — brak zmian kodu
- **Dimension**: Scope Discipline
- **Location**: public/icon.svg
- **Detail**: User-requested enhancement podczas Phase 2. Statyczny SVG, benign.
- **Fix**: Jednolinijkowa adnotacja w planie Phase 2
- **Decision**: FIXED — ec35dac
