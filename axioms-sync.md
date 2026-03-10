# Synchronizacja aksjomatów z kodem

## Filozofia

Programista pracuje nad aksjomatami, nie nad kodem. Aksjomaty to deklaratywny opis systemu — źródło prawdy. Kod jest pochodną aksjomatów.

Workflow: edytuj aksjomaty → uruchom `/axioms-sync` → kod się aktualizuje.

## Struktura folderów

- `axioms/` — aksjomaty systemu (tu programista pracuje): `main.md` (entry point), `technology.md`, `data-protection.md`, `ui-template.html`, oraz foldery `*-client/` (np. `landing-client/`, `login-client/`, `patient-client/`, `therapist-client/`, `admin-client/`)
- `code/` — kod systemu (generowany z aksjomatów). Utwórz jeśli nie istnieje.
- `data/` — dane runtime (bazy danych, uploady itp.). Nie zarządzane przez sync.
- `.axioms/` — folder roboczy sync (tymczasowe pliki, snapshoty). Utwórz jeśli nie istnieje.
  - `.axioms/current/` — kopia aksjomatów z bieżącego uruchomienia (tworzona na starcie sync)
  - `.axioms/freeze/` — snapshot aksjomatów z ostatniego sync (do diffów)

Twoje zadanie: doprowadzić kod w `code/` do zgodności z aksjomatami.

## Format aksjomatów

### Plik główny: `axioms/main.md`

`axioms/main.md` to mapa systemu — zawiera słownik, definicje labeli i linki do plików aksjomatów. Sam NIE zawiera aksjomatów.

Struktura:
```
# Nazwa systemu

## Słownik
- **Termin** - definicja pojęcia...

## Labele
### [test] @implementation @validation
Opis/instrukcje dla labela test

### [scenario] @validation
Scenariusze behawioralne. Walidowane po implementacji.

### [security] @validation
Opis/instrukcje dla labela security

## Aksjomaty
[lint]
- [Ochrona danych](./data-protection.md)
- [Booking](./patient-client/booking.md)
```

Sekcja "## Słownik":
- Zawiera definicje pojęć domenowych w formacie `**Termin** - opis`
- Pojęcia ze słownika NIE SĄ aksjomatami — nie generuj dla nich zmian, testów ani implementacji
- Słownik służy wyłącznie do rozumienia znaczenia terminów używanych w aksjomatach

Sekcja "## Labele":
- Definicje labeli w formacie `### [nazwa-labela] @fazy...`
- Każdy label ma opis/instrukcje pod headingiem
- Labele określają wymagane działanie dla aksjomatu (np. pisanie testów, przegląd bezpieczeństwa)
- Label może definiować pipeline weryfikacyjny: konkretne komendy do uruchomienia, model AI do użycia, narzędzia statyczne
- **Fazy labela:** Po nazwie labela w headingu podaje się jedną lub więcej faz: `@implementation`, `@validation`, `@satisfaction`. Fazy określają *kiedy* uruchomić agenta dla tego labela:
  - `@implementation` — bloki z tym labelem trafiają do agenta implementującego (Krok 5)
  - `@validation` — bloki trafiają do agenta walidującego (Krok 6)
  - `@satisfaction(próg)` — bloki trafiają do agenta-sędziego (Krok 7). Agent ocenia doświadczenie w skali 0.0–1.0. Próg to minimalny wymagany score, np. `@satisfaction(0.8)`. Domyślnie `@satisfaction` = `@satisfaction(0.7)`.
  - Label z oboma fazami (`@implementation @validation`) — widoczny dla obu agentów (np. `[test]` — TDD w implementacji + weryfikacja)
  - Label tylko z `@validation` — ukryty przed agentem implementującym (holdout). Agent buduje software bez wiedzy o tych kryteriach walidacyjnych. Działa jak holdout set w ML.
  - Label tylko z `@satisfaction` — scenariusz nie generuje kodu ani testów. Jest promptem dla AI-sędziego, który wchodzi w interakcję z działającą aplikacją i ocenia ją subiektywnie. To jest walidacja tego, czego nie da się sprawdzić deterministycznym testem: UX, czytelność, intuicyjność, ogólna jakość.
  - Label bez żadnej fazy — **błąd**. Sync zatrzymuje się w Kroku 2 (spójność) z komunikatem: "Label `[x]` nie ma zdefiniowanej fazy (@implementation / @validation / @satisfaction)."
