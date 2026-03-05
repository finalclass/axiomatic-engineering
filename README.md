# Axiomatic Engineering

A framework for building software systems from declarative specifications — not code.

## The idea

You don't write code. You write **axioms** — plain-language statements that define what your system does. An AI-powered sync process reads your axioms and generates (or updates) the codebase to match. When requirements change, you edit the axioms and re-sync. The code follows.

```
axioms/  ← you work here (source of truth)
_generated/  ← generated code (derived artifact)
```

This inverts the traditional workflow. Instead of translating requirements into code by hand, you maintain a living specification that compiles into a working system. The axioms are the project — the code is a build artifact.

## Why "axioms"?

In mathematics, axioms are foundational truths from which everything else is derived. In this framework, axioms are foundational **decisions** — made by you, your client, or a regulatory body — from which all code is derived.

An axiom is non-negotiable during sync. The sync process never questions an axiom; it makes the code comply. If the code can't comply, that's a signal the axiom needs human attention — not that the code should silently deviate.

## Who is this for?

Software architects who understand that the hard part of building systems is not writing code — it's deciding what the system should do and keeping the implementation faithful to those decisions over time.

If you think AI is a better autocomplete for writing loops, this framework is not for you. If you think AI can take over the translation from specification to code while humans focus on specification, design, and verification — read on.

## Relation to Spec-Driven Development

