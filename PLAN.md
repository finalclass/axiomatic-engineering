# Plan: Moduł Konfiguracji z Hierarchicznym Ładowaniem

## Cel

Stworzenie modułu `Config` w `lib/config/`, który ładuje konfigurację z 4 źródeł w kolejności priorytetu (od najniższego do najwyższego):

1. `~/.config/axioms-sync.toml` — domyślne ustawienia użytkownika (globalne)
2. `.axioms/axioms-sync.toml` — konfiguracja projektowa (w katalogu projektu, gdzie wywoływana jest komenda)
3. Argumenty wywołania CLI — `--api-url https://...`
4. Zmienne środowiskowe z prefixem `AS_` — `AS_API_URL=https://...`

**Uwaga**: `axioms-sync` to komenda CLI uruchamiana w projektach. Katalog projektu wyznaczany przez argument pozycyjny lub `project_path` w konfiguracji.

---

## Struktura modułu

```
lib/config/
├── config.ml      # Re-eksport + load() + typy
├── sources.ml     # Odczyt z poszczególnych źródeł
├── transform.ml   # Transformacje: CLI→TOML, ENV→TOML
└── merge.ml       # Hierarchiczne scalanie
```

---

## 0. Zmienne konfiguracyjne i domyślne wartości

### Zasada domyślnych wartości

**Hierarchia priorytetów (od najniższego do najwyższego):**

1. Wartości domyślne w kodzie (`Types.default_config`)
2. Global TOML (`~/.config/axioms-sync.toml`)
3. Projekt TOML (`.axioms/axioms-sync.toml`)
4. Argumenty CLI
5. Zmienne środowiskowe (`AS_*`)

**Oznacza to:** jeśli użytkownik uruchomi `axioms-sync` bez żadnych argumentów, bez plików konfiguracyjnych i bez zmiennych środowiskowych, program użyje wartości domyślnych z kodu. Użytkownik może wywołać polecenie bez podawania jakichkolwiek argumentów i domyślne wartości będą sensownie dobrane.

### Lista wszystkich zmiennych konfiguracyjnych

#### Typ `Types.config` (core config)

| Zmienna        | Typ                 | Domyślna wartość | CLI flag              | ENV var          |
|----------------|---------------------|------------------|-----------------------|------------------|
| `project_path` | string              | `"."`            | argument pozycyjny    | -                |
| `mode`         | `Diff \| Full`      | `Diff`           | `--full`              | -                |
| `planner`      | string              | `"opus4.6"`      | `--planner MODEL`     | `AS_PLANNER`     |
| `implementer`  | string              | `"opus4.6"`      | `--implementer MODEL` | `AS_IMPLEMENTER` |
| `smart`        | string              | `"opus4.6"`      | `--smart MODEL`       | `AS_SMART`       |
| `balanced`     | string              | `"sonnet4.6"`    | `--balanced MODEL`    | `AS_BALANCED`    |
| `fast`         | string              | `"haiku4.5"`     | `--fast MODEL`        | `AS_FAST`        |
| `vision`       | string              | `"llama-vision"` | `--vision MODEL`      | `AS_VISION`      |
| `preprompt`    | string              | `""`             | `--preprompt TEXT`    | `AS_PREPROMPT`   |
| `max_cycles`   | int                 | `3`              | `--max-cycles N`      | `AS_MAX_CYCLES`  |
| `no_semantic`  | bool                | `false`          | `--no-semantic`       | `AS_NO_SEMANTIC` |
| `axiom`        | string option       | `None`           | `--axiom ID`          | `AS_AXIOM`       |
| `timings`      | bool                | `false`          | `--timings`           | `AS_TIMINGS`     |
| `provider`     | `Cli \| OpenRouter` | `Cli`            | `--provider MODE`     | `AS_PROVIDER`    |

#### Typ AI provider config (z `lib/config/config.ml`)

