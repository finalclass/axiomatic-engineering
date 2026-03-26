# Plan: axioms-sync jako program OCaml

## Motywacja

Benchmark browser automation na trzech modelach:

| Model | Czas tego samego zadania |
|-------|--------------------------|
| Opus 4.6 | 249s |
| Sonnet 4.6 | 46s |
| Haiku 4.5 | 33s |

Orkiestracja w Claude Code = wąskie gardło:
- Każdy krok to round-trip przez API (model generuje → tool call → odpowiedź → model myśli → kolejny tool call)
- Nie da się mieszać modeli per krok
- Flow jest deterministyczny — LLM niepotrzebnie decyduje "co dalej"
- Brak prawdziwej równoległości (agenty Claude Code to sekwencyjne subprocesy)

## Cel

Program OCaml zastępuje obecny `axioms-sync.md` (skill Claude Code) jako orkiestrator. Modele AI wywoływane bezpośrednio przez Anthropic API — dobór modelu per krok.

## Dlaczego OCaml

- 90% orkiestratora to parsowanie i transformacja drzew — core kompetencja OCamla (ADT, pattern matching)
- System typów łapie błędy w filtrowania kontekstów i kaskadzie labeli — krytyczne dla izolacji agentów
- Kompilacja do natywnego binary — szybki start, zero runtime overhead
- Projekt już używa dune

## Zależności

- `well` (~/Documents/well) — używamy:
  - `Well.fetch` — HTTP client z automatycznym TLS (Anthropic API)
  - `well_test` — framework testowy (describe/it/matchers)
- `eio` + `eio_main` — fiber-based async (`Eio.Fiber.all` do równoległych agentów, `Eio.Process` do spawn, `Eio.Path` do plików)
- `yojson` — JSON parsing/building
- `mirage-crypto-rng-eio` — inicjalizacja RNG wymagana przez TLS w Well.fetch

## Architektura

```
bin/
  axioms_sync.ml        ← entry point, CLI args

lib/axioms_sync/
  ├── types.ml          ← AST aksjomatu, labele, fazy, konteksty
  ├── snapshot.ml       ← Step 0: snapshot + diff (Eio.Path, Eio.Process)
  ├── loader.ml         ← Step 1: parsowanie MD → AST, śledzenie linków, kaskada
  ├── consistency.ml    ← Step 2: walidacja spójności (deterministyczna)
  ├── planner.ml        ← Step 3: change list, filtrowanie kontekstów per faza
  ├── markers.ml        ← Step 4: walidacja @axiom markerów w code/
  ├── implement.ml      ← Step 5: delegacja do AI (implementacja)
  ├── validate.ml       ← Step 6: delegacja do AI per label (walidacja)
  ├── satisfy.ml        ← Step 7: delegacja do AI (satisfaction review)
  └── tools.ml          ← definicje narzędzi dla agentów (read_file, write_file, bash, agent-browser)

lib/ai_access/
  ├── ai_access.ml      ← interfejs: model_id → send prompt+tools → response
  ├── agent.ml          ← pętla agentowa (prompt + tools → execute tool_use → loop)
  ├── anthropic.ml      ← provider: Anthropic API (Well.fetch)
  └── provider.ml       ← typ providera (moduł signature), rozszerzalny o OpenAI, Gemini, lokalne modele...
```

## Typy (types.ml)

```ocaml
type phase = Implementation | Validation | Satisfaction of float (* threshold *)

type context_marker = Code | Browser | Api | Axioms

type label_def = {
  name: string;                  (* "test", "ux", "security" *)
  phases: phase list;
  markers: context_marker list;
  model: string option;          (* override modelu per label *)
  description: string;           (* instrukcje dla agenta *)
}

type section = {
  heading: string;
  anchor: string;                (* heading-slug *)
  content: string;               (* surowy MD treści *)
  labels: string list;           (* nazwy labeli po kaskadzie *)
}

type axiom = {
  id: string;                    (* patient-client/booking.md *)
  name: string;
  sections: section list;
  labels: string list;           (* labele na poziomie pliku, po kaskadzie *)
  refs: string list;             (* linki do innych axiomów *)
  raw_content: string;
}

type axiom_change = Added | Deleted | Modified of string list (* zmienione sekcje *)

type task = {
  axiom_id: string;
  section: string option;
  label: label_def;
  phase: phase;
  context: string;               (* przefiltrowana treść aksjomatu *)
  tools: tool_def list;          (* per +markers *)
  model: string;                 (* model do użycia *)
}

type sync_result = {
  mode: [`Diff | `Full];
  changes: (string * axiom_change) list;
  implementation: task list;
  validation: task list;
  satisfaction: task list;
}
```

