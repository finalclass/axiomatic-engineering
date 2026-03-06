# Axiomatic Engineering

A framework for building software systems from declarative specifications — not code.

## The idea

You don't write code. You write **axioms** — plain-language statements that define what your system does. An AI-powered sync process reads your axioms and generates (or updates) the codebase to match. When requirements change, you edit the axioms and re-sync. The code follows.

```
/  ← you work here (source of truth)
_generated/  ← generated code (derived artifact)
```

This inverts the traditional workflow. Instead of translating requirements into code by hand, you maintain a living specification that compiles into a working system. The axioms are the project — the code is a build artifact.

## Why "axioms"?

In mathematics, axioms are foundational truths from which everything else is derived. In this framework, axioms are foundational **decisions** — made by you, your client, or a regulatory body — from which all code is derived.

An axiom is non-negotiable during sync. The sync process never questions an axiom; it makes the code comply. If the code can't comply, that's a signal the axiom needs human attention — not that the code should silently deviate.

## Who is this for?

Software architects who understand that the hard part of building systems is not writing code — it's deciding what the system should do and keeping the implementation faithful to those decisions over time.

If you think AI is a better autocomplete for writing loops, this framework is not for you. If you think AI can take over the translation from specification to code while humans focus on specification, design, and verification — read on.

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

## Relation to Spec-Driven Development

Axiomatic Engineering is related to what the industry calls Spec-Driven Development (SDD). In mid-2025, major players entered this space: Amazon launched Kiro (a spec-first IDE), GitHub released spec-kit (an open-source SDD toolkit), and Tessl launched a spec-driven framework. Birgitta Böckeler from Thoughtworks analyzed these tools and identified three levels of SDD: spec-first (specification written before code, then abandoned), spec-anchored (specification maintained alongside code), and spec-as-source (specification is the only artifact edited by humans — code is a derived build artifact).

Most existing tools operate at the spec-first level. Axiomatic Engineering operates at the spec-as-source level, with concrete mechanisms that make this practical: freeze/diff for incremental sync, labels for pluggable verification aspects, @axiom markers for traceability, and modular namespacing.

## Axiom format

**One file = one axiom.** Each axiom is a Markdown file describing one cohesive concern: a page, a feature, a technology stack, a data protection policy. The main `axioms.md` file is the system map — it contains the glossary, label definitions, and links to all axiom files.

**Labels** are pluggable verification aspects. They define what kind of verification an axiom requires. Labels are declared in the `## Labels` section of `axioms.md` and applied to axioms.

Label placement follows a **cascade** (like CSS):
- Label on `#` heading (top of file) → applies to entire file
- Label on `##` section → applies to that section
- Sections inherit labels from the file level

Example:

```markdown
# Data protection
[rodo]

Patients can export their data in a structured format.
Patients can delete their account and all associated data.

## Technical security
[pentest] [test]

Passwords are hashed with bcrypt or argon2.
Data at rest is encrypted. Communication via HTTPS only.
Access to sensitive data requires 2FA.

## Privacy policy
[ux-validate]

The system displays privacy policy before registration.
```

In this example: the entire file has `[rodo]`. The "Technical security" section has `[rodo] [pentest] [test]` (inherited + own). The "Privacy policy" section has `[rodo] [ux-validate]`.

**Narrative over checklists.** Axiom files describe pages, features, or rules narratively — as you would explain them to a colleague. They are NOT decomposed into atomic checklist items. The sync process reads the natural language description and generates code accordingly.

**Modular namespacing.** Axioms live in files organized by domain. Each file is a namespace. An axiom's full identifier is its file path plus optional anchor: `patient-client/booking.md` or `data-protection.md#technical-security`. This is the same format as a standard Markdown link — one convention, zero translation between references, code markers, and links.

**Glossary** (`## Słownik` / `## Glossary`) contains domain term definitions. Glossary entries are NOT axioms — they don't generate code or tests. They exist to ensure shared understanding of domain language between stakeholders and AI.

## @axiom markers

Every piece of generated code is annotated with markers pointing back to the axiom it implements:

```html
<!-- @axiom: login-client/login.md -->
<div class="login-form">
  ...entire login page...
</div>
<!-- /@axiom: login-client/login.md -->
```

Rules:
- Every opening marker must have a matching closing marker
- Markers can be nested (e.g., a registration form containing a privacy policy checkbox)
- Marker names must correspond to existing axiom files/sections
- Test files don't require markers
- Format varies by language: HTML uses `<!-- -->`, JS uses `//`, CSS uses `/* */`, Bash uses `#`

## How sync works

The sync process (`/axioms-sync`) is the compiler of axiomatic engineering. It reads axioms, compares them against the last known state (freeze), generates a change list, implements changes, and verifies the result.

Workflow: edit axioms → run sync → code updates.

The sync operates in two modes:
- **Diff mode** (default): only axioms changed since last sync are processed
- **Full mode** (`--full`): all axioms are reprocessed

Key steps: read axioms → check consistency → generate change list → implement changes → verify (tests, linters, label requirements) → repeat until everything passes.

For the complete sync procedure, see [axioms-sync.md](./axioms-sync.md).

## Architecture and AI

Good software architecture remains valuable in the age of AI-generated code, but the reason shifts. Traditional architecture (like volatility-based decomposition from IDesign Method) aims to minimize the cost of human-driven changes. With axiomatic engineering, AI handles the changes — but it benefits from architecture even more than humans do.

A well-decomposed system gives the AI agent small, closed problems with minimal context. Instead of reasoning about a 10,000-line monolith, the agent works within a 2,000-line service with clear contracts. This produces better results because AI is more sensitive to context size than humans.

The practical rule: decompose for AI comprehensibility. Small services with clear contracts and atomic business verbs (not CRUDs) at the boundaries. For volatility-based decomposition, [idesign-architect](https://github.com/finalclass/idesign-architect) works well with this approach.

## Example

See the [example/](./example/) directory for a simplified project demonstrating the axiom format, label cascade, namespacing, and generated code with @axiom markers.

## License

MIT