- **Znaczniki kontekstu (`+`):** Po fazach można podać znaczniki kontekstu, które określają *co* agent dostaje. Każdy agent zawsze otrzymuje swój aksjomat (ten z którego wynika label). Dostępne znaczniki:
  - `+code` — dostęp do kodu źródłowego w `code/`
  - `+axioms` — dostęp do wszystkich aksjomatów systemu (nie tylko swojego)
  - `+browser` — dostęp do przeglądarki / działającej aplikacji (browser automation)
  - `+api` — dostęp do endpointów HTTP (curl, requesty)
  - Brak znaczników = agent dostaje tylko swój aksjomat i instrukcje labela
- **Izolacja agentów:** Każdy label w fazach weryfikacji i satisfaction uruchamia **osobnego agenta** z kontekstem określonym przez znaczniki `+`. Proces główny (Kroki 0–4) pełni rolę orkiestratora — czyta aksjomaty, buduje plan, filtruje kontekst i deleguje pracę. Agent implementujący NIE widzi bloków z labeli `@validation`-only ani `@satisfaction`-only. Agent weryfikujący NIE widzi procesu myślowego agenta implementującego. Znaczniki `+` kontrolują co każdy agent widzi — np. agent `[ux-validate]` z `+browser` bez `+code` nie może oszukać sprawdzając HTML zamiast oceniać UI.

### Pliki aksjomatów

**Jeden plik = jeden aksjomat.** Każdy aksjomat to plik Markdown opisujący jedno spójne zagadnienie: stronę, funkcjonalność, stack technologiczny, politykę ochrony danych.

Struktura pliku aksjomatu:
```
# Nazwa aksjomatu
[label1]

Treść aksjomatu — narracyjny opis zagadnienia.

## Sekcja
[label2]

Dalsza treść...
```

Składnia:
- Heading `#` to nazwa aksjomatu
- Heading `##` to sekcje wewnątrz aksjomatu
- Labele w nawiasach kwadratowych w linii pod headingiem: `[test] [security]`
- Treść opisowa poniżej (narracja, nie checklist)
- Referencja do innego aksjomatu: `[Nazwa](./plik.md)` lub `[Sekcja](./plik.md#sekcja)` (standardowy markdown link)
- Namespace ID aksjomatu: `{folder}/{plik}.md` (np. `patient-client/booking.md`). Dla sekcji: `{folder}/{plik}.md#{heading-slug}` (np. `data-protection.md#technical-security`)

### Kaskada labeli

Labele dziedziczą w dół (jak CSS):
- Label pod `## Aksjomaty` w `main.md` → dotyczy WSZYSTKICH aksjomatów (globalny)
- Label na `#` (nagłówek pliku aksjomatu) → dotyczy całego pliku
- Label na `##` (sekcja) → dotyczy tej sekcji
- Każdy poziom dziedziczy labele z poziomu wyższego

Przykład — plik `data-protection.md`:
```markdown
# Data protection
[rodo]

Patients can export their data in a structured format.

## Technical security
[pentest] [test]

Passwords are hashed with bcrypt or argon2.

## Privacy policy
[ux-validate]

The system displays privacy policy before registration.
```

W tym przykładzie: cały plik ma `[rodo]`. Sekcja "Technical security" ma `[rodo] [pentest] [test]` (dziedziczone + własne). Sekcja "Privacy policy" ma `[rodo] [ux-validate]`. Jeśli w `main.md` pod `## Aksjomaty` jest `[lint]`, to wszystkie sekcje mają dodatkowo `[lint]`.

## Markery @axiom w kodzie

Każdy fragment kodu w `code/` musi wskazywać aksjomat, z którego wynika, za pomocą markerów `@axiom`.

### Format markerów

Markery używają namespace ID aksjomatu (ścieżka pliku + anchor z headingu):