## Podział: co jest AI, co nie

### Kroki bez AI (czysty OCaml)
- **Step 0** — cp, diff -ru, parsowanie diffu → `snapshot.ml`
- **Step 1** — parsowanie Markdowna, śledzenie linków, kaskada labeli → `loader.ml`
- **Step 2** — walidacja referencji, duplikatów, faz labeli → `consistency.ml`
- **Step 3** — filtrowanie kontekstów per faza, budowanie change list, emitowanie tasków → `planner.ml`
- **Step 4** — parsowanie markerów @axiom w code/, walidacja parowania → `markers.ml`

### Kroki z AI (Anthropic API przez Well)
- **Step 5 (implementacja)** — Opus. Dostaje: change list, filtrowane aksjomaty, dostęp do code/
- **Step 6 (walidacja)** — model z definicji labela (domyślnie Sonnet). Osobny agent per label
- **Step 7 (satisfaction)** — Haiku. Osobny agent per scenariusz

## Klient Anthropic API (anthropic.ml)

```ocaml
type message = { role: string; content: content list }
and content =
  | Text of string
  | Tool_use of { id: string; name: string; input: Yojson.Safe.t }
  | Tool_result of { tool_use_id: string; content: string }

type tool_def = {
  name: string;
  description: string;
  input_schema: Yojson.Safe.t;
}

val create_message :
  model:string ->
  system:string ->
  messages:message list ->
  tools:tool_def list ->
  max_tokens:int ->
  message
(** POST https://api.anthropic.com/v1/messages via fetch *)
```

fetch (wyciągnięty z Well) — TLS z automatu:
```ocaml
let response = Fetch.fetch
  ~method_:"POST"
  ~headers:[
    ("x-api-key", api_key);
    ("anthropic-version", "2023-06-01");
    ("content-type", "application/json");
  ]
  ~body:(Yojson.Safe.to_string payload)
  "https://api.anthropic.com/v1/messages"
```

## Pętla agentowa (agent.ml)

```ocaml
val run_agent :
  model:string ->
  system:string ->
  prompt:string ->
  tools:tool_def list ->
  execute_tool:(string -> Yojson.Safe.t -> string) ->
  max_iterations:int ->
  string (* końcowy tekst odpowiedzi *)
```

Logika:
1. Wyślij prompt + tools do Anthropic API
2. Jeśli odpowiedź zawiera tool_use → execute_tool → dołącz wyniki → goto 1
3. Jeśli stop_reason = end_turn → zwróć tekst
4. Jeśli iterations > max → przerwij z błędem

## Narzędzia dla agentów (tools.ml)

```ocaml
val read_file : path:string -> string
val write_file : path:string -> content:string -> unit
val edit_file : path:string -> old_string:string -> new_string:string -> unit
val list_files : glob:string -> string list
val bash : command:string -> string (* stdout + stderr *)
val agent_browser : args:string list -> string (* Eio.Process.run *)
```

Każde narzędzie ma odpowiadający `tool_def` (JSON schema) + implementację.
Konteksty (`+markers`) kontrolują który agent dostaje które narzędzia:
- `+code` → read_file, write_file, edit_file, list_files
- `+browser` → agent_browser
- `+api` → bash (ograniczony do curl)
- domyślnie → bash (ogólny)

## Klasy modeli

Aksjomaty definiują **klasę** modelu (`{smart}`, `{balanced}`, `{fast}`), nie konkretny model. Orkiestrator mapuje klasy na modele.

### Składnia w labelach

