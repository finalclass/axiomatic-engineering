---
name: axe
description: Spec-anchored development. Human-authored docs/ is the source of truth; code is derived. Two entry points — (1) a chat request goes through spec first (write docs, then STOP), (2) "axe sync" / "zsynchronizuj" or "rąbiemy" (from axe - siekiera). diffs docs against .axe/freeze and implements that delta. Use whenever the user mentions axe, sync, docs, SDD, STP, contracts, architecture, or asks to change lib/ or test/.
---

# axe — Spec-Anchored Development

This repository works in **spec-anchored development**. Human-authored artifacts in `docs/` are the source of truth; code and tests are derived. Your role is to protect this order. Implementing first and documenting later creates what Juval Lowy calls cognitive debt.

Start every session that might touch the system by reading `docs/main.md` (labels + map), then the artifacts that file points at.

## The binding artifacts

Project instructions select the contract format and review mode. For projects
explicitly retaining standalone TOML or a methods directory, read
[legacy contract compatibility](references/legacy-contracts.md).
When the project or user explicitly selects direct Git/T3 review, write the requested specification changes after
Specification review and stop; this overrides the diff-before-write gate.
Implementation still requires an explicit sync request.

| Artifact | Location | What it captures |
|---|---|---|
| `docs/main.md` | `docs/` | System map: **label definitions**, links to arch and mockup. Not the architecture itself. |
| `docs/arch.md` | `docs/` | IDesign layers, call-graph, resource map, system-level workflows |
| `docs/mockup/DESIGN.md` | `docs/mockup/` | Visual identity: tokens + prose (why a color exists). Portable across Well / Flutter / anything. |
| `docs/mockup/tokens.css` | `docs/mockup/` | Derived projection of DESIGN.md **for HTML mockup only**. Never imported by the app. |
| `docs/mockup/screens/*.html` | `docs/mockup/screens/` | Visual contract of each screen / state. Pixel-to-pixel, not HTML-to-HTML. |
| `docs/<service>/sdd.md` | `docs/<service>/` | Per-service black-box SDD and contract index: role, boundary, assumptions, workflows, and links to RPC specs |
| `docs/<service>/<rpc>.md` | `docs/<service>/` | Flat per-method spec: complete fenced TOML `[service.rpc]` signature, Request/Response, use case, and method-local types |
| `docs/<service>/types.md` | `docs/<service>/` | Types used by more than one method of the service; linked from those methods |
| `lib/contract/<Service>.toml` | `lib/contract/` | Deterministically merged, comment-free projection of the contract TOML fenced in the service Markdown. Written only by `axe sync` for `well contract build`; never authored manually. |
| `docs/<service>/stp.md` | `docs/<service>/` | Service Test Plan — verification strategy (human). Test code is derived. |
| `docs/<client>/<name>.tag.md` | `docs/<client>/` | Frontend component contract: attrs / emits / use cases. No layout. |
| Linked `docs/**/*.json` | `docs/` | Text contract artifact, including OpenAPI schemas explicitly linked from an SDD or contract Markdown. |

Code under `lib/` and tests under `test/` are **derived**. They are never a source of truth.

Look lives in the mockup, not in the tag/SDD. A `*_page.md` or `.tag.md` links to `docs/mockup/screens/<file>.html`. Do not describe pixels in Markdown.

### Labels

Defined **only** in `docs/main.md`. A spec file may attach a name (`[look]`) under its heading. Unknown label = consistency error.

| Label | Phases | Agent does |
|---|---|---|
| `[impl]` | `@implementation +code` | Bring code in line with the changed spec |
| `[contract]` | `@implementation @validation +code` | When defined by the repository, project contract-bearing Markdown → `lib/contract/` and compile |
| `[test]` | `@implementation @validation +code` | Write / update tests **only** from STP (and headings labeled `[test]`). Never from implementation, use cases, or a generic “code needs tests” rule |
| `[look]` | `@validation +browser` | Compare running UI to the mockup at the same viewport |

