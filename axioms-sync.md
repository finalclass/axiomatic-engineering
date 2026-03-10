# Syncing axioms with code

## Philosophy

The developer works on axioms, not on code. Axioms are a declarative description of the system — the source of truth. Code is derived from axioms.

Workflow: edit axioms → run `/axioms-sync` → code updates.

## Directory structure

- `axioms/` — system axioms (where the developer works): `main.md` (entry point), `technology.md`, `data-protection.md`, `ui-template.html`, and `*-client/` folders (e.g., `landing-client/`, `login-client/`, `patient-client/`, `therapist-client/`, `admin-client/`)
- `code/` — system code (generated from axioms). Create if it doesn't exist.
- `data/` — runtime data (databases, uploads, etc.). Not managed by sync.
- `.axioms/` — sync working directory (temporary files, snapshots). Create if it doesn't exist.
  - `.axioms/current/` — copy of axioms from the current run (created at sync start)
  - `.axioms/freeze/` — snapshot of axioms from the last sync (for diffs)

Your task: bring the code in `code/` into compliance with the axioms.

## Axiom format

### Main file: `axioms/main.md`

`axioms/main.md` is the system map — it contains the glossary, label definitions, and links to axiom files. It does NOT contain axioms itself.

Structure:
```
# System name

## Glossary
- **Term** — definition of concept...
- **satisfaction-level** — 0.7

## Labels
### [test] @implementation @validation +code
Description/instructions for the test label

### [scenario] @validation +browser
Behavioral scenarios. Validated after implementation.

### [security] @validation +code +api
Description/instructions for the security label

### [ux] @satisfaction(satisfaction-level) +browser
Interface usability verification.

## Axioms
[lint]
- [Data protection](./data-protection.md)
- [Booking](./patient-client/booking.md)
```

"## Glossary" section:
- Contains domain term definitions in the format `**Term** — description`
- Glossary entries are NOT axioms — do not generate changes, tests, or implementations for them
- The glossary serves to understand the meaning of terms used in axioms
- **Glossary values in labels:** If the `@satisfaction()` argument is not a number, treat it as a glossary key. E.g., `@satisfaction(satisfaction-level)` → looks up `**satisfaction-level**` in the glossary and uses its numeric value. If the key doesn't exist in the glossary — consistency error (Step 2).

"## Labels" section:
- Label definitions in the format `### [label-name] @phases...`
- Each label has a description/instructions below the heading
- Labels define the required action for an axiom (e.g., writing tests, security review)
- A label can define a verification pipeline: specific commands to run, AI model to use, static tools
- **Label phases:** After the label name in the heading, one or more phases are specified: `@implementation`, `@validation`, `@satisfaction`. Phases determine *when* to run an agent for this label:
  - `@implementation` — blocks with this label go to the implementing agent (Step 5)
  - `@validation` — blocks go to the validating agent (Step 6)
  - `@satisfaction(threshold)` — blocks go to the judge agent (Step 7). The agent evaluates the experience on a 0.0–1.0 scale. The threshold is the minimum required score — can be a number (`@satisfaction(0.8)`) or a glossary key (`@satisfaction(satisfaction-level)`). Default: `@satisfaction` = `@satisfaction(0.7)`.
  - A label with both phases (`@implementation @validation`) — visible to both agents (e.g., `[test]` — TDD in implementation + verification)
  - A label with `@validation` only — hidden from the implementing agent (holdout). The agent builds software without knowledge of these validation criteria. Works like a holdout set in ML.
  - A label with `@satisfaction` only — the scenario does not generate code or tests. It is a prompt for the AI judge, who interacts with the running application and evaluates it subjectively. This validates what cannot be checked by a deterministic test: UX, readability, intuitiveness, overall quality.
  - A label without any phase — **error**. Sync stops at Step 2 (consistency) with the message: "Label `[x]` has no defined phase (@implementation / @validation / @satisfaction)."
- **Context markers (`+`):** After phases, context markers can be specified to determine *what* the agent receives. Every agent always receives its own axiom (the one the label originates from). Available markers:
  - `+code` — access to source code in `code/`
  - `+axioms` — access to all system axioms (not just its own)
  - `+browser` — access to a browser / running application (browser automation)
  - `+api` — access to HTTP endpoints (curl, requests)
  - No markers = agent receives only its axiom and label instructions
- **Agent isolation:** Each label in the verification and satisfaction phases launches a **separate agent** with context determined by `+` markers. The main process (Steps 0–4) serves as the orchestrator — reads axioms, builds the plan, filters context, and delegates work. The implementing agent does NOT see blocks from `@validation`-only or `@satisfaction`-only labels. The validating agent does NOT see the implementing agent's reasoning. The `+` markers control what each agent sees — e.g., a `[ux-validate]` agent with `+browser` but without `+code` cannot cheat by inspecting HTML instead of evaluating the UI.