```markdown
### [test] @implementation @validation +code
Unit tests. TDD.
(brak {class} → domyślna per faza: implementation={smart}, validation={balanced})

### [security] @validation +code +api {smart}
Security review — override: {smart} zamiast domyślnego {balanced} dla validation.

### [ux] @satisfaction(0.8) +browser
UX review — domyślna klasa dla satisfaction: {fast}.
```

### Domyślne klasy per faza

| Faza | Domyślna klasa | Uzasadnienie |
|------|----------------|--------------|
| `@implementation` | `{smart}` | Generowanie kodu wymaga głębokiego rozumowania |
| `@validation` | `{balanced}` | Weryfikacja: wystarczająco smart, szybszy |
| `@satisfaction` | `{fast}` | Browser automation + ocena subiektywna, szybkość kluczowa |

### Konfiguracja orkiestratora (CLI)

```
./axioms-sync . \
  --implementer opus4.6 \
  --planner sonnet4.6 \
  --smart opus4.6 \
  --balanced sonnet4.6 \
  --fast haiku4.5
```

Wszystkie parametry opcjonalne — domyślne wartości poniżej.

**A) Modele procesowe** — role w pipeline orkiestratora (nie kontrolowane przez aksjomaty):

| Parametr | Domyślnie | Co robi |
|----------|-----------|---------|
| `--implementer` | `opus4.6` | Step 5: generuje kod, pisze testy |
| `--planner` | `sonnet4.6` | Step 2: wykrywanie sprzeczności, Step 3: analiza zmian |

**B) Klasy labelowe** — mapowanie `{smart}`, `{balanced}`, `{fast}` na modele (kontrolowane przez aksjomaty):

| Parametr | Domyślnie | Domyślna faza |
|----------|-----------|---------------|
| `--smart` | `opus4.6` | `@validation` override |
| `--balanced` | `sonnet4.6` | `@validation` domyślna |
| `--fast` | `haiku4.5` | `@satisfaction` domyślna |

**Rozróżnienie:** aksjomaty decydują *jaka klasa* modelu weryfikuje/ocenia dany label. Orkiestrator decyduje *który konkretny model* implementuje kod i planuje pracę. Aksjomaty nie mają wpływu na `--implementer`/`--planner`.

### Moduł ai_access

Osobna biblioteka (`lib/ai_access/`) — abstrakcja nad providerami AI. Orkiestrator nie wie jaki provider stoi za danym model ID.

```ocaml
(* provider.ml — signature *)
module type Provider = sig
  val name : string  (* "anthropic", "openai", "google", ... *)
  val send :
    model:string ->
    system:string ->
    messages:message list ->
    tools:tool_def list ->
    max_tokens:int ->
    response
end

(* ai_access.ml — router *)
type config = {
  implementer: string;  (* model ID *)
  planner: string;
  smart: string;
  balanced: string;
  fast: string;
}

let default_config = {
  implementer = "opus4.6";
  planner = "sonnet4.6";
  smart = "opus4.6";
  balanced = "sonnet4.6";
  fast = "haiku4.5";
}

(* Resolve model alias → provider + model ID *)
val resolve : string -> (module Provider) * string

(* Agent loop — provider-agnostic *)
val run_agent :
  model:string ->
  system:string ->
  prompt:string ->
  tools:tool_def list ->
  execute_tool:(string -> Yojson.Safe.t -> string) ->
  max_iterations:int ->
  string
```

Model aliasy (krótkie nazwy → pełne model ID):

| Alias | Provider | Model ID |
|-------|----------|----------|
| `opus4.6` | Anthropic | `claude-opus-4-6` |
| `sonnet4.6` | Anthropic | `claude-sonnet-4-6` |
| `haiku4.5` | Anthropic | `claude-haiku-4-5-20251001` |
| `gpt4o` | OpenAI | `gpt-4o` |
| `gemini2` | Google | `gemini-2.0-flash` |

Docelowo: dodanie nowego providera = nowy moduł implementujący `Provider` + wpis w `resolve`.

## Równoległość (Eio.Fiber)

