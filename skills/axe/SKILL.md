---
name: axe
description: Spec-anchored development. Human-authored docs/ is the source of truth; code is derived. Two entry points — (1) a chat request goes through spec first (write docs, then STOP), (2) "axe sync" / "zsynchronizuj" or "rąbiemy" (from axe - siekiera). diffs docs against .axe/freeze and implements that delta. Use whenever the user mentions axe, sync, docs, SDD, STP, contracts, architecture, or asks to change lib/ or test/.
---

# axe — Spec-Anchored Development

This repository works in **spec-anchored development**. Human-authored artifacts in `docs/` are the source of truth; code and tests are derived. Your role is to protect this order. Implementing first and documenting later creates what Juval Lowy calls cognitive debt.

Start every session that might touch the system by reading `docs/main.md` (labels + map), then the artifacts that file points at.

## The binding artifacts

| Artifact | Location | What it captures |
|---|---|---|
| `docs/main.md` | `docs/` | System map: **label definitions**, links to arch and mockup. Not the architecture itself. |
| `docs/arch.md` | `docs/` | IDesign layers, call-graph, resource map, system-level workflows |
| `docs/mockup/DESIGN.md` | `docs/mockup/` | Visual identity: tokens + prose (why a color exists). Portable across Well / Flutter / anything. |
| `docs/mockup/tokens.css` | `docs/mockup/` | Derived projection of DESIGN.md **for HTML mockup only**. Never imported by the app. |
| `docs/mockup/screens/*.html` | `docs/mockup/screens/` | Visual contract of each screen / state. Pixel-to-pixel, not HTML-to-HTML. |
| `docs/<service>/sdd.md` | `docs/<service>/` | Per-service black-box SDD: role, boundary, assumptions, workflows, **binding contract** (inline methods, or a TOC) |
| `docs/<service>/methods/<rpc>.md` | `docs/<service>/methods/` | Per-method spec when Contract is split: signature, input, output, use-case, local types |
| `docs/<service>/types.md` | `docs/<service>/` | Types used by more than one method of the service; linked from those methods |
| `docs/<service>/sdd.toml` | `docs/<service>/` | Executable contract (RPC + messages). Human-authored with the SDD. |
| `lib/contract/*.toml` | `lib/contract/` | Bit-identical, comment-free copy of `sdd.toml` for `well contract build`. Not the source of truth. |
| `docs/<service>/stp.md` | `docs/<service>/` | Service Test Plan — verification strategy (human). Test code is derived. |
| `docs/<client>/<name>.tag.md` | `docs/<client>/` | Frontend component contract: attrs / emits / use cases. No layout. |

Code under `lib/` and tests under `test/` are **derived**. They are never a source of truth.

Look lives in the mockup, not in the tag/SDD. A `*_page.md` or `.tag.md` links to `docs/mockup/screens/<file>.html`. Do not describe pixels in Markdown.

### Labels

Defined **only** in `docs/main.md`. A spec file may attach a name (`[look]`) under its heading. Unknown label = consistency error.

| Label | Phases | Agent does |
|---|---|---|
| `[impl]` | `@implementation +code` | Bring code in line with the changed spec |
| `[contract]` | `@implementation @validation +code` | Project `sdd.toml` → `lib/contract/` and compile |
| `[test]` | `@implementation @validation +code` | Write / update tests **only** from STP (and headings labeled `[test]`). Never from implementation, use cases, or a generic “code needs tests” rule |
| `[look]` | `@validation +browser` | Compare running UI to the mockup at the same viewport |

Defaults when a file has no label: `sdd.toml` → `[contract]`; `stp.md` → `[test]`; `*_page.md` / `*.tag.md` / `docs/mockup/screens/*` → `[impl] [look]`; `sdd.md` / `types.md` / `methods/*.md` / `arch.md` / `DESIGN.md` → `[impl]`.

