# Synchronizacja aksjomatów z kodem

## Filozofia

Programista pracuje nad aksjomatami, nie nad kodem. Aksjomaty to deklaratywny opis systemu — źródło prawdy. Kod jest pochodną aksjomatów.

Workflow: edytuj aksjomaty → uruchom `/axioms-sync` → kod się aktualizuje.

## Struktura folderów

- Root projektu — aksjomaty systemu (tu programista pracuje): `axioms.md`, `technology.md`, `data-protection.md`, `ui-template.html`, oraz foldery `*-client/` (np. `landing-client/`, `login-client/`, `patient-client/`, `therapist-client/`, `admin-client/`)
- `_generated/` — kod systemu (generowany z aksjomatów). Utwórz jeśli nie istnieje.
- `.axioms-freeze/` — snapshot aksjomatów z ostatniego sync (do diffów)

Twoje zadanie: doprowadzić kod w `_generated/` do zgodności z aksjomatami.

## Format aksjomatów

Plik: `axioms.md`

Struktura pliku:
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
### Nazwa grupy
#### Nazwa aksjomatu
[label1] [label2]
Treść aksjomatu...
```

Składnia aksjomatów:
- Aksjomat to heading 4: `#### Nazwa aksjomatu` (czytelna polska nazwa)
- Labele w nawiasach kwadratowych w linii pod headingiem: `[test] [security]`
- Treść aksjomatu poniżej (do następnego aksjomatu lub sekcji)
- Referencja do innego aksjomatu: `[Nazwa aksjomatu](#anchor)` (standardowy markdown link)
- Namespace ID aksjomatu: `{folder}/{file}.md#{heading-slug}` (np. `landing-client/main.md#sekcja-hero`). Dla plików w rootcie: `axioms.md#cel-systemu`, `data-protection.md#szyfrowanie`

Sekcja "## Słownik":
- Zawiera definicje pojęć domenowych w formacie `**Termin** - opis`
- Pojęcia ze słownika NIE SĄ aksjomatami — nie generuj dla nich zmian, testów ani implementacji
- Słownik służy wyłącznie do rozumienia znaczenia terminów używanych w aksjomatach

Sekcja "## Labele":
- Definicje labeli w formacie `### [nazwa-labela]`
- Każdy label ma opis/instrukcje pod headingiem
- Labele określają wymagane działanie dla aksjomatu (np. pisanie testów, przegląd bezpieczeństwa)

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
# @axiom: axioms.md#skrypt-wdrożeniowy
...kod...
# /@axiom: axioms.md#skrypt-wdrożeniowy
```

CSS:
```css
/* @axiom: landing-client/main.md#sekcja-hero */
...style...
/* /@axiom: landing-client/main.md#sekcja-hero */
```

JS:
```javascript
// @axiom: axioms.md#walidacja-formularza
...kod...
// /@axiom: axioms.md#walidacja-formularza
```

PHP:
```php
// @axiom: axioms.md#endpoint-api
...kod...
// /@axiom: axioms.md#endpoint-api
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

### Krok 0: Freeze i diff

1. Przeczytaj aktualne aksjomaty (krok 1 poniżej).
2. Sprawdź czy istnieje folder `.axioms-freeze/`.
3. **Jeśli `.axioms-freeze/` NIE istnieje** (pierwsze uruchomienie):
   - Traktuj jako pełny sync — wszystkie aksjomaty będą na liście zmian.
4. **Jeśli `.axioms-freeze/` istnieje** i tryb = diff (domyślny):
   - Porównaj pliki aksjomatowe (`.md` w rootcie + foldery `*-client/`) z ich kopiami w `.axioms-freeze/` za pomocą `diff -ru`.
   - Jeśli diff zwraca pusty wynik — brak zmian, zakończ sync z komunikatem "Brak zmian w aksjomatach."
   - Jeśli diff zwraca różnice — sparsuj wynik diffa:
     - Nowe pliki → nowe aksjomaty (dodane).
     - Usunięte pliki → usunięte aksjomaty.
     - Zmienione linie (`+`/`-`) → zidentyfikuj, które aksjomaty (heading 4) zostały zmodyfikowane na podstawie kontekstu diffa.
   - Dalsze kroki (lista zmian, implementacja) dotyczą TYLKO zmienionych aksjomatów.
5. **Jeśli tryb = full** (`--full`):
   - Ignoruj `.axioms-freeze/`, traktuj wszystkie aksjomaty.
6. Zapisz aktualną treść aksjomatów do `.axioms-freeze/`:
   - Skopiuj pliki aksjomatowe (axioms.md, technology.md, data-protection.md, ui-template.html, *-client/) do `.axioms-freeze/`

### Krok 1: Wczytaj aksjomaty

1. Przeczytaj `axioms.md`.
2. Znajdź wszystkie includy — linki w formacie `[Nazwa](./plik.md)`. Przeczytaj te pliki.
   - Traktuj zawartość includowanych plików jako część aksjomatów.
   - **Rekurencyjnie:** jeśli includowany plik sam zawiera linki do innych plików `.md` (ścieżki względne), przeczytaj też te pliki. Powtarzaj aż nie ma nowych linków.
   - NIE skanuj plików w folderze, które nie są osiągalne przez łańcuch linków z `axioms.md`.
