# Axiomatic Engineering

A framework for building software systems from declarative specifications — not code.

## The idea

You don't write code. You write **axioms** — plain-language statements that define what your system does. An AI-powered sync process reads your axioms and generates (or updates) the codebase to match. When requirements change, you edit the axioms and re-sync. The code follows.

```
axioms/     ← you work here (source of truth)
axioms/main.md  ← entry point (system map)
code/       ← generated code (derived artifact)
data/       ← runtime data (databases, uploads, etc.)
.axioms/    ← sync working directory (freeze, snapshots)
```

This inverts the traditional workflow. Instead of translating requirements into code by hand, you maintain a living specification that compiles into a working system. The axioms are the project — the code is a build artifact.

## Why "axioms"?

In mathematics, axioms are foundational truths from which everything else is derived. In this framework, axioms are foundational **decisions** — made by you, your client, or a regulatory body — from which all code is derived.

An axiom is non-negotiable during sync. The sync process never questions an axiom; it makes the code comply. If the code can't comply, that's a signal the axiom needs human attention — not that the code should silently deviate.

## Who is this for?

Software architects who understand that the hard part of building systems is not writing code — it's deciding what the system should do and keeping the implementation faithful to those decisions over time.

If you think AI is a better autocomplete for writing loops, this framework is not for you. If you think AI can take over the translation from specification to code while humans focus on specification, design, and verification — read on.

## Design principles

**Specification is the product.** Code is derived. If your axioms are precise and complete, the generated code is correct. If the code has a bug, the axiom is incomplete — you fix the axiom, not the code. This applies to every kind of change without exception: new features, bug fixes, UI adjustments, refactors, dependency updates. The workflow is always: edit the axiom first, then sync. Never touch code directly.

**Progressive refinement.** You never leave the framework to fix code — you refine the axiom. Axioms exist on a natural gradient of specificity:

1. General intent — *"The login page has an email and password field."*
2. Detailed description — *"The password field requires minimum 8 characters. Validation errors appear below the field in red."*
3. Specific instruction — *"Use a generic error message for failed login to prevent account enumeration."*
4. Literal code — a code block in the axiom with the exact implementation to use.

When the AI misinterprets an axiom, you don't bypass the framework — you move one level down the gradient. Add more detail, add verification labels, and if precision demands it, embed the exact code in the axiom with an explanation of *why* it must be exactly that way. The axiom always remains the source of truth, whether it describes intent in a sentence or specifies `padding-left: 3px` in a code block.

This gradient is self-correcting: each iteration makes the specification more precise. Instead of escaping the framework when it produces wrong code, you deepen it — and the next sync gets it right.

**Layered verification.** Axioms can carry labels — `[test]`, `[security]`, `[e2e]`, `[ux]`, `[rodo]` — that define what kind of verification each axiom requires. Verification happens across three phases: deterministic tools and tests (`@validation`), AI-powered subjective evaluation (`@satisfaction`), and compile-time type checking. The combination creates a multi-layered safety net where each layer catches a different class of errors — from type mismatches to UX problems that no test can express.

**Labels as verification pipelines.** A label is not just a tag — it is a declarative verification pipeline. The engineer defines *how* each label is verified: which static analysis tools to run, which AI model to use for review, what specific concerns to check for. The label definition is the engineer's primary lever for ensuring code quality. A well-designed label catches what the generating agent misses.

**Label phases.** Each label declares its visibility in the pipeline using phase annotations: `@implementation`, `@validation`, `@satisfaction(threshold)`, or a combination. Phases control *when* an agent runs:

- `@implementation` — visible to the implementing agent (code generation)
- `@validation` — visible to the validating agent (deterministic verification)
- `@satisfaction(threshold)` — visible to the AI judge agent (subjective evaluation of the running application). The threshold is the minimum required score (0.0–1.0), defaulting to 0.7 if omitted: `@satisfaction` = `@satisfaction(0.7)`. The threshold can be a number or a **glossary key** — e.g., `@satisfaction(satisfaction-level)` looks up `**satisfaction-level**` in the glossary. This lets you define the threshold once and reference it across labels.
- Both `@implementation @validation` — visible to both (e.g., `[test]` for TDD: tests written during implementation, then verified)
- `@validation` only — **holdout**: hidden from the implementing agent entirely. The agent builds software without knowing these validation criteria. This works like a holdout set in machine learning — preventing the agent from optimizing for test passage rather than building correct software.
- `@satisfaction` only — the scenario does not generate code or tests. It is a prompt for an AI judge that interacts with the running application and evaluates it subjectively (UX, readability, intuitiveness, overall quality). The judge returns a score (0.0–1.0) instead of pass/fail.

Every label must declare at least one phase. A label without a phase annotation is an error caught during consistency checking.

**Context markers (`+`).** Each label also declares *what* its agent receives using `+` markers after the phase annotations. Every agent always receives its own axiom. Available markers:

- `+code` — access to source code in `code/`
- `+axioms` — access to all axioms (not just its own)
- `+browser` — access to a browser / running application (browser automation)
- `+api` — access to HTTP endpoints (curl, requests)

No markers = the agent receives only its axiom and label instructions. This is a security mechanism: an agent without `+code` cannot cheat by inspecting implementation details — it must evaluate behavior from the outside.

Each label runs as a **separate agent** with its own context during verification. The verifying agent sees only the resources granted by its `+` markers — never the generating agent's reasoning. This isolation prevents tautological verification (the same model "confirming" its own work). For stronger guarantees, labels can specify a different model than the one used for code generation.

```markdown
### [security] @validation +code +api
model: opus
1. Run `semgrep --config=p/owasp-top-ten` on changed files
2. Agent review: check for injection, auth bypass, data exposure
3. If backend: run `sqlmap` on endpoints

### [test] @implementation @validation +code
Unit tests. Written before implementation (TDD).

### [e2e] @validation +browser
End-to-end scenarios. Validated against the running application
after implementation — the implementing agent never sees these.

### [perf] @validation +code
1. Run benchmark suite: `make bench`
2. Agent review: check for N+1 queries, unbounded loops, missing indexes
3. Compare results against baseline from previous sync

### [arch] @validation +code +axioms
Architecture review. Checks decomposition, service contracts,
and layer boundaries against the system's architectural rules.

### [ux] @satisfaction(satisfaction-level) +browser
AI judge opens the application in a browser, performs the described
scenario, and evaluates usability, readability, and intuitiveness.

### [scenario] @validation @satisfaction(satisfaction-level) +browser
When an employee accepts an order, the owner sees it in
their dashboard within 3 seconds.
```

The three phases form a complete pipeline: `@implementation` builds the code, `@validation` verifies it deterministically (pass/fail), and `@satisfaction` evaluates the running application subjectively (score 0.0–1.0). A scenario can span multiple phases — for example, `@validation @satisfaction` first runs a deterministic holdout test, then has the AI judge evaluate the same behavior qualitatively.

**Deterministic tools first.** The strongest verification pipelines maximize the use of deterministic tools — linters, type checkers, static analyzers, benchmark suites, OWASP scanners — and use AI agents only for what deterministic tools cannot catch (semantic review, intent matching, architectural judgment). A label that runs `semgrep` + `sqlmap` + an AI review is stronger than one that relies on AI review alone, because deterministic tools have zero hallucination rate. The ideal label pipeline is: deterministic tools catch the known classes of errors, AI agent catches the rest.

The engineer's role shifts from reviewing code line-by-line to designing verification pipelines and interpreting their results.

**Loose syntax, strict semantics.** Axioms are written in Markdown — readable by developers, clients, and regulators. No formal DSL required. LLMs can parse intent from natural language; you don't need rigid structure for machine-readability anymore. Precision comes from the verification layer (types, tests, labels), not from the specification format.

**Traceability by design.** Every line of generated code is annotated with `@axiom` markers pointing back to the axiom it implements. You always know *why* a piece of code exists.

**Nothing gets lost.** In a typical prompt-driven workflow, each conversation is a narrow window — an AI sees the current request and the code in front of it, but has no awareness of decisions made in previous sessions. A prompt that says "add feature X" can silently overwrite or break feature Y that was introduced three prompts ago. There is no mechanism to prevent it; the earlier intent simply isn't part of the context anymore.

Axioms solve this by treating the entire specification as a single, always-present whole. When the sync process runs, it doesn't see "the latest change" — it sees *every* axiom simultaneously. Adding a new axiom cannot erase an existing one, because the existing one is still there, still required, still enforced. If two axioms conflict, the consistency check catches it *before* any code is generated. The system makes regression structurally difficult rather than relying on the developer to remember what was built before.

This is the fundamental difference between "programming by prompting" and programming by specification: prompts are ephemeral, axioms are cumulative.

**Modular namespacing.** Axioms live in the `axioms/` directory, organized by domain. Each file is a namespace. An axiom's full identifier is its file path (relative to `axioms/`) plus anchor: `patient-panel/booking.md#visit-reservation`. This is the same format as a standard Markdown link — one convention, zero translation.

## A note on the future

Every industrial revolution eventually produces regulation. Steam engines led to boiler codes. Construction led to structural engineering licenses and standards like Eurocode. Software has largely avoided this — but as AI makes it possible for anyone to build and ship production systems, the pressure for professional accountability will grow.

When that happens, regulations will look like axioms: formalized rules that a system must satisfy. In this framework, a regulatory package is just a set of axiom files you import into your project — the same format, the same sync process, the same verification. Your custom business logic and legally mandated requirements live side by side as equals.

Axiomatic Engineering is designed with this future in mind.

## Relation to Spec-Driven Development