HTML:
```html
<!-- @axiom: landing-client/main.md#sekcja-hero -->
...kod wynikający z aksjomatu...
<!-- /@axiom: landing-client/main.md#sekcja-hero -->
```

Bash:
```bash
# @axiom: technology.md#deploy-script
...kod...
# /@axiom: technology.md#deploy-script
```

CSS:
```css
/* @axiom: landing-client/main.md#sekcja-hero */
...style...
/* /@axiom: landing-client/main.md#sekcja-hero */
```

JS:
```javascript
// @axiom: login-client/registration.md#form-validation
...kod...
// /@axiom: login-client/registration.md#form-validation
```

PHP:
```php
// @axiom: api.md#endpoint-api
...kod...
// /@axiom: api.md#endpoint-api
```

### Zasady markerów

1. Markery mogą być zagnieżdżone — np. formularz rejestracji (`@axiom: login-client/registration.md#formularz-rejestracji-pacjenta`) może zawierać wewnątrz `@axiom: data-protection.md#zgoda-przetwarzanie` dla checkboxa.
2. Każdy opening marker (`@axiom: X`) musi mieć matching closing marker (`/@axiom: X`).
3. Nazwy w markerach to namespace ID (ścieżka pliku + anchor), muszą odpowiadać istniejącym aksjomatom.
4. W blokach `{{content}}` nie powinno być kodu poza markerami @axiom (orphaned code).
5. Pliki w `code/tests/` nie wymagają markerów.
6. Layout files (`layout-*.html`) mają markery na nawigacji i strukturze, nie na `{{yield content}}`.

### Aksjomaty deklaratywne (bez markerów w kodzie)

Niektóre aksjomaty opisują zasady, architekturę lub wykluczenia — nie mają bezpośredniego odzwierciedlenia w kodzie i NIE wymagają markerów `@axiom`. Takie aksjomaty powinny być wymienione w pliku aksjomatów projektu.

## Tryby uruchomienia

### Tryb domyślny (diff)
Domyślnie axioms-sync działa w trybie diff — synchronizuje tylko aksjomaty, które zmieniły się od ostatniego uruchomienia.

### Tryb pełny
Aby wymusić pełną synchronizację (wszystkie aksjomaty, nie tylko diff), użytkownik musi przekazać argument `--full` lub powiedzieć "pełny sync" / "full sync".

## Procedura

Wykonaj poniższe kroki SEKWENCYJNIE. Nie przechodź do następnego kroku bez zakończenia poprzedniego.

### Krok 0: Snapshot i diff

1. Utwórz folder `.axioms/` jeśli nie istnieje.
2. **Snapshot bieżących aksjomatów:** Skopiuj pliki aksjomatowe z `axioms/` (`.md`, `ui-template.html`, foldery `*-client/`) do `.axioms/current/` (wyczyść folder przed kopiowaniem). To jest snapshot aksjomatów z tego uruchomienia — dalsze kroki pracują na plikach z `.axioms/current/`.
3. Sprawdź czy istnieje folder `.axioms/freeze/`.
4. **Jeśli `.axioms/freeze/` NIE istnieje** (pierwsze uruchomienie):
   - Traktuj jako pełny sync — wszystkie aksjomaty będą na liście zmian.
5. **Jeśli `.axioms/freeze/` istnieje** i tryb = diff (domyślny):
   - Porównaj `.axioms/current/` z `.axioms/freeze/` za pomocą `diff -ru`.
   - Jeśli diff zwraca pusty wynik — brak zmian, zakończ sync z komunikatem "Brak zmian w aksjomatach."
   - Jeśli diff zwraca różnice — sparsuj wynik diffa:
     - Nowe pliki → nowe aksjomaty (dodane).
     - Usunięte pliki → usunięte aksjomaty.
     - Zmienione linie (`+`/`-`) → zidentyfikuj, które aksjomaty (pliki/sekcje) zostały zmodyfikowane na podstawie kontekstu diffa.
   - Dalsze kroki (lista zmian, implementacja) dotyczą TYLKO zmienionych aksjomatów.
6. **Jeśli tryb = full** (`--full`):
   - Ignoruj `.axioms/freeze/`, traktuj wszystkie aksjomaty.