| Zmienna           | Typ                  | Domyślna wartość                            | ENV var (stare)        | ENV var (nowe)      |
|-------------------|----------------------|---------------------------------------------|------------------------|---------------------|
| `provider`        | ai_provider          | `Cli` (lub `OpenRouter` jeśli jest api_key) | -                      | `AS_PROVIDER`       |
| `api_key`         | string option        | `None`                                      | `OPENROUTER_API_KEY`   | `AS_API_KEY`        |
| `model_overrides` | (string*string) list | `[]`                                        | -                      | -                   |
| `search_api_key`  | string option        | `None`                                      | `BRAVE_SEARCH_API_KEY` | `AS_SEARCH_API_KEY` |

### Flagi CLI (bez wartości)

| Flaga               | Efekt                               | ENV equivalent        |
|---------------------|-------------------------------------|-----------------------|
| `--quiet` / `-q`    | `quiet = true`                      | `AS_QUIET=true`       |
| `--progress` / `-p` | `quiet = true; progress = true`     | -                     |
| `--full`            | `mode = Full`                       | -                     |
| `--timings`         | `timings = true`                    | `AS_TIMINGS=true`     |
| `--no-semantic`     | `no_semantic = true`                | `AS_NO_SEMANTIC=true` |
| `--models`          | (flag do wyświetlenia listy modeli) | -                     |

---

## 1. Typy konfiguracji (`config.ml`)

```ocaml
type t = {
  provider: Types.ai_provider;
  api_key: string option;
  model_overrides: (string * string) list;
  search_api_key: string option;
  (* ... inne pola ... *)
}

(* Źródło pochodzenia dla debugowania/opcache *)
type source = 
  | GlobalToml 
  | ProjectToml 
  | CliArg 
  | EnvVar

(* Mapowanie klucz → (wartość, źródło) dla debugowania *)
type resolved = (string * string * source) list
```

---

## 2. Źródła konfiguracji (`sources.ml`)

### 2.1 Global TOML (`~/.config/axioms-sync.toml`)

```ocaml
val load_global : unit -> Well.Toml.types * string (* path *)
```

- Ścieżka: `~/.config/axioms-sync.toml`
- Jeśli plik nie istnieje → pusta mapa TOML
- Błędy parsowania → loguj ostrzeżenie, zwracaj pustą mapę

### 2.2 Projekt TOML (`<project>/.axioms/axioms-sync.toml`)

```ocaml
val load_project : string (* project_path *) -> Well.Toml.types * string option (* path *)
```

- Ścieżka: `<project_path>/.axioms/axioms-sync.toml`
- Plik opcjonalny — jeśli nie istnieje, nie błądź
- Można wykryć przez sprawdzenie czy to projekt `axioms-sync`

### 2.3 CLI Args

```ocaml
val parse_cli_args : string list -> Well.Toml.types
```

- Pobiera `Sys.argv` lub przekazaną listę
- Transformuje `--api-url value` → `api_url = "value"` (myślniki → podkreślenia)
- Wartości bez argumentu (flagi): `--verbose` → `verbose = true`
- Nieznane argumenty → pomijane (lub błąd, do dyskusji)

### 2.4 Zmienne środowiskowe

```ocaml
val load_env : unit -> Well.Toml.types
```

- Filtruje env vars z prefixem `AS_`
- `AS_API_URL=https://...` → `api_url = "https://..."`
- Usuwa prefix `AS_`, zamienia `_` na `-` w kluczach
- Konwertuje wartości: `"true"/"false"` → boolean, liczby → int/float

---

## 3. Transformacje (`transform.ml`)

### 3.1 CLI → TOML

```ocaml
val cli_key_to_toml : string -> string
(* "--api-url" → "api_url" *)
(* "--no-ssl" → "no_ssl" *)
```

- Usuń prefix `--`
- Zamień `-` na `_`

### 3.2 ENV → TOML

```ocaml
val env_key_to_toml : string -> string
(* "AS_API_URL" → "api_url" *)
(* "AS_MAX_RETRIES" → "max_retries" *)
```

- Usuń prefix `AS_`
- Zamień `_` na `-` w stringu
- Następnie zamień wszystkie `-` na `_` (dla spójności z TOML)

### 3.3 Typy wartości