### Axiom files

**One file = one axiom.** Each axiom is a Markdown file describing one cohesive concern: a page, a feature, a technology stack, a data protection policy.

Axiom file structure:
```
# Axiom name
[label1]

Axiom content — narrative description of the concern.

## Section
[label2]

Further content...
```

Syntax:
- Heading `#` is the axiom name
- Heading `##` defines sections within the axiom
- Labels in square brackets on the line below the heading: `[test] [security]`
- Descriptive content below (narrative, not checklist)
- Reference to another axiom: `[Name](./file.md)` or `[Section](./file.md#section)` (standard markdown link)
- Axiom namespace ID: `{folder}/{file}.md` (e.g., `patient-client/booking.md`). For sections: `{folder}/{file}.md#{heading-slug}` (e.g., `data-protection.md#technical-security`)

### Label cascade

Labels inherit downward (like CSS):
- Label under `## Axioms` in `main.md` → applies to ALL axioms (global)
- Label on `#` (axiom file heading) → applies to the entire file
- Label on `##` (section) → applies to that section
- Each level inherits labels from the level above

Example — file `data-protection.md`:
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

In this example: the entire file has `[rodo]`. The "Technical security" section has `[rodo] [pentest] [test]` (inherited + own). The "Privacy policy" section has `[rodo] [ux-validate]`. If `main.md` has `[lint]` under `## Axioms`, all sections additionally have `[lint]`.

## @axiom markers in code

Every code fragment in `code/` must point to the axiom it derives from using `@axiom` markers.

### Marker format

Markers use the axiom namespace ID (file path + heading anchor):

HTML:
```html
<!-- @axiom: landing-client/main.md#hero-section -->
...code derived from the axiom...
<!-- /@axiom: landing-client/main.md#hero-section -->
```

Bash:
```bash
# @axiom: technology.md#deploy-script
...code...
# /@axiom: technology.md#deploy-script
```

CSS:
```css
/* @axiom: landing-client/main.md#hero-section */
...style...
/* /@axiom: landing-client/main.md#hero-section */
```

JS:
```javascript
// @axiom: login-client/registration.md#form-validation
...code...
// /@axiom: login-client/registration.md#form-validation
```

PHP:
```php
// @axiom: api.md#api-endpoint
...code...
// /@axiom: api.md#api-endpoint
```

### Marker rules

1. Markers can be nested — e.g., a registration form (`@axiom: login-client/registration.md#patient-registration-form`) can contain `@axiom: data-protection.md#processing-consent` inside for a checkbox.
2. Every opening marker (`@axiom: X`) must have a matching closing marker (`/@axiom: X`).
3. Names in markers are namespace IDs (file path + anchor) and must correspond to existing axioms.
4. In `{{content}}` blocks there should be no code outside @axiom markers (orphaned code).
5. Files in `code/tests/` do not require markers.
6. Layout files (`layout-*.html`) have markers on navigation and structure, not on `{{yield content}}`.

### Declarative axioms (no markers in code)

Some axioms describe rules, architecture, or exclusions — they have no direct representation in code and do NOT require `@axiom` markers. Such axioms should be listed in the project's axiom file.

## Run modes

### Default mode (diff)
By default, axioms-sync works in diff mode — it only syncs axioms that have changed since the last run.

### Full mode
To force a full sync (all axioms, not just the diff), the user must pass the `--full` argument or say "full sync".

## Procedure

Execute the following steps SEQUENTIALLY. Do not proceed to the next step without completing the previous one.

### Step 0: Snapshot and diff

1. Create the `.axioms/` folder if it doesn't exist.
2. **Snapshot current axioms:** Copy axiom files from `axioms/` (`.md`, `ui-template.html`, `*-client/` folders) to `.axioms/current/` (clear the folder before copying). This is the snapshot of axioms from this run — subsequent steps work on files from `.axioms/current/`.
3. Check if the `.axioms/freeze/` folder exists.
4. **If `.axioms/freeze/` does NOT exist** (first run):
   - Treat as a full sync — all axioms will be on the change list.
5. **If `.axioms/freeze/` exists** and mode = diff (default):
   - Compare `.axioms/current/` with `.axioms/freeze/` using `diff -ru`.
   - If diff returns empty — no changes, end sync with the message "No changes in axioms."
   - If diff returns differences — parse the diff output:
     - New files → new axioms (added).
     - Deleted files → deleted axioms.
     - Changed lines (`+`/`-`) → identify which axioms (files/sections) were modified based on diff context.
   - Subsequent steps (change list, implementation) apply ONLY to changed axioms.