```ocaml
(* Step 5 — sekwencyjnie per aksjomat *)
List.iter run_implementation tasks.implementation

(* Step 6 — równolegle per label *)
Eio.Fiber.all (List.map (fun task -> fun () -> run_validation task) tasks.validation)

(* Step 7 — równolegle per scenariusz *)
Eio.Fiber.all (List.map (fun task -> fun () -> run_satisfaction task) tasks.satisfaction)
```

Fix cycle: jeśli step 6 lub 7 failuje → tylko failing taski wracają do step 5 → ponownie tylko failing taski w step 6/7.

## Cykl naprawczy

```
implement → validate → satisfy
    ↑           |          |
    └───────────┘          |
    ↑                      |
    └──────────────────────┘
```

Feedback z walidacji/satisfaction → trafia do implementing agenta jako dodatkowy kontekst (ale BEZ holdout scenariuszy — agent nadal ich nie widzi, dostaje tylko opis problemu).

## Pipeline — co się dzieje krok po kroku

```
axioms/*.md
    │
    ▼
┌─────────────────────────────────────────────────┐
│  KOMPILATOR (OCaml, zero AI)                    │
│                                                 │
│  Step 0: Snapshot current/ vs freeze/ → diff    │
│  Step 1: Parse MD → AST (axiom, section, label) │
│  Step 2: Validate (refs, dupes, phases)         │
│  Step 3: Filter contexts → emit task list       │
│  Step 4: Validate @axiom markers in code/       │
│                                                 │
│  Output: task[] z modelem, promptem, narzędziami│
└────────────────────┬────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────┐
│  DISPATCHER (OCaml + Fetch + Eio.Fiber)    │
│                                                 │
│  Step 5: Implement (Opus, sekwencyjnie)         │
│  Step 6: Validate (Sonnet, równolegle)          │
│  Step 7: Satisfy (Haiku, równolegle)            │
│                                                 │
│  Fix cycle jeśli fail                           │
│  Emit: .axioms/sync-result.md                   │
│  Freeze: cp current/ → freeze/                  │
└─────────────────────────────────────────────────┘
```

## CLI

```
axioms-sync [--full] [ścieżka-do-projektu]
```

- Domyślnie: diff mode, bieżący katalog
- `--full`: pełny sync (ignoruj freeze)
- Ścieżka: katalog z `axioms/` i `code/`
- `ANTHROPIC_API_KEY` z env

## Budowanie i integracja

```
# W dune-project axiomatic-engineering:
(depends well ...)

# Albo: well jako git submodule / vendored dependency
```

Opcja integracji ze skillem Claude Code:
- Skill `/axioms-sync` wywołuje `axioms-sync` binary zamiast orkiestrować sam
- Albo: binary jest standalone, nie potrzebuje Claude Code

## Etapy implementacji

### Etap 1: Kompilator (zero AI)
- types.ml, loader.ml, consistency.ml, planner.ml, markers.ml, snapshot.ml
- Testy: parsowanie axiomów z example/, walidacja markerów
- **Cel:** `axioms-sync --dry-run` emituje task list bez wywoływania AI

### Etap 2: Agent loop + Anthropic client
- anthropic.ml, agent.ml, tools.ml
- Test: prosty agent z jednym narzędziem (read_file)
- **Cel:** agent potrafi prowadzić konwersację z API i wykonywać narzędzia

### Etap 3: Kroki AI (implement, validate, satisfy)
- implement.ml, validate.ml, satisfy.ml
- Integracja z agent loop
- **Cel:** pełny sync na example/ projekcie

### Etap 4: Fix cycle + równoległość
- Cykl naprawczy implement→validate→satisfy
- Eio.Fiber.all dla step 6 i 7
- **Cel:** pełny sync na TerapiaPro

## Scenariusze testów

Testy pisane w `well_test` (describe/it/matchers). Dane testowe: `example/` projekt + dedykowane fixtures.

### A) Loader — parsowanie axiomów (loader_test.ml)