Defaults when a file has no label: `stp.md` → `[test]`; `*_page.md` / `*.tag.md` / `docs/mockup/screens/*` → `[impl] [look]`; `sdd.md` / `types.md` / RPC Markdown / `arch.md` / `DESIGN.md` → `[impl]`. Independently of labels, adding, changing, or deleting a fenced contract TOML block triggers contract consistency, projection, and compilation. Do not require or add `[contract]` when `docs/main.md` does not define it.

Do not invent extra labels. Do not put label *definitions* in `arch.md`.

### The TOML rule

The authored contract lives only in Markdown under `docs/<service>/`: `sdd.md`, flat `<rpc>.md` method files, and `types.md`. Each RPC method file contains its complete TOML `[service.rpc]` signature; fenced TOML may also define method-local message types. Types used by multiple methods, or exported to another service through a qualified reference, live in `types.md`. Small services may keep complete methods inline in `sdd.md`, but do not mix authored Markdown with a manually maintained `sdd.toml` or `contract.toml`.

`lib/contract/<Service>.toml` exists only because the Well compiler reads TOML. It is a deterministic merged projection, written only during `axe sync`. Never edit it as a source or invent API there.

Frontend components have no TOML — the contract is the `.tag.md`.

## Present state

`docs/` is the application **as it is**. Write that. Do not describe the
previous shape, the thought process, or that this edit replaced something.
What used to be is git history.

## Specification review

Before diagnosing, proposing or reviewing a substantive specification or contract
change, read the available `idesign-architecture/SKILL.md` and relevant references.
Its catalog description and the layer summary are not substitutes. Read the
owning service and affected dependency contracts; verify the meaning and returned
fields of existing operations before extending an API. Pure spelling and
formatting edits do not require an architecture review.

Before presenting or saving the proposal:

- Make the smallest semantic change that satisfies the request. Each changed
  artifact must be necessary for that outcome; keep optional improvements outside
  the proposal. An existing requirement violated by code is an implementation
  defect, not a reason to add the same requirement to the spec.
- When connecting existing functionality, start with calls to the existing
  mechanism in the owning use-case diagrams. Before adding a contract parameter,
  persistent field, separate specification document or error-handling mechanism,
  identify the requested or already binding requirement that existing elements
  cannot satisfy and explain that limitation. A hypothetical edge case alone
  does not justify expanding the scope. Review this necessity before checking
  the internal consistency of the expanded design.
- Define each rule once in its owning artifact. The use-case diagram owns the
  procedure; prose adds only information absent from it. Link to existing rules
  instead of restating them in SDD or arch.md. Architecture owns cross-service
  structure and system workflows, not local method behavior. A pattern or type
  need not be repeated as an enumeration of its implications.
- When the requested artifact is a template, provide the concrete template in
  its owning specification rather than prose instructions for constructing it.
  Explain only semantics that the artifact itself does not express.
- Check responsibility ownership as well as call edges. Transport and presentation
  behavior belongs to the relevant adapter; dependency contracts preserve their
  abstraction boundary. For example, download response headers belong to the HTTP
  endpoint, not the resource-access operation returning a file URL.
- Review existing STP coverage first. Add verification only for uncovered behavior,
  at the narrowest sufficient boundary. STP describes setup, stimulus and observable
  expectations by reference to the contract, without reproducing its prose.
  Client/E2E scenarios need a behavior that cannot be verified at a narrower boundary;
  do not assign new implementation or automated tests to clients outside project control.
- When removing redundancy, locate the surviving source of each binding rule.
  Preserve unique requirements, decisions and operational instructions; presence
  in derived code alone is not evidence that a specification rule is redundant.

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

Apply Specification review first. For mockups, use the browser-review exception
below. For project-selected direct spec editing, use the direct-write mode above.

The architect has **not** yet edited the spec. Do **not** write code.