Axiomatic Engineering is related to what the industry calls [Spec-Driven Development](https://www.speakeasy.com/post/spec-driven-development) — the practice of writing a formal specification first and deriving implementation from it. SDD typically means an API spec (OpenAPI, GraphQL schema) that drives code generation and contract testing.

Axiomatic Engineering takes this further. The specification isn't just a contract — it's the **source of truth** that replaces hand-written code entirely. Axioms are not limited to API shapes; they describe business logic, UI behavior, security constraints, and regulatory requirements — all in plain language, all generating code through the same sync process. And every line of generated code traces back to the axiom that requires it, with a layered verification system (`[test]`, `[security]`, `[e2e]`) that ensures each axiom is not just implemented but *proven* compliant.

Where SDD stops at "spec first, then code", Axiomatic Engineering says: spec *is* the codebase.

## Design principles

**Specification is the product.** Code is derived. If your axioms are precise and complete, the generated code is correct. If the code has a bug, the axiom is incomplete — you fix the axiom, not the code.

**Layered verification.** Axioms can carry labels — `[test]`, `[security]`, `[e2e]`, `[rodo]` — that define what kind of verification each axiom requires. A strict type system (e.g. OCaml) adds another verification layer at compile time. The combination of typed languages, labeled tests, and AI-powered sync creates a multi-layered safety net where each layer catches a different class of errors.

**Loose syntax, strict semantics.** Axioms are written in Markdown — readable by developers, clients, and regulators. No formal DSL required. LLMs can parse intent from natural language; you don't need rigid structure for machine-readability anymore. Precision comes from the verification layer (types, tests, labels), not from the specification format.

**Traceability by design.** Every line of generated code is annotated with `@axiom` markers pointing back to the axiom it implements. You always know *why* a piece of code exists.

**Nothing gets lost.** In a typical prompt-driven workflow, each conversation is a narrow window — an AI sees the current request and the code in front of it, but has no awareness of decisions made in previous sessions. A prompt that says "add feature X" can silently overwrite or break feature Y that was introduced three prompts ago. There is no mechanism to prevent it; the earlier intent simply isn't part of the context anymore.

Axioms solve this by treating the entire specification as a single, always-present whole. When the sync process runs, it doesn't see "the latest change" — it sees *every* axiom simultaneously. Adding a new axiom cannot erase an existing one, because the existing one is still there, still required, still enforced. If two axioms conflict, the consistency check catches it *before* any code is generated. The system makes regression structurally difficult rather than relying on the developer to remember what was built before.

This is the fundamental difference between "programming by prompting" and programming by specification: prompts are ephemeral, axioms are cumulative.

**Modular namespacing.** Axioms live in files organized by domain. Each file is a namespace. An axiom's full identifier is its file path plus anchor: `patient-panel/booking.md#visit-reservation`. This is the same format as a standard Markdown link — one convention, zero translation.

## A note on the future

Every industrial revolution eventually produces regulation. Steam engines led to boiler codes. Construction led to structural engineering licenses and standards like Eurocode. Software has largely avoided this — but as AI makes it possible for anyone to build and ship production systems, the pressure for professional accountability will grow.

When that happens, regulations will look like axioms: formalized rules that a system must satisfy. In this framework, a regulatory package is just a set of axiom files you import into your project — the same format, the same sync process, the same verification. Your custom business logic and legally mandated requirements live side by side as equals.

Axiomatic Engineering is designed with this future in mind.

## How it works

### Project layout

```
axioms.md                  ← main axiom file (entry point)
technology.md              ← technology decisions
data-protection.md         ← regulatory/privacy axioms
ui-template.html           ← UI reference template
landing-client/            ← axioms per client (IDesign decomposition)
_generated/                ← all code lives here (derived artifact)
.axioms-freeze/            ← snapshot from last sync (for diffing)
```

You work in the root. The `_generated/` folder is the compiler output.

### Axiom format

Axioms are plain Markdown. The structure:

```markdown
# System Name

## Dictionary
- **Term** — domain definition...

## Labels
### [test]
Instructions for the test label...

### [security]
Instructions for the security label...

## Axioms
### Group Name
#### Axiom Name
[test] [security]
The axiom's content — what the system must do.
```

- An axiom is a heading 4 (`####`) with a human-readable name.
- Labels in brackets (`[test]`, `[security]`, `[e2e]`) define required verification.
- References between axioms use standard Markdown links: `[Other Axiom](#anchor)`.
- Namespace ID: `file-path#heading-slug` (e.g. `patient-client/booking.md#visit-reservation`).

The Dictionary section defines domain terms — it is not implemented, only used for understanding.

### The sync process

Run `/axioms-sync` in Claude Code or any other agentic cli. The process:

1. **Freeze & diff** — compares current axioms against `.axioms-freeze/` to find what changed. First run treats everything as new. Use `--full` to force a complete sync.
2. **Load axioms** — reads `axioms.md`, follows all `[Link](./file.md)` includes recursively, parses axioms, labels, and references.
3. **Consistency check** — detects contradictions, broken references, duplicate names. Stops on error.
4. **Change list** — for each changed axiom, determines what code in `_generated/` needs to change. Labels add requirements: `[test]` means tests must be written, `[security]` means a security review is needed.
5. **Marker validation** — every piece of generated code is wrapped in `@axiom` markers that trace back to the source axiom. The sync validates marker pairing, naming, and checks for orphaned code.
6. **Implementation** — generates or updates code in `_generated/`, one axiom at a time. For `[test]` axioms, tests are written first (TDD).
7. **Verification** — runs tests, linters, and other checks required by labels. Repeats until everything passes.

### @axiom markers

Every line of generated code is annotated with markers pointing to its source axiom:

```html
<!-- @axiom: patient-client/booking.md#visit-reservation -->
<form>...</form>
<!-- /@axiom: patient-client/booking.md#visit-reservation -->
```

Markers can nest — e.g. a registration form axiom containing a data protection consent axiom inside it. This gives you full traceability: for any piece of code, you know exactly which axiom requires it.

### Labels as a verification layer

Labels are the mechanism for attaching verification requirements to axioms. i/e:

| Label                  | Effect                                                |
|------------------------|-------------------------------------------------------|
| `[test]`               | Unit tests required (TDD — tests written before code) |
| `[e2e]`                | End-to-end test covering the full flow                |
| `[security]`           | Security review                                       |
| `[architecture-check]` | Architecture verification                             |
| `[ux-validate]`        | UI/UX validation                                      |

An axiom marked `[test]` is not satisfied until its tests exist and pass. The label system is extensible — you define labels and their instructions in the axiom file itself.

### Declarative axioms

Some axioms describe constraints, architecture decisions, or exclusions rather than features. These don't produce code and don't need `@axiom` markers — but they guide the sync process. Examples: "no mobile app", "use SQLite", "encrypt data at rest".

## Getting started

### Installation

To use Axiomatic Engineering in your project, copy these files into your repo:

1. **`command/axioms-sync.md`** — the sync command. Copy it to `.claude/commands/axioms-sync.md` in your project so Claude Code registers it as `/axioms-sync`.
2. **`test-axioms.sh`** — the marker validation script (see below). Place it at `_generated/tests/test-axioms.sh`.

Then create your axiom files in the project root (`axioms.md`, `technology.md`, etc.) and run `/axioms-sync` in Claude Code.

### The sync command

The sync process lives in `command/axioms-sync.md`. Copy it to `.claude/commands/axioms-sync.md` in your project so Claude Code registers it as the `/axioms-sync` command. It reads your axioms and generates (or updates) the code in `_generated/`.

- `/axioms-sync` — diff-based sync (only changed axioms since last run).
- `/axioms-sync --full` — full sync (all axioms, ignoring previous state).

### test-axioms.sh — marker validation

`test-axioms.sh` is a standalone bash test runner that validates the structural integrity of generated code. It checks that:

- Every file in `_generated/` has `@axiom` markers.
- Every opening marker (`@axiom: X`) has a matching closing marker (`/@axiom: X`).
- Every marker reference points to an axiom that actually exists in the axiom files.
- No orphaned code exists inside `{{content}}` blocks outside of `@axiom` markers.

Run it after sync to catch structural problems:

```bash
bash test-axioms.sh
```

The script is format-aware — it handles HTML (`<!-- @axiom -->`), JS/PHP (`// @axiom`), CSS (`/* @axiom */`), and bash (`# @axiom`) markers. It also handles Polish diacritics in axiom names by generating both Unicode and ASCII-transliterated slugs for matching.

You can extend the `=== PROJECT-SPECIFIC TESTS ===` section at the bottom of the script with your own assertions using the built-in helpers: `file_exists`, `has_layout`, `has_text`, `has_element`, `has_axiom_markers`, `has_matched_markers`, `has_valid_axiom_refs`, `has_no_orphaned_content`.

### Bonus: IDesign architecture skill

This repo includes `idesign-architecture` — a Claude Code skill based on Juval Lowy's IDesign Method ("Righting Software"). It helps with volatility-based system decomposition, layered architecture design, and service contract definition.

IDesign pairs naturally with Axiomatic Engineering: use `idesign-architecture` to design your system's structure (managers, engines, accessors, utilities), then express that structure as axioms and let the sync process generate the code.

The skill is available as a Claude Code agent skill — once installed, it activates automatically when you discuss system architecture, decomposition, service boundaries, or anti-patterns.

### Example

The `example/` folder contains a complete working example — a vanilla JS todo app with localStorage persistence. It demonstrates the full workflow: axioms as input, generated code as output, `@axiom` markers for traceability, and browser-based tests for `[test]`-labeled axioms.

## Core rules

- **Never edit axioms during sync.** Axioms are the source of truth.
- **If an axiom can't be implemented, report it.** Don't work around it silently.
- **No test = not compliant.** If an axiom has `[test]`, code without a passing test violates it.
- **One axiom, one commit.** Small, atomic changes for traceability.