Do not invent extra labels. Do not put label *definitions* in `arch.md`.

### The TOML rule

Contract lives in `docs/<service>/` (`sdd.md` Contract + optional `methods/<rpc>.md` + `types.md` + `sdd.toml`). `lib/contract/*.toml` exists only because codegen reads it. Edit the SDD first, then sync the projection. Never invent API in `lib/contract/` alone.

Frontend components have no TOML — the contract is the `.tag.md`.

## Present state

`docs/` is the application **as it is**. Write that. Do not describe the
previous shape, the thought process, or that this edit replaced something.
What used to be is git history.

## Docs proposal = unified diff

When you suggest a change to `docs/`, the architect reviews **hunks**,
not a description of hunks. The patch is the proposal. A plan is not.

- Format: one or more fenced `diff` blocks, unified (`---` / `+++` paths,
  `@@` hunks, `-` / `+` lines, enough context to apply). New file:
  `--- /dev/null` and all `+`. `+` lines are present-state text.
- Wrong: "I would add…", paraphrases of new sections, a bullet list of
  intended edits, then "ok?". That is not a proposal. No hunks on screen
  = you have not proposed. Do not ask the architect to approve a
  description.
- One diagnosis line (artifact + section) may sit above the fence.
  Completeness questions may sit after it. After that: stop.

## Two entry points

### A. Change requested in chat

The architect has **not** yet edited the spec. Do **not** write code.

1. **Diagnosis** — one line: artifact + section the request belongs to (SDD method, arch edge, mockup screen, DESIGN.md token, STP note). If it maps nowhere, say so. For a backend change: read that service’s SDD Contract and `docs/arch.md` first; decide whether the contract must move or only implementation. Do **not** read the service’s code until that strategy is set (zoom-in).
2. **Propose** — the unified diff of the spec/mockup/DESIGN.md (see **Docs proposal**). Do not edit `docs/` in this turn. End the turn.
3. **Completeness** — every touched contract method has signature + use case; assumptions written; STP covers new behavior or the architect accepts the gap out loud; arch and DESIGN.md stay coherent. Missing pieces → ask, do not guess. Completeness does not replace the hunks.
4. **Coherence** — state that the touched artifacts agree. Wait for explicit "ok" / "approve" / "go" **of those hunks**.
5. **Write spec** — only after that acceptance, apply **Writing `docs/`**.
   Then **stop**. Do not implement.

Exception: purely mechanical fixes with no spec impact (build flag). If unsure, treat as spec.

### Writing `docs/`

Hard gate. **Never** create, overwrite, or patch anything under `docs/`
until the architect has accepted a unified diff you already showed **in a
previous turn**. Showing the diff and writing in the same turn is
forbidden. „Zrób docs” / „dopisz spec” without an accepted diff is
still: show the hunks, stop.

You are a text editor on `docs/`. Never write those files first.

1. Show the unified diff (see **Docs proposal**). End the turn.
2. Wait for explicit acceptance of **those hunks**
   ("ok" / "approve" / "go"). A later "ok" on a different question
   does not approve an unshown docs edit. Approving a description
   you never patched does not count.
3. Write **only** the accepted lines. Do not add beyond the diff.
4. Do not implement. Do not test. Do not start `axe sync` on your own.
   Approving docs is **not** a signal to code. **Stop.**
5. Code starts only when the architect says `axe sync` / „zsynchronizuj”.

This gate does **not** apply to entry B (`axe sync`): the architect
already changed `docs/`. Sync must still not invent extra spec.

Contract navigation: `## Contract` in `docs/<service>/sdd.md` (inline methods, or a TOC linking to `methods/<rpc>.md`). Shared types: `docs/<service>/types.md`. `lib/contract/*.toml` is a comment-free copy of `sdd.toml` for codegen — sync it only during entry B, never as a stand-in for the SDD.

#### Describe

If asked to describe something in `docs/`, write **at most one short sentence**. Prefer a link over prose.