7. Zapisz snapshot do freeze: Skopiuj zawartość `.axioms/current/` do `.axioms/freeze/` (nadpisz).

### Krok 1: Wczytaj aksjomaty

1. Przeczytaj `axioms/main.md`.
2. Znajdź wszystkie includy — linki w formacie `[Nazwa](./plik.md)`. Przeczytaj te pliki.
   - Każdy includowany plik to osobny aksjomat.
   - **Rekurencyjnie:** jeśli includowany plik sam zawiera linki do innych plików `.md` (ścieżki względne), przeczytaj też te pliki. Powtarzaj aż nie ma nowych linków.
   - NIE skanuj plików w folderze, które nie są osiągalne przez łańcuch linków z `main.md`.
3. Sparsuj aksjomaty ze wszystkich wczytanych plików: wyodrębnij nazwy (heading `#`), sekcje (heading `##`), labele (`[...]`), referencje, treść. Uwzględnij kaskadę labeli (globalny z `## Aksjomaty`, plik `#`, sekcja `##`).
4. Sparsuj definicje labeli z sekcji "## Labele".

### Krok 2: Sprawdź spójność aksjomatów

Sprawdź:
- Czy są aksjomaty wykluczające się wzajemnie (sprzeczne wymagania)?
- Czy wszystkie referencje `[Nazwa](#anchor)` wskazują na istniejące aksjomaty?
- Czy są duplikaty nazw aksjomatów?
- Czy wszystkie linki i ścieżki (np. `./ui-template.html`) wskazują na istniejące pliki?

Jeśli znajdziesz problemy — ZATRZYMAJ SIĘ i zgłoś je użytkownikowi. Nie kontynuuj bez rozwiązania sprzeczności.

### Krok 3: Sporządź listę zmian i checklistę weryfikacyjną

Jeśli tryb = diff, wypisz najpierw podsumowanie zmian w aksjomatach:
```
## Zmiany w aksjomatach od ostatniego sync
- Dodane: ...
- Usunięte: ...
- Zmodyfikowane: ...
```

**A) Kontekst implementacyjny (dla Kroku 5):**

Dla każdego aksjomatu w zakresie (diff lub full):
1. Sprawdź czy kod w `code/` jest zgodny z aksjomatem.
2. Jeśli nie — zapisz co trzeba zmienić.
3. **Filtruj po fazach:** Z treści aksjomatów usuń bloki oznaczone labelami, które mają tylko `@validation` lub tylko `@satisfaction` (bez `@implementation`). Agent implementujący nie może ich widzieć.
4. Uwzględnij labele `@implementation` aksjomatu i dodaj odpowiednie pozycje do listy zmian (np. "napisz testy" dla `[test]`, "napisz test e2e" dla `[e2e]`).

Wypisz listę zmian w formacie:

```
## Lista zmian (implementacja)

### Nazwa aksjomatu — krótki opis
- [ ] Co trzeba zrobić
- [ ] Jakie testy napisać (jeśli [test])
```

**B) Kontekst walidacyjny (dla Kroku 6):**

Na podstawie labeli znalezionych w aksjomatach oraz infrastruktury testowej projektu, sporządź dwie listy:

1. **Komendy do uruchomienia** — sprawdź jakie test runnery istnieją w projekcie (np. `Makefile`, `package.json`, `playwright.config.*`, `dune` test stanzas) i zapisz komendy.
2. **Scenariusze holdout** — zbierz bloki aksjomatów oznaczone labelami `@validation`-only (bez `@implementation`). Każdy taki scenariusz to kryterium walidacyjne, które agent walidujący sprawdza przeciwko działającej aplikacji/kodowi, **bez dostępu do kodu źródłowego implementacji**.

Wypisz w formacie:
```
## Checklista weryfikacyjna
- [ ] `komenda budowania` (np. dune build)
- [ ] `komenda testów unit/integracyjnych` (np. dune exec test/smock_test.exe)
- [ ] `komenda testów e2e` (np. npx playwright test) — jeśli są labele [e2e]
- [ ] przegląd bezpieczeństwa — jeśli są labele [security]

## Scenariusze holdout
- [ ] Scenariusz X (z aksjomatu Y)
- [ ] Scenariusz Z (z aksjomatu W)
```