1. **Parsowanie main.md** — wczytuje glossary, label definitions, listę linków do axiomów
2. **Śledzenie linków** — z main.md → technology.md, main-use-case.md, frontend-design.md, hiding-finished.md, infrastructure.md (5 axiomów)
3. **Rekursywne linki** — axiom A linkuje do B, B linkuje do C → wszystkie 3 wczytane
4. **Plik poza łańcuchem linków** — plik istnieje w axioms/ ale nie jest linkowany z main.md → nie wczytany
5. **Parsowanie sekcji** — frontend-design.md ma sekcje: "Visual inspiration", "Paleta kolorów", "Typografia" itd. z poprawnymi anchorami
6. **Kaskada labeli** — label [ui] z main.md ## Axioms dziedziczony na wszystkie axiomy. Sekcja z własnym labelem [test] → ma [ui] + [test]
7. **Parsowanie label definitions** — `### [ui] @satisfaction(satisfaction-level) +browser` → faza=Satisfaction(0.7), markers=[Browser]
8. **Glossary lookup w threshold** — `@satisfaction(satisfaction-level)` → szuka `**satisfaction-level** — 0.7` w glossary → threshold=0.7
9. **Threshold jako literal** — `@satisfaction(0.85)` → threshold=0.85
10. **Model class w labelu** — `### [security] @validation +code {smart}` → model_class=Some Smart
11. **Brak model class** — `### [test] @implementation @validation +code` → model_class=None

### B) Consistency — walidacja spójności (consistency_test.ml)

1. **Poprawny projekt** — example/ przechodzi bez błędów
2. **Brakujący link** — axiom referencuje `[Foo](./foo.md)` ale plik nie istnieje → error
3. **Duplikat nazwy axioma** — dwa pliki z `# Technology` → error
4. **Label bez fazy** — `### [broken]` (brak @implementation/@validation/@satisfaction) → error
5. **Glossary key nie istnieje** — `@satisfaction(nonexistent-key)` → error
6. **Sprzeczne axiomy** — (opcjonalnie, z LLM) dwa axiomy mówią przeciwne rzeczy

### C) Snapshot + diff (snapshot_test.ml)

1. **Pierwszy run** — brak freeze/ → full sync, wszystkie axiomy na liście zmian
2. **Brak zmian** — current/ == freeze/ → "No changes in axioms."
3. **Nowy plik** — dodany axiom w current/, brak w freeze/ → change: Added
4. **Usunięty plik** — plik w freeze/, brak w current/ → change: Deleted
5. **Zmieniony plik** — treść się różni → change: Modified z listą zmienionych sekcji
6. **Full mode** — `--full` → ignoruje freeze/, wszystkie axiomy na liście

### D) Planner — filtrowanie kontekstów (planner_test.ml)

1. **Implementation context** — aksjomat z [test] (@implementation @validation) + [ui] (@satisfaction) → implementation context zawiera treść aksjomatu + instrukcje [test], NIE zawiera bloku [ui]
2. **Validation context** — ten sam aksjomat → validation context zawiera [test] z +code narzędziami
3. **Satisfaction context** — ten sam aksjomat → satisfaction context zawiera [ui] z +browser narzędziami, threshold=0.7
4. **Holdout** — label z @validation only (bez @implementation) → blok niewidoczny dla implementera
5. **Domyślna klasa modelu** — task dla @implementation → model_class=Smart, @validation → Balanced, @satisfaction → Fast
6. **Override klasy** — label z {smart} + @validation → model_class=Smart (nie Balanced)

### E) Markers — walidacja @axiom (markers_test.ml)

1. **Poprawne markery** — example/code/index.html → wszystkie markery sparowane i wskazują na istniejące axiomy
2. **Niesparowany marker** — `@axiom: foo.md` bez `/@axiom: foo.md` → error
3. **Nieistniejący axiom** — `@axiom: nonexistent.md` → error
4. **Zagnieżdżone markery** — `@axiom: A` wewnątrz `@axiom: B` → ok
5. **Orphaned code** — kod poza markerami w sekcji {{content}} → warning

### F) AI Access (ai_access_test.ml)