3. Sparsuj aksjomaty ze wszystkich wczytanych plików: wyodrębnij nazwy (heading 4), labele (`[...]`), referencje (`[Nazwa](#anchor)`), treść.
4. Sparsuj definicje labeli z sekcji "## Labele".

### Krok 2: Sprawdź spójność aksjomatów

Sprawdź:
- Czy są aksjomaty wykluczające się wzajemnie (sprzeczne wymagania)?
- Czy wszystkie referencje `[Nazwa](#anchor)` wskazują na istniejące aksjomaty?
- Czy są duplikaty nazw aksjomatów?
- Czy wszystkie linki i ścieżki (np. `./ui-template.html`) wskazują na istniejące pliki?

Jeśli znajdziesz problemy — ZATRZYMAJ SIĘ i zgłoś je użytkownikowi. Nie kontynuuj bez rozwiązania sprzeczności.

### Krok 3: Sporządź listę zmian

Jeśli tryb = diff, wypisz najpierw podsumowanie zmian w aksjomatach:
```
## Zmiany w aksjomatach od ostatniego sync
- Dodane: ...
- Usunięte: ...
- Zmodyfikowane: ...
```

Dla każdego aksjomatu w zakresie (diff lub full):
1. Sprawdź czy kod w `_generated/` jest zgodny z aksjomatem.
2. Jeśli nie — zapisz co trzeba zmienić.
3. Uwzględnij labele aksjomatu (definicje w sekcji "## Labele"):
   - `[test]` — dodaj do listy: "napisz test(y) dla aksjomatu"
   - `[e2e]` — dodaj do listy: "napisz test e2e dla aksjomatu"
   - `[security]` — dodaj do listy: "przegląd bezpieczeństwa dla aksjomatu"
   - `[architecture-check]` — dodaj do listy: "weryfikacja architektury dla aksjomatu"
   - `[ux-validate]` — dodaj do listy: "weryfikacja UI dla aksjomatu"

Wypisz pełną listę zmian w formacie:

```
## Lista zmian

### Nazwa aksjomatu — krótki opis
- [ ] Co trzeba zrobić
- [ ] Jakie testy napisać (jeśli [test])
- [ ] Co sprawdzić (jeśli [security], [architecture-check], [ux-validate])
```

Zapisz listę zmian do `.axioms-freeze/sync-result.md` (data, tryb diff/full, podsumowanie zmian, pełna lista do implementacji).

### Krok 3.5: Weryfikacja markerów @axiom

1. Sparsuj wszystkie pliki w `_generated/` (poza `tests/`).
2. Sprawdź parowanie markerów: każdy `@axiom: X` musi mieć `/@axiom: X`.
3. Waliduj nazwy: każda nazwa w markerze musi odpowiadać istniejącemu aksjomatowi.
4. Sprawdź orphaned code: w blokach `{{content}}` nie powinno być kodu poza markerami @axiom.
5. Jeśli są problemy — napraw je przed przejściem do implementacji.

### Krok 4: Implementuj zmiany

Od razu przejdź do implementacji — nie czekaj na potwierdzenie użytkownika.

1. Implementuj zmiany z listy, jedna po drugiej. Cały kod trafia do `_generated/`. Przy tworzeniu/modyfikacji plików — zawsze dodawaj markery `@axiom` wskazujące aksjomat źródłowy.
2. Po każdej zmianie oznacz ją jako zrobioną.
3. Dla aksjomatów z labelem `[test]` — napisz testy ZANIM napiszesz implementację (TDD).
4. Dla aksjomatów z labelem `[e2e]` — napisz test e2e pokrywający cały flow.

### Krok 5: Weryfikacja

Po implementacji wszystkich zmian:
1. Uruchom testy, lintery i inne narzędzia wymagane przez labele.
2. Jeśli coś nie przechodzi — napraw kod tak, aby spełniał aksjomaty. To nadal jest część sync.
3. Powtarzaj aż wszystko przechodzi.
4. Sync-axioms kończy się dopiero gdy kod jest zgodny z aksjomatami I wszystkie labele są spełnione.

Jeśli po zakończeniu sync użytkownik nadal widzi błędy — to sygnał, że specyfikacja jest niekompletna (brakuje aksjomatu lub labela). Ale to już poza zakresem tego sync — wymaga edycji aksjomatów i ponownego uruchomienia.

## Partyjne przetwarzanie

Jeśli liczba aksjomatów do przetworzenia jest duża (>20), podziel pracę na partie:
1. Krok 2 (spójność) — zawsze na całości aksjomatów.
2. Krok 3 (lista zmian) — po grupach (sekcje `###` z `axioms.md` lub per `*-client/` folder).
3. Krok 4 (implementacja) — po jednym aksjomacie na raz.
4. Krok 5 (weryfikacja) — na całości po zakończeniu implementacji.

## Zasady

- Nie zmieniaj aksjomatów. Aksjomaty to źródło prawdy.
- Jeśli aksjomat jest nierealizowalny — zgłoś to, nie implementuj obejścia.
- Jeśli aksjomat oznaczony `[test]` — kod BEZ testu nie jest zgodny z aksjomatem.
- Preferuj małe, atomowe commity: jeden aksjomat = jeden commit.
