# Separate operator review and execution

Opt in through the project's `axe.toml`:

```toml
[workflow]
review = "operators"
```

The project's linked role diagrams own the sequence, approvals and transitions.
This reference owns AXE mechanics for that sequence. It does not grant approval,
enable operators or authorize deployment. Projects without this setting retain
the default AXE workflow.

## Source and responsibility boundaries

Architect prepares the smallest necessary specification proposal and Inspektor
owns its independent consistency, necessity, completeness and testability review.
Both work from the issue and authored specification, never implementation, tests,
generated projections or source history. They use **Specification review** in
SKILL.md. For project-selected specification PR review, saving the proposal in
that PR is authorized; stop at the project's human specification gate.

Drwal reads the approved scope and relevant binding specification, investigates
implementation, synchronizes it and runs automated checks. Do not perform another
specification consistency audit. An execution-blocking ambiguity goes back to
Architect; never change requirements to make code pass. Syntax parsing and
contract compilation are mechanical checks, not a product/specification review.

Drwal never loads `agent-browser`, opens the application interactively, performs
visual acceptance or records a manual UI pass. Automated E2E is allowed under the
existing test plan. Tester performs visual/behavioral acceptance independently,
primarily from the issue and live application. Tester may consult only a relevant
specification passage to clarify the expected result and never reads source.
Do not apply the generic repository-wide discovery instructions to these roles.

## Accepted specification delta

Run `scripts/delta.py` from the project root. In this mode it produces a mechanical
delta and automation requirements; semantic links/ownership are Inspektor's
review responsibility. Invalid JSON or contract TOML still blocks execution.
Missing freeze is a blocker: the tool must not certify current docs as implemented.
Establish the baseline from verified previous implementation, outside this run.

Implement only the accepted scope. If the delta includes unrelated, unapproved
requirements, stop and report the scope mismatch instead of absorbing them.
The report's **Tester handoff** is pending work for Tester, never Drwal's check.
The issue's UI scope can require video acceptance even if no `[look]` changed.
Use the project's automated build/format/test targets; existing required checks
remain required even if no new STP scenario was added. Write or change tests only
where the approved STP / `[test]` authorizes them. Do not invent a test plan.

## Bounded implementation-only repair

An empty delta means unchanged specification, not absence of an implementation
defect. A project-authorized handoff must identify the issue, existing requirement
and revision (or explain a purely mechanical repair), bounded scope, observable
acceptance criteria and relevant existing automated checks. Without it, stop.

Run the delta tool to establish that no unrelated specification change is pending.
An `empty` report then permits this bounded repair; do not fabricate a docs edit.
If a real delta exists, reconcile it with the approved scope before proceeding.
Read relevant binding artifacts and STP, repair the implementation, format changed
source, and run existing required automated checks. A need for new requirements
or uncovered test behavior returns to Architect. Do not move freeze for a repair
with unchanged docs, and do not claim a fresh specification approval.

## Freeze and evidence

In this mode freeze means **implemented specification with successful automated
verification**. It does not mean visual acceptance, human code approval or release
approval. Preserve freeze on any unresolved required automation failure.
Before advancing it, confirm `.axe/current` still represents the approved docs
implemented in this run; a concurrent docs change requires a fresh scope check.
Then replace `.axe/freeze` with that verified snapshot under the project's AXE
storage rules. Never advance it merely because a candidate was built.

Record commands, exit codes and log paths, scope/issue references, specification
revision, sync versus repair, and visual acceptance as `pending` (or `not
applicable` with reason) in `.axe/last-sync.md`. Pass that status and any required
screens/viewports to the issue handoff. A pending visual check is not a passed
check and does not prevent this automation-only freeze; it prevents release until
the project's Tester and human gates are satisfied.

Persist every completed sync or repair as a commit, including task-owned freeze
and evidence where tracked, and push it under project Git rules before handing
off implementation review. Preserve unrelated changes. Use **Tracker issues in
commits**; never use auto-closing keywords. No changed files means no empty commit.
A published implementation still requires all remaining human gates.