**C) Kontekst satisfaction (dla Kroku 7):**

Zbierz bloki aksjomatów oznaczone labelami `@satisfaction`. Każdy taki blok to prompt dla AI-sędziego — opis scenariusza do wykonania i oceny na działającej aplikacji. Scenariusze `@satisfaction` NIE generują kodu ani testów.

Dla każdego scenariusza odczytaj:
1. **Prompt** — treść aksjomatu (opis co sprawdzić, jak ocenić)
2. **Próg** — z `@satisfaction(próg)` w definicji labela (domyślnie 0.7)
3. **Kontekst** — znaczniki `+` z definicji labela (np. `+browser` = browser automation)

Wypisz w formacie:
```
## Scenariusze satisfaction
- [ ] Scenariusz X (z aksjomatu Y) — próg: 0.8
- [ ] Scenariusz Z (z aksjomatu W) — próg: 0.7
```

Zapisz obie listy do `.axioms/sync-result.md` (data, tryb diff/full, podsumowanie zmian, kontekst implementacyjny, kontekst walidacyjny).

### Krok 4: Weryfikacja markerów @axiom

1. Sparsuj wszystkie pliki w `code/` (poza `tests/`).
2. Sprawdź parowanie markerów: każdy `@axiom: X` musi mieć `/@axiom: X`.
3. Waliduj nazwy: każda nazwa w markerze musi odpowiadać istniejącemu aksjomatowi.
4. Sprawdź orphaned code: w blokach `{{content}}` nie powinno być kodu poza markerami @axiom.
5. Jeśli są problemy — napraw je przed przejściem do implementacji.

### Krok 5: Implementacja (agent implementujący)

Deleguj implementację do **osobnego agenta**. Od razu, nie czekaj na potwierdzenie użytkownika.

Agent implementujący otrzymuje:
- Kontekst implementacyjny z Kroku 3A (lista zmian + przefiltrowane aksjomaty **bez bloków `@validation`-only**)
- Dostęp do `code/` i infrastruktury projektu
- Definicje labeli `@implementation` (np. `[test]`, `[e2e]`)

Agent implementujący NIE otrzymuje:
- Bloków aksjomatów oznaczonych labelami `@validation`-only (bez `@implementation`)
- Kontekstu walidacyjnego z Kroku 3B

Zadanie agenta:
1. Implementuj zmiany z listy zmian, jedna po drugiej. Cały kod trafia do `code/`. Przy tworzeniu/modyfikacji plików — zawsze dodawaj markery `@axiom` wskazujące aksjomat źródłowy.
2. Po każdej zmianie oznacz ją jako zrobioną.
3. Dla aksjomatów z labelem `[test]` — napisz testy ZANIM napiszesz implementację (TDD).
4. Dla aksjomatów z labelem `[e2e]` — napisz test e2e pokrywający cały flow.

### Krok 6: Weryfikacja (agent walidujący)

Deleguj weryfikację do **osobnego agenta** (lub osobnych agentów per label). Wykonaj po zakończeniu Kroku 5.

**A) Weryfikacja standardowa:**
1. Uruchom każdą komendę z checklisty weryfikacyjnej (Krok 3B). Nie pomijaj żadnej.
2. **Każdy label odpalaj jako osobnego agenta** z czystym kontekstem. Agent otrzymuje: swój aksjomat i instrukcje labela + zasoby określone przez znaczniki `+` (np. `+code` = kod źródłowy, `+browser` = przeglądarka, `+api` = endpointy HTTP, `+axioms` = wszystkie aksjomaty). NIE otrzymuje historii generowania ani procesu myślowego agenta implementującego. Jeśli label definiuje model — użyj tego modelu.

**B) Weryfikacja `@validation`-only (holdout):**
Dla każdego scenariusza `@validation`-only z Kroku 3B:
1. Agent walidujący otrzymuje: treść scenariusza + zasoby wg znaczników `+` z definicji labela.
2. Jeśli label **nie ma** `+code` — agent NIE otrzymuje kodu źródłowego, ocenia wyłącznie zachowanie systemu z zewnątrz.
3. Jeśli label **ma** `+code` (np. `[architecture-check]`) — agent otrzymuje kod, bo weryfikacja dotyczy struktury kodu, nie zachowania.