### B. `axe sync` / „zsynchronizuj” / „zrób diffa docs”

The architect **already** changed `docs/`. You do not invent scope from chat. You compute the delta against freeze and implement that.

#### Step 0 — Snapshot

Text files from `docs/` (`*.md`, `*.toml`, `*.html`, `*.css`) → `.axe/current/` (wipe the folder first, keep relative paths).

Binaries (png, jpg, svg, …): do **not** copy. Append `sha256  relative/path` lines to `.axe/current/ASSETS`.

#### Step 1 — Diff

- No `.axe/freeze/` → **not** a first-run implement-everything. After Step 0, copy the snapshot as the baseline and stop:

  ```
  rm -rf .axe/freeze
  cp -a .axe/current .axe/freeze
  ```

  Print: freeze was missing — current `docs/` is now the baseline. Do **not**
  diff against git history. Do **not** implement `lib/` / `test/` from the
  whole docs tree. If this `axe sync` follows a just-written spec, implement
  **only** that spec’s delta — not the whole docs tree.
- Freeze exists → `diff -ru .axe/freeze .axe/current` for text; compare `ASSETS` for binaries. A changed hash is „asset X changed — open the new file”, not a pixel diff.

Print:

```
## Docs changes since last sync
- Added: …
- Deleted: …
- Modified: …
```

If the set is empty, stop. Nothing to implement.

#### Step 2 — Consistency

- Every link in the changed files resolves.
- `sdd.toml` matches the SDD Contract section it belongs to.
- Labels used on files exist in `docs/main.md`.
- New color / new control kind on a mockup screen is declared in `DESIGN.md` (no raw hex that already has a token).
- `docs/mockup/tokens.css` still matches DESIGN.md if DESIGN.md changed — update the projection, do not edit tokens.css as a source.
- If a changed screen/page has no owning `*_page.md` / `.tag.md`, say so (gap). Do not invent a service.

Contradictions → **stop** and report. Do not implement a workaround.

#### Step 3 — Change list

For each changed artifact, list work filtered by label phases:

```
## Change list (implementation)
### docs/operations_client/project_page.md
- [ ] …

## Verification
- [ ] contract / compile  (if [contract])
- [ ] tests               (if [test])
- [ ] look vs mockup      (if [look])
```

Write this to `.axe/last-sync.md`. Then implement — the architect already approved by editing docs. Do not wait for a second "go" unless Step 2 found gaps.

#### Step 4 — Implement

You are a full agent on derived code: infer and close the implementation so it matches docs. Do not leave the delta half-done.

Only the delta. Follow IDesign. Project TOML when `[contract]`. Write or update tests **only** when `[test]` — never alongside `[impl]` / `[contract]` / `[look]`. Add `@doc path/to.md` markers **only** when one code file realizes several docs (coarse regions). Do not wrap every block. Do not comment OCaml to explain domain — that lives in the spec.

Do not modify `docs/` during sync unless `tokens.css` must be regenerated from DESIGN.md (derived). If a spec is unrealizable, stop and report.

#### Step 5 — Verify

Run what the labels require. `[look]`: same viewport (default 1440×900), screenshot mockup and running app, compare layout / type / color / states. Fail on a clear miss; do not require bitwise PNG identity (font hinting, scrollbars). `[test]`: run the STP-derived tests you wrote or updated. Without `[test]`, do not add tests to make a suite green.

Failures → fix from the error description, still without changing docs. Repeat until checks pass or you must escalate a spec hole.

#### Step 6 — Freeze

Only after implementation **and** verification succeed:

```
rm -rf .axe/freeze
mv .axe/current .axe/freeze
```

A failed sync leaves freeze untouched so the next run sees the same delta.

`.axe/current/` is scratch (gitignore). `.axe/freeze/` is the last successful docs snapshot (text + ASSETS). Commit freeze if the project does; never commit PNG copies.