```ocaml
val parse_value : string -> Well.Toml.value
(* "true" → boolean *)
(* "123" → integer *)
(* "3.14" → float *)
(* inne → string *)
```

---

## 4. Hierarchiczne scalanie (`merge.ml`)

```ocaml
val merge : Well.Toml.types list -> Well.Toml.types
(* [global; project; cli; env] → merged *)
```

- Funkcja redukuje listę map TOML od lewej do prawej
- Późniejsze źródła nadpisują wcześniejsze
- Obsługa zagnieżdżonych sekcji: `Well.Toml.get` / `Well.Toml.set`

### Algorytm:

```ocaml
let merge sources =
  List.fold_left (fun acc source -> Toml.patch acc source) Toml.empty sources
```

Gdzie `patch` iteruje po kluczach `source` i dodaje je do `acc`, nadpisując istniejące.

---

## 5. Interfejs główny (`config.ml` - rozszerzenie)

```ocaml
val load : ?project_path:string -> unit -> t
(* Ładuje konfigurację ze wszystkich źródeł *)

val load_with_metadata : ?project_path:string -> unit -> t * resolved
(* Zwraca też mapę skąd pochodzi każda wartość (do debugowania) *)

val reset : unit -> unit
(* Resetuje cache *)
```

### Sekwencja ładowania:

```ocaml
let load ?(project_path=".") () =
  let global = Sources.load_global () in
  let project = Sources.load_project project_path in
  let cli = Sources.parse_cli_args (Array.to_list Sys.argv |> List.tl) in
  let env = Sources.load_env () in
  let merged = Merge.merge [global; project; cli; env] in
  let t = from_toml merged in  (* konwersja Well.Toml → nasz typ t *)
  t
```

---

## 6. Integracja z istniejącym kodem - MIGRACJA

### 6.1 Pliki do usunięcia

```
bin/cli.ml          → DO USUNIĘCIA (duplikacja)
src/cli_args.ml     → DO USUNIĘCIA (duplikacja)
src/config.ml       → DO USUNIĘCIA (duplikacja)
```

### 6.2 Nowa struktura

Wszystkie funkcje konfiguracyjne w `lib/config/`:
- `lib/config/config.ml` — główny interfejs + `load()` + typy
- `lib/config/sources.ml` — źródła konfiguracji
- `lib/config/transform.ml` — transformacje kluczy
- `lib/config/merge.ml` — hierarchiczne scalanie

### 6.3 Aktualizacja `bin/main.ml`

Zamiast:
```ocaml
let config, quiet = Cli.parse_args ()
```

Będzie:
```ocaml
let config, quiet = Config.load ()
```

### 6.4 Zmiana ścieżki globalnej konfiguracji

| Przed                               | Po                           |
|-------------------------------------|------------------------------|
| `~/.config/axioms-sync/config.toml` | `~/.config/axioms-sync.toml` |

**Brak backward compatibility** — nowa ścieżka od początku.

### 6.5 Zmienne środowiskowe

Nowe prefixy z `AS_`:
- `OPENROUTER_API_KEY` → `AS_OPENROUTER_API_KEY`

Dla kompatybilności można tymczasowo wspierać stare nazwy z ostrzeżeniem.

---

## 7. Szczegóły implementacyjne

### 7.1 Obsługa błędów

- Plik TOML nie istnieje → pusta mapa, nie błąd
- Błąd parsowania TOML → loguj + pusta mapa + ostrzeżenie
- Nieznany argument CLI → pomijaj z opcjonalnym logiem
- Zła wartość env (np. `AS_MAX_RETRIES=abc`) → jako string, nie błąd

### 7.2 Wydajność

- Cache w `ref` (jak istniejący `lib/config/config.ml`)
- `reset()` do testów

### 7.3 Testowanie