Axiomatic Engineering is related to what the industry calls Spec-Driven Development (SDD). In mid-2025, major players entered this space: Amazon launched Kiro (a spec-first IDE), GitHub released spec-kit (an open-source SDD toolkit), and Tessl launched a spec-driven framework. Birgitta Böckeler from Thoughtworks analyzed these tools and identified three levels of SDD: spec-first (specification written before code, then abandoned), spec-anchored (specification maintained alongside code), and spec-as-source (specification is the only artifact edited by humans — code is a derived build artifact).

Most existing tools operate at the spec-first level. Axiomatic Engineering operates at the spec-as-source level, with concrete mechanisms that make this practical: freeze/diff for incremental sync, labels for pluggable verification aspects, @axiom markers for traceability, and modular namespacing.

## Axiom format

**One file = one axiom.** Each axiom is a Markdown file describing one cohesive concern: a page, a feature, a technology stack, a data protection policy. All axiom files live in the `axioms/` directory. The entry point `axioms/main.md` is the system map — it contains the glossary, label definitions, and links to all axiom files.

**Labels** are pluggable verification aspects with phase annotations (`@implementation`, `@validation`, `@satisfaction`) and context markers (`+code`, `+browser`, `+api`, `+axioms`). Phases define *when* an agent runs; markers define *what* it receives. Labels are declared in the `## Labels` section of `main.md` and applied to axioms.

Label placement follows a **cascade** (like CSS):
- Label under `## Aksjomaty` in `main.md` → applies to all axioms (global)
- Label on `#` heading (top of axiom file) → applies to entire file
- Label on `##` section → applies to that section
- Each level inherits labels from the level above

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

**Modular namespacing.** Axioms live in the `axioms/` directory, organized by domain. Each file is a namespace. An axiom's full identifier is its file path (relative to `axioms/`) plus optional anchor: `patient-client/booking.md` or `data-protection.md#technical-security`. This is the same format as a standard Markdown link — one convention, zero translation between references, code markers, and links.

**Glossary** (`## Słownik` / `## Glossary`) contains domain term definitions. Glossary entries are NOT axioms — they don't generate code or tests. They exist to ensure shared understanding of domain language between stakeholders and AI. Glossary entries can also hold **configuration values** referenced by labels — e.g., `**satisfaction-level** — 0.7` can be referenced as `@satisfaction(satisfaction-level)`. One place to change when moving from mockup to production thresholds.

## @axiom markers

Generated code is wrapped in block-level markers pointing back to the axiom it implements:

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
- **Diff mode** (default): only axioms changed since last sync are processed. The sync maintains a freeze snapshot (`.axioms/freeze/`) to detect what changed since the last run.
- **Full mode** (`--full`): all axioms are reprocessed regardless of freeze state.

Axiom files are loaded by following the link chain from `main.md` — only files reachable through links are included in the sync.

The sync process follows an **orchestrator pattern**. The main process handles planning (snapshot, diff, reading axioms, consistency checks, change list generation, marker verification) and then delegates execution to isolated agents:

- **Implementing agent** — receives axioms filtered to `@implementation` labels only. Blocks carrying `@validation`-only or `@satisfaction`-only labels are stripped from its context. Builds code and writes tests for `@implementation` labels.
- **Validating agent(s)** — one per label, each receiving only the resources declared by its `+` markers. An agent with `+code` reviews source code; one with `+browser` tests the running application; one without either evaluates behavior from the outside.
- **Satisfaction agent (AI judge)** — receives `@satisfaction` scenarios as prompts and resources per `+` markers. Evaluates the application subjectively, returning a score (0.0–1.0) with justification. Score must meet the threshold from `@satisfaction(threshold)` or the cycle repeats.

If validation or satisfaction review fails, the implementing agent receives the error/feedback description but still never sees holdout or satisfaction blocks — it must fix the issue based on the description alone. The cycle repeats until all checks pass.

**Declarative axioms.** Some axioms describe rules, architecture, or exclusions that have no direct representation in code. These axioms don't require `@axiom` markers in generated files.

**Batch processing.** When the number of axioms to process is large (>20), the sync splits work into batches — consistency checking runs on the full set, but implementation proceeds one axiom at a time.

For the complete sync procedure, see [axioms-sync.md](./axioms-sync.md).

## Architecture and AI

Good software architecture remains valuable in the age of AI-generated code, but the reason shifts. Traditional architecture (like volatility-based decomposition from IDesign Method) aims to minimize the cost of human-driven changes. With axiomatic engineering, AI handles the changes — but it benefits from architecture even more than humans do.

A well-decomposed system gives the AI agent small, closed problems with minimal context. Instead of reasoning about a 10,000-line monolith, the agent works within a 2,000-line service with clear contracts. This produces better results because AI is more sensitive to context size than humans.

The practical rule: decompose for AI comprehensibility. Small services with clear contracts and atomic business verbs (not CRUDs) at the boundaries. For volatility-based decomposition, [idesign-architect](https://github.com/finalclass/idesign-architect) works well with this approach.

## Example

See the [example/](./example/) directory for a simplified project demonstrating the axiom format, label cascade, namespacing, and generated code with @axiom markers.

## License

MIT