## Before you touch code

1. `docs/main.md` — labels and map.
2. `docs/arch.md` — layers, call-graph, resources.
3. If the change is visual: `docs/mockup/DESIGN.md` and the owning `screens/*.html`.
4. `docs/<service>/sdd.md` (Contract is binding — follow TOC links to `methods/<rpc>.md` and `types.md` when split) and `sdd.toml`.
5. `docs/<service>/stp.md` when it exists and you touch covered behavior.
6. For a component: `docs/<client>/<name>.tag.md` (attrs / emits / use cases — not layout).
7. WELL: `lib/contract/<Service>.toml` only as a cross-check; SDD wins.

Missing artifact → say so. Do not infer a contract from code.

## What goes in `sdd.md`

Strict black-box:

1. **Role**
2. **Abstraction boundary**
3. **Contract** — in `sdd.md` (inline) **or** split: `sdd.md` Contract is a TOC linking to `docs/<service>/methods/<rpc>.md` (signature, input, output, use-case, local types). Types used by more than one method of the service live in `docs/<service>/types.md` and are linked from those methods. `sdd.toml` remains the executable wire (when present).
4. **Assumptions** — a bug is a violation of an assumption.
5. **Scenarios / workflows** of *this* service. Multi-manager journeys go to `arch.md`.

Do not list collaborators (that is the call-graph), storage technology, algorithms, or verification strategy.

### Frontend `.tag.md`

Same Role / boundary. Contract is Attrs, Emits, Use cases (verbs). **No State, no View/layout, no Msg.** Look is the mockup. A one-line `Look: [screen](../mockup/screens/….html)` is allowed.

## What goes in `stp.md`

Critical behaviors, collaborator substitution plan, endpoint modes if any, what is explicitly not tested here. Strategy is human; test code is derived. No STP scenario = no new test code. Do not fill that gap from use cases or from the implementation.

## What goes in `docs/arch.md`

IDesign layers, components table, call-graph, resource map, system-level workflows. Not labels. Not tokens.

## Mockup rules

- `docs/mockup/` is documentation, not a frontend to ship.
- DESIGN.md is the visual source of truth. `tokens.css` is derived for the HTML pencil.
- New recurring control = named component in DESIGN.md, then a semantic class, then use on a screen.
- Utility-soup in a screen is a sketch, not a contract. Implementation (including Flutter) reads DESIGN.md + the rendered screen.
- One file per screen or per state (`planner-meta-list.html`, not one form with hidden sections as the spec).
- Do not `@import` the application's `static/design-tokens.css`.

## Source of truth

`docs/` (main, arch, DESIGN.md, screens, SDD, toml, STP, tags) is binding. Code conforms. When code disagrees: report. Default is fix the code. Never change the spec on your own; the architect decides if the spec should move.

## No code comments

Never add comments in source. Domain and architecture live in `docs/`. `@doc` markers are identifiers, not explanations.

## IDesign layering

Client → Manager → Engine → Access → Resource (+ Utility). Manager ↛ Manager. Access ↛ Access. Access methods are Atomic Business Verbs, not CRUD. Contract method descriptions are literal.

## Use cases vs workflows

| Term | Meaning | Where |
|---|---|---|
| Use case | One Manager call | Activity diagram on that method in the SDD (`sdd.md` Contract, or `methods/<rpc>.md` when split) |
| Workflow | Sequence of use cases | `sdd.md` Scenarios (one service) or `arch.md` (system-wide) |

## Worked examples

**Chat:** "Add FileManager.ArchiveClosedCases."
Diagnosis (one line) → unified diff of SDD + toml + assumption + STP (no prose of the edit) → wait → write spec → **STOP**.

**Sync:** architect says `axe sync` (or already edited `docs/`).
`axe sync` → diff vs freeze → change list → implement matching UI/code → `[look]` in the browser → freeze.