**C) Naprawianie błędów:**
1. Jeśli coś nie przechodzi (A lub B) — deleguj naprawę do agenta implementującego (z tym samym przefiltrowanym kontekstem + informacją o błędzie, ale nadal **bez bloków `@validation`-only**).
2. Powtarzaj cykl implementacja → weryfikacja aż wszystko przechodzi.
3. Sync kończy się dopiero gdy kod jest zgodny z aksjomatami I cała checklista weryfikacyjna (włącznie z holdout) jest zaliczona.

Jeśli po zakończeniu sync użytkownik nadal widzi błędy — to sygnał, że specyfikacja jest niekompletna (brakuje aksjomatu lub labela). Ale to już poza zakresem tego sync — wymaga edycji aksjomatów i ponownego uruchomienia.

### Krok 7: Satisfaction review (agent-sędzia)

Wykonaj po zakończeniu Kroków 5–6 (implementacja i walidacja muszą przejść). Ten krok wymaga działającej aplikacji.

Jeśli nie ma labeli `@satisfaction` — pomiń ten krok.

Dla każdego scenariusza `@satisfaction` z Kroku 3C:

1. **Deleguj do osobnego agenta-sędziego.** Agent otrzymuje:
   - Treść scenariusza (prompt z aksjomatu)
   - Zasoby określone przez znaczniki `+` z definicji labela (np. `+browser` = browser automation, `+api` = HTTP requesty)
2. **Agent NIE otrzymuje** (chyba że znacznik `+` jawnie to daje):
   - Kodu źródłowego (brak `+code`)
   - Procesu myślowego agentów implementującego i walidującego
   - Treści aksjomatów spoza scenariusza (brak `+axioms`)
3. **Agent wykonuje scenariusz** — wchodzi w interakcję z aplikacją jak użytkownik (klika, nawiguje, sprawdza UI) i ocenia doświadczenie.
4. **Agent zwraca:**
   - Score: 0.0–1.0
   - Uzasadnienie: co działa, co nie, co wymaga poprawy
   - Opcjonalnie: screenshoty, nagrania
5. **Porównaj score z progiem.** Jeśli score < próg:
   - Przekaż uzasadnienie agentowi implementującemu (bez treści scenariusza `@satisfaction` — agent nadal nie widzi promptu sędziego).
   - Agent implementujący poprawia na podstawie opisu problemu.
   - Powtórz cykl: implementacja → walidacja → satisfaction review.
6. **Sync kończy się** dopiero gdy wszystkie scenariusze satisfaction osiągną wymagany próg (lub orkiestrator zgłosi brak postępu po N iteracjach).

Wynik satisfaction review zapisz do `.axioms/sync-result.md`:
```
## Satisfaction review
- Scenariusz X (aksjomat Y): 0.85/1.0 ✓ (próg: 0.7)
  Uzasadnienie: ...
- Scenariusz Z (aksjomat W): 0.55/1.0 ✗ (próg: 0.8)
  Uzasadnienie: ...
```

## Partyjne przetwarzanie

Jeśli liczba aksjomatów do przetworzenia jest duża (>20), podziel pracę na partie:
1. Krok 2 (spójność) — zawsze na całości aksjomatów.
2. Krok 3 (plan + filtrowanie) — po grupach (per folder/domena).
3. Krok 5 (implementacja) — deleguj agentowi po jednym aksjomacie na raz.
4. Krok 6 (weryfikacja) — deleguj agentowi/agentom na całości po zakończeniu implementacji.
5. Krok 7 (satisfaction) — deleguj agentowi-sędziemu po zakończeniu weryfikacji.

## Zasady

- Nie zmieniaj aksjomatów. Aksjomaty to źródło prawdy.
- Jeśli aksjomat jest nierealizowalny — zgłoś to, nie implementuj obejścia.
- Jeśli aksjomat oznaczony `[test]` — kod BEZ testu nie jest zgodny z aksjomatem.
- Preferuj małe, atomowe commity: jeden aksjomat = jeden commit.