1. **Diagnosis** — one line: artifact + section the request belongs to (SDD method, arch edge, mockup screen, DESIGN.md token, STP note). If it maps nowhere, say so. For a backend change: read that service’s SDD Contract and `docs/arch.md` first; decide whether the contract must move or only implementation. Do **not** read the service’s code until that strategy is set (zoom-in).
2. **Completeness** — verify the affected signature, use case, assumptions and STP coverage, and coherence with architecture and visual contracts. Existing content and coverage count; completeness does not require adding text or touching every artifact. Raise genuine gaps without inventing requirements.
3. **Propose** — the unified diff of the necessary specification changes (see **Docs proposal**). Do not edit `docs/` in this turn. End the turn.
4. **Coherence** — state that the touched artifacts agree. Wait for explicit "ok" / "approve" / "go" **of those hunks**.
5. **Write spec** — only after that acceptance, apply **Writing `docs/`**.
   Then **stop**. Do not implement.

Exception: purely mechanical fixes with no spec impact (build flag). If unsure, treat as spec.

### Writing `docs/`

Outside explicit direct-write mode and the mockup browser-review exception,
**never** create, overwrite, or patch anything under `docs/`
until the architect has accepted a unified diff you already showed **in a
previous turn**. Showing the diff and writing in the same turn is
forbidden. „Zrób docs” / „dopisz spec” without an accepted diff is
still: show the hunks, stop.

In diff-before-write mode, never write those files first.

1. Show the unified diff (see **Docs proposal**). End the turn.
2. Wait for explicit acceptance of **those hunks**
   ("ok" / "approve" / "go"). A later "ok" on a different question
   does not approve an unshown docs edit. Approving a description
   you never patched does not count.
3. Write **only** the accepted lines. Do not add beyond the diff.
   When this write is committed, tag tracker issues (see **Tracker
   issues in commits**).
4. Do not implement. Do not test. Do not start `axe sync` on your own.
   Approving docs is **not** a signal to code. **Stop.**
5. Code starts only when the architect says `axe sync` / „zsynchronizuj”.

This gate does **not** apply to entry B (`axe sync`): the architect
already changed `docs/`. Sync must still not invent extra spec.

Contract navigation: `## Contract` in `docs/<service>/sdd.md` links flat sibling `<rpc>.md` files, or contains complete inline methods for a small service. Shared types are in `docs/<service>/types.md`. `lib/contract/*.toml` is a generated projection—sync it only during entry B, never as a stand-in for the Markdown SDD.

#### Describe

If asked to describe something in `docs/`, write only information not already expressed by the contract or use case.
Prefer a link over repeated prose; retain the detail needed to define unique behavior.

### B. `axe sync` / „zsynchronizuj” / „zrób diffa docs”

The architect **already** changed `docs/`. You do not invent scope from chat. You compute the delta against freeze and implement that.

#### Execution configuration

Read optional **`<project-root>/axe.toml`** before sync. It is versioned execution configuration, outside `docs/` and the snapshots; changing it does not create an application delta. No file means local execution by the current agent, as before.

When present, read [execution configuration and delegation](references/execution.md). The current agent is the orchestrator; neither its model nor a worker model is hardcoded in this skill. Delegated execution starts only after Steps 0–3 establish a consistent delta. Workers implement assigned tasks; only the orchestrator integrates results, performs final verification, and updates freeze. A worker assignment is not an instruction to start another `axe sync`.

#### Step 0 — Snapshot

Before implementation, run the project's documented tool readiness target (for
DG: `make tools-check`). Resolve tools from project instructions and Makefile;
do not repeatedly search the web or package tree for installed executables.
Missing/broken tools block implementation until repaired. Do not silently skip
formatting or substitute an unverified formatter. Environment repair time is
reported separately from sync time.

Text files from `docs/` (`*.md`, `*.toml`, `*.html`, `*.css`, `*.js`, `*.json`) → `.axe/current/` (wipe the folder first, keep relative paths). Parse JSON. When an older freeze hashes text as an asset, compare its content hash before treating the representation change as product work.

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
- Every changed JSON file parses with a real JSON parser. When an affected SDD or contract Markdown links an OpenAPI JSON artifact, validate that artifact as part of the affected contract even if the JSON file itself is unchanged; check that its operations, schemas, required fields, and examples agree with the linked prose contract.
- For explicitly selected standalone TOML, apply the legacy contract reference
  instead of the Markdown extraction rules below.