```ocaml
(* test/axioms_sync_test.ml *)
let test_merge_priority () =
  let global = Toml.empty |> Toml.add ["api_url"] (Toml.String "global") in
  let project = Toml.empty |> Toml.add ["api_url"] (Toml.String "project") in
  let cli = Toml.empty |> Toml.add ["api_url"] (Toml.String "cli") in
  let env = Toml.empty |> Toml.add ["api_url"] (Toml.String "env") in
  let merged = Merge.merge [global; project; cli; env] in
  assert (get_string merged ["api_url"] = Some "env")

let test_env_transform () =
  assert (Transform.env_key_to_toml "AS_API_URL" = "api_url");
  assert (Transform.env_key_to_toml "AS_MAX_RETRIES" = "max_retries")
```

---

## 8. Przykładowe użycie

### Konfiguracja globalna (`~/.config/axioms-sync/axioms-sync.toml`)

```toml
[general]
provider = "openrouter"

[openrouter]
api_key = "sk-..."

[models]
smart = "opus4.6"
balanced = "sonnet4.6"
fast = "haiku4.5"
```

### Konfiguracja projektowa (`.axioms/axioms-sync.toml`)

```toml
[models]
smart = "sonnet4.7"  # nadpisuje globalny
```

### Wywołanie CLI

```bash
axioms-sync . --api-url https://custom.api.com --max-retries 5
```

### Zmienne środowiskowe

```bash
export AS_API_KEY="sk-proj-..."
export AS_MAX_RETRIES="10"
```

### Wynikowa konfiguracja (priorytet: env > cli > project > global)

```toml
provider = "openrouter"      # z global
api_key = "sk-proj-..."       # z AS_API_KEY
api_url = "https://custom.api.com"  # z --api-url
max_retries = "10"            # z AS_MAX_RETRIES
models.smart = "sonnet4.7"    # z project
models.balanced = "sonnet4.6" # z global
```

---

## 9. Zadania implementacyjne

### Faza 1: Stworzyć nowe pliki w `lib/config/`

1. [x] Stworzyć `lib/config/sources.ml`
   - [x] `load_global()` - ładuje `~/.config/axioms-sync.toml`
   - [x] `load_project()` - ładuje `.axioms/axioms-sync.toml` z projektu
   - [x] `parse_cli_args()` - parsuje Sys.argv → TOML
   - [x] `load_env()` - ładuje `AS_*` vars → TOML

2. [x] Stworzyć `lib/config/transform.ml`
   - [x] `cli_key_to_toml("api-url")` → `"api_url"`
   - [x] `env_key_to_toml("AS_API_URL")` → `"api_url"`
   - [x] Wartości pozostają jako stringi

3. [x] Stworzyć `lib/config/merge.ml`
   - [x] `merge([global; project; cli; env])` → scalona mapa TOML

4. [x] Rozszerzyć `lib/config/config.ml`
   - [x] Zaktualizować `load()` o 4-źródłowe ładowanie
   - [x] Zmienić ścieżkę na `~/.config/axioms-sync.toml`
   - [x] Usunąć cache (lub zachować dla performance)
   - [x] Dodać `reset()` do testów

### Faza 2: Migracja

5. [x] **USUNIĘTO** `bin/cli.ml` (nie istniał)
6. [x] **USUNIĘTO** `src/cli_args.ml` (nie istniał)
7. [x] **USUNIĘTO** `src/config.ml` (nie istniał)

### Faza 3: Aktualizacja bin/main.ml

8. [x] Zmienić `Cli.parse_args()` na `Config.load()`
9. [x] Flagi CLI (`--help`, `--models`, itp.) - dodane do `Config.Sources.parse_cli_args`

### Faza 4: Testy

10. [x] Testy JSON/TOML merge dostępne w `test/axioms_sync_test.ml`

---

## 10. Decyzje podjęte ✓

| Decyzja                     | Wybór                                            |
|-----------------------------|--------------------------------------------------|
| Stara ścieżka `config.toml` | Usunięta - tylko `axioms-sync.toml`              |
| Wartości numeryczne w env   | Zostawiamy jako stringi                          |
| Flagi CLI bez wartości      | Traktowane jako `flag = true`                    |
| Nieznane argumenty CLI      | Błąd                                             |
| Pliki do usunięcia          | `bin/cli.ml`, `src/cli_args.ml`, `src/config.ml` |
| Prefix zmiennych env        | `AS_` (np. `AS_API_KEY`)                         |
