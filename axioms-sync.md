# Synchronizacja aksjomatów z kodem

## Filozofia

Programista pracuje nad aksjomatami, nie nad kodem. Aksjomaty to deklaratywny opis systemu — źródło prawdy. Kod jest pochodną aksjomatów.

Workflow: edytuj aksjomaty → uruchom `/axioms-sync` → kod się aktualizuje.

## Struktura folderów

- Root projektu — aksjomaty systemu (tu programista pracuje): `main.md`, `technology.md`, `data-protection.md`, `ui-template.html`, oraz foldery `*-client/` (np. `landing-client/`, `login-client/`, `patient-client/`, `therapist-client/`, `admin-client/`)
- `_generated/` — kod systemu (generowany z aksjomatów). Utwórz jeśli nie istnieje.
- `.axioms/` — folder roboczy sync (tymczasowe pliki, snapshoty). Utwórz jeśli nie istnieje.
  - `.axioms/current/` — kopia aksjomatów z bieżącego uruchomienia (tworzona na starcie sync)
  - `.axioms/freeze/` — snapshot aksjomatów z ostatniego sync (do diffów)

Twoje zadanie: doprowadzić kod w `_generated/` do zgodności z aksjomatami.

## Format aksjomatów

### Plik główny: `main.md`

`main.md` to mapa systemu — zawiera słownik, definicje labeli i linki do plików aksjomatów. Sam NIE zawiera aksjomatów.

Struktura:
```
# Nazwa systemu

## Słownik
- **Termin** - definicja pojęcia...

## Labele
### [test]
Opis/instrukcje dla labela test

### [security]
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
- Definicje labeli w formacie `### [nazwa-labela]`
- Każdy label ma opis/instrukcje pod headingiem
- Labele określają wymagane działanie dla aksjomatu (np. pisanie testów, przegląd bezpieczeństwa)
- Label może definiować pipeline weryfikacyjny: konkretne komendy do uruchomienia, model AI do użycia, narzędzia statyczne
- **Izolacja agentów:** Każdy label w kroku weryfikacji (Krok 6) jest odpalany jako osobny agent z własnym kontekstem. Agent weryfikujący NIE widzi procesu myślowego agenta generującego kod — widzi tylko aksjomat i wygenerowany kod. To zapobiega tautologicznej weryfikacji (ten sam agent pisze kod i "potwierdza" że jest poprawny)

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

Każdy fragment kodu w `_generated/` musi wskazywać aksjomat, z którego wynika, za pomocą markerów `@axiom`.

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
5. Pliki w `_generated/tests/` nie wymagają markerów.
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
2. **Snapshot bieżących aksjomatów:** Skopiuj pliki aksjomatowe (`.md` w rootcie, `ui-template.html`, foldery `*-client/`) do `.axioms/current/` (wyczyść folder przed kopiowaniem). To jest snapshot aksjomatów z tego uruchomienia — dalsze kroki pracują na plikach z `.axioms/current/`.
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

1. Przeczytaj `main.md`.
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

**A) Lista zmian do implementacji (dla Kroku 5):**

Dla każdego aksjomatu w zakresie (diff lub full):
1. Sprawdź czy kod w `_generated/` jest zgodny z aksjomatem.
2. Jeśli nie — zapisz co trzeba zmienić.
3. Uwzględnij labele aksjomatu (definicje w sekcji "## Labele"):
   - `[test]` — dodaj do listy: "napisz test(y) dla aksjomatu"
   - `[e2e]` — dodaj do listy: "napisz test e2e dla aksjomatu"
   - `[security]` — dodaj do listy: "przegląd bezpieczeństwa dla aksjomatu"
   - `[architecture-check]` — dodaj do listy: "weryfikacja architektury dla aksjomatu"
   - `[ux-validate]` — dodaj do listy: "weryfikacja UI dla aksjomatu"

Wypisz listę zmian w formacie:

```
## Lista zmian

### Nazwa aksjomatu — krótki opis
- [ ] Co trzeba zrobić
- [ ] Jakie testy napisać (jeśli [test])
- [ ] Co sprawdzić (jeśli [security], [architecture-check], [ux-validate])
```

**B) Checklista weryfikacyjna (dla Kroku 6):**