6. **If mode = full** (`--full`):
   - Ignore `.axioms/freeze/`, process all axioms.
7. Save snapshot to freeze: Copy contents of `.axioms/current/` to `.axioms/freeze/` (overwrite).

### Step 1: Load axioms

1. Read `axioms/main.md`.
2. Find all includes — links in the format `[Name](./file.md)`. Read those files.
   - Each included file is a separate axiom.
   - **Recursively:** if an included file itself contains links to other `.md` files (relative paths), read those files too. Repeat until there are no new links.
   - Do NOT scan files in a folder that are not reachable through the link chain from `main.md`.
3. Parse axioms from all loaded files: extract names (heading `#`), sections (heading `##`), labels (`[...]`), references, content. Account for the label cascade (global from `## Axioms`, file `#`, section `##`).
4. Parse label definitions from the "## Labels" section.

### Step 2: Check axiom consistency

Check:
- Are there mutually exclusive axioms (contradictory requirements)?
- Do all references `[Name](#anchor)` point to existing axioms?
- Are there duplicate axiom names?
- Do all links and paths (e.g., `./ui-template.html`) point to existing files?

If you find problems — STOP and report them to the user. Do not continue without resolving contradictions.

### Step 3: Prepare the change list and verification checklist

If mode = diff, first output a summary of axiom changes:
```
## Axiom changes since last sync
- Added: ...
- Deleted: ...
- Modified: ...
```

**A) Implementation context (for Step 5):**

For each axiom in scope (diff or full):
1. Check if the code in `code/` complies with the axiom.
2. If not — record what needs to change.
3. **Filter by phases:** Remove blocks tagged with labels that have only `@validation` or only `@satisfaction` (without `@implementation`) from axiom content. The implementing agent must not see them.
4. Include the axiom's `@implementation` labels and add corresponding items to the change list (e.g., "write tests" for `[test]`, "write e2e test" for `[e2e]`).

Output the change list in the format:

```
## Change list (implementation)

### Axiom name — short description
- [ ] What needs to be done
- [ ] What tests to write (if [test])
```

**B) Validation context (for Step 6):**

Based on labels found in axioms and the project's test infrastructure, prepare two lists:

1. **Commands to run** — check what test runners exist in the project (e.g., `Makefile`, `package.json`, `playwright.config.*`, `dune` test stanzas) and record the commands.
2. **Holdout scenarios** — collect axiom blocks tagged with `@validation`-only labels (without `@implementation`). Each such scenario is a validation criterion that the validating agent checks against the running application/code, **without access to implementation source code**.

Output in the format:
```
## Verification checklist
- [ ] `build command` (e.g., dune build)
- [ ] `unit/integration test command` (e.g., dune exec test/smock_test.exe)
- [ ] `e2e test command` (e.g., npx playwright test) — if there are [e2e] labels
- [ ] security review — if there are [security] labels

## Holdout scenarios
- [ ] Scenario X (from axiom Y)
- [ ] Scenario Z (from axiom W)
```

**C) Satisfaction context (for Step 7):**

Collect axiom blocks tagged with `@satisfaction` labels. Each such block is a prompt for the AI judge — a description of a scenario to execute and evaluate on the running application. `@satisfaction` scenarios do NOT generate code or tests.

For each scenario, read:
1. **Prompt** — axiom content (description of what to check, how to evaluate)
2. **Threshold** — from `@satisfaction(threshold)` in the label definition (default 0.7)
3. **Context** — `+` markers from the label definition (e.g., `+browser` = browser automation)

Output in the format:
```
## Satisfaction scenarios
- [ ] Scenario X (from axiom Y) — threshold: 0.8
- [ ] Scenario Z (from axiom W) — threshold: 0.7
```

Save both lists to `.axioms/sync-result.md` (date, diff/full mode, change summary, implementation context, validation context).

### Step 4: Verify @axiom markers

1. Parse all files in `code/` (except `tests/`).
2. Check marker pairing: every `@axiom: X` must have a `/@axiom: X`.
3. Validate names: every name in a marker must correspond to an existing axiom.
4. Check for orphaned code: in `{{content}}` blocks there should be no code outside @axiom markers.
5. If there are problems — fix them before proceeding to implementation.

### Step 5: Implementation (implementing agent)

Delegate implementation to a **separate agent**. Immediately, do not wait for user confirmation.