- Every changed RPC spec contains one complete fenced TOML `[service.rpc]` signature and matching Request/Response prose. Local types are defined there; types referenced by multiple methods or another service are defined once in `types.md`.
- Extract all contract TOML fences for each affected service from `sdd.md`, its linked RPC Markdown (flat files; accept existing `methods/*.md` during migration), `types.md`, and explicitly linked contract-extension Markdown. Parse every fragment with a real TOML parser. Merge tables by fully qualified key, allowing repeated `[service.rpc]` table fragments only when their method keys are disjoint or identical. A message/type table has exactly one authored definition: reject duplicates even when textually identical. Also reject conflicting duplicate keys, unresolved named references (after checking primitives, the local service type catalog, and qualified referenced-service catalogs), malformed TOML, two RPC files defining the same method, and unlinked contract-bearing files.
- Compare the canonical merged result with `lib/contract/<Service>.toml` when it exists. A difference is projection work, not authority for changing Markdown.
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

For delegated execution, follow [the service task protocol](references/execution.md): give each affected service a separate worker session with a bounded task, then review the actual changes. Keep shared contract projection and integration explicitly owned by the orchestrator. Delegation does not change the spec gates, label rules, or success criteria below.

Only the delta. Follow IDesign. When contract fences change (or a repository-defined `[contract]` label applies), semantically merge the affected service contract into comment-free `lib/contract/<Service>.toml` and run the project contract build. Never concatenate TOML fragments as text. For standalone TOML, use the legacy contract reference. Write or update tests **only** when `[test]` — never alongside `[impl]` / `[contract]` / `[look]`. Add `@doc path/to.md` markers **only** when one code file realizes several docs (coarse regions). Do not wrap every block. Do not comment OCaml to explain domain — that lives in the spec.

Do not modify `docs/` during sync unless `tokens.css` must be regenerated from DESIGN.md (derived). If a spec is unrealizable, stop and report.

#### Step 5 — Verify

Use the project's make targets for build/test/format operations where required.
Record exact commands, exit codes and log paths. Required formatting must actually
run; visual resemblance to the formatter's style is not evidence. Missing tools,
failed required checks or unresolved test failures mean sync is not verified:
leave freeze unchanged. Calling a failure pre-existing requires baseline evidence
and does not itself waive the project's acceptance requirements.

Record elapsed time for planning, contracts, implementation, verification and
environment repair, plus total wall time in `.axe/last-sync.md`.

Run what the labels require. `[look]`: same viewport (default 1440×900), screenshot mockup and running app, compare layout / type / color / states. Fail on a clear miss; do not require bitwise PNG identity (font hinting, scrollbars). `[test]`: run the STP-derived tests you wrote or updated. Without `[test]`, do not add tests to make a suite green.

Failures → fix from the error description, still without changing docs. Repeat until checks pass or you must escalate a spec hole.

#### Step 6 — Freeze

Only after implementation **and** verification succeed:

```
rm -rf .axe/freeze
mv .axe/current .axe/freeze
```

A failed sync leaves freeze untouched so the next run sees the same delta.

`.axe/current/` is scratch (gitignore). `.axe/freeze/` is the last successful docs snapshot (text + ASSETS). Commit freeze if the project does; never commit PNG copies. That commit lists harvested issue tags (see **Tracker issues in commits**).

## Tracker issues in commits

Format: `#<n>` — the tracker-local id (Forgejo or any issue store). Take
`n` from the conversation (number, URL, user). Do not invent. No issue
in context → no tag. Write `#<n>` only; do not add `Fixes` / `Closes`.

**Spec.** The commit that records an accepted `docs/` write in an
issue-scoped chat includes that `#<n>`.

**Sync.** After freeze, find the last successful sync in git history,
then list every issue this delta implemented in code:

1. Last sync = latest commit that changed `.axe/freeze`. If freeze is
   not in git, latest commit whose subject starts with `axe sync:`.
   None → do not walk the whole history; keep only issue ids from this
   chat, if any.
2. `git log --no-merges --format='%s%n%b' <last-sync>..HEAD`. Collect
   unique `#<digits>` in first-seen order. Add any issue ids from this
   chat that are missing from that list.