Na podstawie labeli znalezionych w aksjomatach oraz infrastruktury testowej projektu, sporządź listę konkretnych komend do uruchomienia po implementacji. Sprawdź jakie test runnery istnieją w projekcie (np. `Makefile`, `package.json`, `playwright.config.*`, `dune` test stanzas) i zapisz komendy.

Wypisz w formacie:
```
## Checklista weryfikacyjna
- [ ] `komenda budowania` (np. dune build)
- [ ] `komenda testów unit/integracyjnych` (np. dune exec test/smock_test.exe)
- [ ] `komenda testów e2e` (np. npx playwright test) — jeśli są labele [e2e]
- [ ] przegląd bezpieczeństwa — jeśli są labele [security]
- [ ] weryfikacja architektury — jeśli są labele [architecture-check]
```

Zapisz obie listy do `.axioms/sync-result.md` (data, tryb diff/full, podsumowanie zmian, lista zmian, checklista weryfikacyjna).

### Krok 4: Weryfikacja markerów @axiom

1. Sparsuj wszystkie pliki w `_generated/` (poza `tests/`).
2. Sprawdź parowanie markerów: każdy `@axiom: X` musi mieć `/@axiom: X`.
3. Waliduj nazwy: każda nazwa w markerze musi odpowiadać istniejącemu aksjomatowi.
4. Sprawdź orphaned code: w blokach `{{content}}` nie powinno być kodu poza markerami @axiom.
5. Jeśli są problemy — napraw je przed przejściem do implementacji.

### Krok 5: Implementuj zmiany

Od razu przejdź do implementacji — nie czekaj na potwierdzenie użytkownika.

1. Implementuj zmiany z listy zmian (Krok 3A), jedna po drugiej. Cały kod trafia do `_generated/`. Przy tworzeniu/modyfikacji plików — zawsze dodawaj markery `@axiom` wskazujące aksjomat źródłowy.
2. Po każdej zmianie oznacz ją jako zrobioną.
3. Dla aksjomatów z labelem `[test]` — napisz testy ZANIM napiszesz implementację (TDD).
4. Dla aksjomatów z labelem `[e2e]` — napisz test e2e pokrywający cały flow.

### Krok 6: Weryfikacja

Przejdź przez checklistę weryfikacyjną z Kroku 3B. Wykonaj każdą pozycję po kolei:
1. Uruchom każdą komendę z checklisty. Nie pomijaj żadnej.
2. **Każdy label odpalaj jako osobnego agenta** z czystym kontekstem. Agent weryfikujący otrzymuje: aksjomat, wygenerowany kod i instrukcje labela. NIE otrzymuje historii generowania ani procesu myślowego agenta implementującego. Jeśli label definiuje model — użyj tego modelu.
3. Jeśli coś nie przechodzi — napraw kod tak, aby spełniał aksjomaty. To nadal jest część sync.
4. Powtarzaj aż wszystko przechodzi.
5. Sync-axioms kończy się dopiero gdy kod jest zgodny z aksjomatami I cała checklista weryfikacyjna jest zaliczona.

Jeśli po zakończeniu sync użytkownik nadal widzi błędy — to sygnał, że specyfikacja jest niekompletna (brakuje aksjomatu lub labela). Ale to już poza zakresem tego sync — wymaga edycji aksjomatów i ponownego uruchomienia.

## Partyjne przetwarzanie

Jeśli liczba aksjomatów do przetworzenia jest duża (>20), podziel pracę na partie:
1. Krok 2 (spójność) — zawsze na całości aksjomatów.
2. Krok 3 (lista zmian i checklista) — po grupach (per folder/domena).
3. Krok 5 (implementacja) — po jednym aksjomacie na raz.
4. Krok 6 (weryfikacja) — na całości po zakończeniu implementacji.

## Zasady

- Nie zmieniaj aksjomatów. Aksjomaty to źródło prawdy.
- Jeśli aksjomat jest nierealizowalny — zgłoś to, nie implementuj obejścia.
- Jeśli aksjomat oznaczony `[test]` — kod BEZ testu nie jest zgodny z aksjomatem.
- Preferuj małe, atomowe commity: jeden aksjomat = jeden commit.