The implementing agent receives:
- Implementation context from Step 3A (change list + filtered axioms **without `@validation`-only blocks**)
- Access to `code/` and project infrastructure
- `@implementation` label definitions (e.g., `[test]`, `[e2e]`)

The implementing agent does NOT receive:
- Axiom blocks tagged with `@validation`-only labels (without `@implementation`)
- Validation context from Step 3B

Agent's task:
1. Implement changes from the change list, one by one. All code goes into `code/`. When creating/modifying files — always add `@axiom` markers pointing to the source axiom.
2. Mark each change as done after completing it.
3. For axioms with the `[test]` label — write tests BEFORE writing the implementation (TDD).
4. For axioms with the `[e2e]` label — write an e2e test covering the entire flow.

### Step 6: Verification (validating agent)

Delegate verification to a **separate agent** (or separate agents per label). Execute after Step 5 is complete.

**A) Standard verification:**
1. Run every command from the verification checklist (Step 3B). Do not skip any.
2. **Run each label as a separate agent** with a clean context. The agent receives: its axiom and label instructions + resources determined by `+` markers (e.g., `+code` = source code, `+browser` = browser, `+api` = HTTP endpoints, `+axioms` = all axioms). Does NOT receive generation history or the implementing agent's reasoning. If the label defines a model — use that model.

**B) `@validation`-only (holdout) verification:**
For each `@validation`-only scenario from Step 3B:
1. The validating agent receives: scenario content + resources per `+` markers from the label definition.
2. If the label **does not have** `+code` — the agent does NOT receive source code, evaluating only system behavior from the outside.
3. If the label **has** `+code` (e.g., `[architecture-check]`) — the agent receives code, because verification concerns code structure, not behavior.

**C) Fixing errors:**
1. If something fails (A or B) — delegate the fix to the implementing agent (with the same filtered context + error information, but still **without `@validation`-only blocks**).
2. Repeat the implementation → verification cycle until everything passes.
3. Sync ends only when the code complies with the axioms AND the entire verification checklist (including holdout) passes.

If after sync completion the user still sees bugs — that's a signal that the specification is incomplete (a missing axiom or label). But that's outside the scope of this sync — it requires editing axioms and re-running.

### Step 7: Satisfaction review (judge agent)

Execute after Steps 5–6 are complete (implementation and validation must pass). This step requires a running application.

If there are no `@satisfaction` labels — skip this step.

For each `@satisfaction` scenario from Step 3C:

1. **Delegate to a separate judge agent.** The agent receives:
   - Scenario content (prompt from the axiom)
   - Resources determined by `+` markers from the label definition (e.g., `+browser` = browser automation, `+api` = HTTP requests)
2. **The agent does NOT receive** (unless a `+` marker explicitly grants it):
   - Source code (no `+code`)
   - Reasoning from the implementing and validating agents
   - Axiom content beyond the scenario (no `+axioms`)
3. **The agent executes the scenario** — interacts with the application like a user (clicks, navigates, checks UI) and evaluates the experience.
4. **The agent returns:**
   - Score: 0.0–1.0
   - Justification: what works, what doesn't, what needs improvement
   - Optionally: screenshots, recordings
5. **Compare the score with the threshold.** If score < threshold:
   - Pass the justification to the implementing agent (without the `@satisfaction` scenario content — the agent still doesn't see the judge's prompt).
   - The implementing agent fixes based on the problem description.
   - Repeat the cycle: implementation → validation → satisfaction review.
6. **Sync ends** only when all satisfaction scenarios meet the required threshold (or the orchestrator reports no progress after N iterations).

Save the satisfaction review result to `.axioms/sync-result.md`:
```
## Satisfaction review
- Scenario X (axiom Y): 0.85/1.0 ✓ (threshold: 0.7)
  Justification: ...
- Scenario Z (axiom W): 0.55/1.0 ✗ (threshold: 0.8)
  Justification: ...
```

## Batch processing

If the number of axioms to process is large (>20), split the work into batches:
1. Step 2 (consistency) — always on the full set of axioms.
2. Step 3 (plan + filtering) — by groups (per folder/domain).
3. Step 5 (implementation) — delegate to the agent one axiom at a time.
4. Step 6 (verification) — delegate to the agent(s) on the full set after implementation is complete.
5. Step 7 (satisfaction) — delegate to the judge agent after verification is complete.

## Rules

- Do not modify axioms. Axioms are the source of truth.
- If an axiom is unrealizable — report it, do not implement a workaround.
- If an axiom is tagged `[test]` — code WITHOUT a test does not comply with the axiom.
- Prefer small, atomic commits: one axiom = one commit.