3. Put those ids in the sync commit message. If freeze is not
   committed, start the subject with `axe sync:`.

## Before you touch code

1. `docs/main.md` — labels and map.
2. `docs/arch.md` — layers, call-graph, resources.
3. If the change is visual: `docs/mockup/DESIGN.md` and the owning `screens/*.html`.
4. `docs/<service>/sdd.md` (Contract is binding—follow its links to flat `<rpc>.md`, `types.md`, any explicit contract-extension Markdown, and linked OpenAPI JSON). Read every linked contract file for the affected service and parse linked JSON with a real JSON parser.
5. `docs/<service>/stp.md` when it exists and you touch covered behavior.
6. For a component: `docs/<client>/<name>.tag.md` (attrs / emits / use cases — not layout).
7. WELL: `lib/contract/<Service>.toml` only as a cross-check; SDD wins.

Missing artifact → say so. Do not infer a contract from code.

## What goes in `sdd.md`

Strict black-box:

1. **Role**
2. **Abstraction boundary**
3. **Contract** — normally an index in `sdd.md` linking flat `docs/<service>/<rpc>.md` files. Each method file contains its complete fenced TOML `[service.rpc]` signature, Request, Response, use case/activity diagram, and method-local types. Types used by multiple methods or exported through qualified cross-service references live once in `docs/<service>/types.md` and are linked from those methods. A small service may define complete methods inline in `sdd.md`. Markdown remains the only authored contract source.
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

### Mockup changes — browser review

When the user requests mockup changes, edit `docs/mockup/` directly.
This includes screen HTML, mockup CSS/JS/assets, navigation and the
supporting visual rules in DESIGN.md. Do not show HTML diffs or ask for
diff approval: the user reviews the saved mockup in the browser.
Verify the affected screens in the browser and provide their preview URL.
This exception overrides entry A's proposal/STOP steps and the `docs/`
writing gate only for mockup artifacts. Changes to service specs,
contracts, STP or application code keep their existing workflow.
Saving or visually approving a mockup does not authorize `axe sync`.

- `docs/mockup/` is documentation, not a frontend to ship.
- DESIGN.md is the visual source of truth. `tokens.css` is derived for the HTML pencil.
- New recurring control = named component in DESIGN.md, then a semantic class, then use on a screen.
- Utility-soup in a screen is a sketch, not a contract. Implementation (including Flutter) reads DESIGN.md + the rendered screen.
- One file per screen or per state (`planner-meta-list.html`, not one form with hidden sections as the spec).
- Do not `@import` the application's `static/design-tokens.css`.

## Source of truth

`docs/` (main, arch, DESIGN.md, screens, SDD/contracts, STP, tags) is binding. Code and generated TOML conform. When code disagrees: report. Default is fix the code. Never change the spec on your own; the architect decides if the spec should move.

## No code comments

Never add comments in source. Domain and architecture live in `docs/`. `@doc` markers are identifiers, not explanations.

## IDesign layering

Apply the loaded `idesign-architecture` skill for layer and interaction rules.
The project architecture records the actual components and edges.

## Use cases vs workflows

| Term | Meaning | Where |
|---|---|---|
| Use case | One Manager call | Activity diagram on that method in the SDD (`sdd.md` inline, or flat `<rpc>.md`) |
| Workflow | Sequence of use cases | `sdd.md` Scenarios (one service) or `arch.md` (system-wide) |

## Worked examples

**Chat:** "Add FileManager.ArchiveClosedCases."
Read IDesign and existing contracts → Specification review → propose only the necessary contract/behavior changes. Update the index or STP only if the new method requires it. Follow the project review mode, then **STOP**. An issue-scoped spec commit includes `#12`.

**Small correction:** restrict the alphabet of an issued code. Change its owning contract to specify the pattern. If existing STP already covers the required error behavior, leave it unchanged; do not add a screen or client tests unless the requested behavior requires them.

**Sync:** architect says `axe sync` (or already edited `docs/`).
`axe sync` → diff vs freeze → change list → implement matching UI/code → `[look]` in the browser → freeze. The sync commit lists `#12 #18` harvested from commits since last freeze.