1. **Resolve alias** — `"opus4.6"` → provider=Anthropic, model_id=`"claude-opus-4-6"`
2. **Nieznany alias** — `"gpt-turbo-99"` → error z listą dostępnych aliasów
3. **Agent loop — single turn** — mock provider zwraca tekst → pętla kończy po 1 iteracji
4. **Agent loop — tool use** — mock provider zwraca tool_use → narzędzie wykonane → wynik dołączony → drugie wywołanie zwraca tekst → koniec
5. **Agent loop — max iterations** — mock provider zawsze zwraca tool_use → pętla przerywa po N iteracjach z błędem
6. **Config defaults** — brak parametrów CLI → domyślne modele (opus4.6, sonnet4.6, haiku4.5)
7. **Config override** — `--fast haiku4.5 --implementer sonnet4.6` → config.fast="haiku4.5", config.implementer="sonnet4.6"

### G) Integracja — pełny pipeline (integration_test.ml)

1. **Dry run na example/** — `axioms-sync --dry-run example/` → emituje task list, zero wywołań AI, zero zmian w code/
2. **Snapshot → freeze** — po udanym syncu current/ skopiowane do freeze/
3. **Freeze nie nadpisane przy błędzie** — sync failuje w step 5 → freeze/ bez zmian (stary stan)
4. **Diff mode pomija niezmienione** — zmień 1 axiom, uruchom sync → tylko ten axiom na liście zmian
5. **CLI parsowanie** — `./axioms-sync . --full --implementer sonnet4.6 --fast haiku4.5` → poprawny config

### H) Tools — narzędzia dla agentów (tools_test.ml)

1. **read_file** — istniejący plik → zwraca treść
2. **read_file** — nieistniejący plik → error message (nie exception)
3. **write_file** — zapisuje plik, read_file zwraca tę samą treść
4. **edit_file** — podmienia old_string na new_string w pliku
5. **edit_file** — old_string nie znaleziony → error
6. **list_files** — glob `*.md` w example/axioms/ → 6 plików
7. **bash** — `echo hello` → "hello\n"
8. **bash** — komenda z niezerowym exit code → error z stderr

## Pomysł: Pipeline opisów screenshotów dla satisfaction

**Problem:** Modele multimodalne (vision) są wolne i drogie przy testach satisfaction opartych o screenshoty. Opus rozumuje dobrze, ale jest wolny z obrazami. Gemini Flash / MiMo-V2-Omni są szybkie, ale mogą nie rozumować wystarczająco dobrze o zgodności z aksjomatem.

**Rozwiązanie — dwuetapowy pipeline:**

1. **agent-browser** robi screenshot
2. **Tani model vision** (Gemini Flash, MiMo) opisuje screenshot jako tekst — proste zadanie: "opisz co widzisz na tym screenshocie"
3. **Dowolny model** (nawet non-vision jak Haiku) ocenia opis tekstowy vs aksjomat i wystawia rating satisfaction

**Implementacja:**
- Nowe narzędzie w `tools.ml`: `describe_screenshot` — przyjmuje ścieżkę do screenshota, zwraca opis tekstowy
- Model vision robi jedno proste zadanie (opis), model judge robi jedno proste zadanie (ocena)
- Opisy są cachowalne i debugowalne (tekst vs obraz)

**Zalety:**
- Judge nie musi być multimodalny → tańsze, szybsze modele
- Opis screenshota to prostsze zadanie niż ocena satisfaction → tani model vision wystarczy
- Opisy tekstowe są cachowalne i łatwiejsze do debugowania
- Separacja odpowiedzialności: vision ≠ reasoning

## Pytania otwarte

1. **Caching sesji agent-browser** — czy agent-browser może trzymać sesję między krokami? (zaloguj raz, reuse w step 6 i 7)
2. ~~**Streaming** — czy orkiestrator powinien streamować output agentów na stdout w czasie rzeczywistym?~~ ✅ Zrobione (stream-json + --quiet)
3. **Max iterations** — ile razy powtarzać cykl implement→validate→satisfy zanim się poddać? (propozycja: 3)
4. **Cost tracking** — logować koszt per krok (input/output tokens × cena modelu)?
5. **Step 2 sprzeczności** — wykrywanie semantycznych sprzeczności wymaga LLM. Jaki model? (propozycja: Haiku)
