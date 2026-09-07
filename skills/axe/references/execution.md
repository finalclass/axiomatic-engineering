# Execution configuration and delegation

`axe.toml` is read by the agent following the Axe skill, not by OpenCode or an Axe executable. Paths resolve against the project root. Never store credentials here.

## Configuration

```toml
version = 1

[execution]
mode = "delegated"
order = "sequential"
task_scope = "service"

[worker]
runner = "opencode"
model = "provider/model"
max_retries = 2
timeout_seconds = 1800
# instructions = "axe-worker.md"
```

- `version`: required integer, currently `1`.
- `execution.mode`: required `local` or `delegated`. Local executes Steps 4–5 directly; no worker is needed.
- Delegated mode requires `order = "sequential"` and `task_scope = "service"`. These are the currently supported policies.
- `worker.runner`: required in delegated mode; currently `opencode`, using [the OpenCode adapter](opencode.md). Other runners need an explicit adapter before use.
- `worker.model`: required, nonempty, exact runner model identifier. Do not substitute another provider or model silently.
- `worker.max_retries`: optional nonnegative integer, default `2`; additional correction attempts per task after the initial attempt.
- `worker.timeout_seconds`: optional positive integer, default `1800`; wall-clock limit per attempt.
- `worker.instructions`: optional existing project-relative Markdown file with extra worker guidance. It cannot add requirements or override the spec and Axe rules.

Parse as TOML, check types and supported keys/values before execution. A malformed file, unknown key/version, missing instructions, or unavailable runner/model is a configuration error: report and stop without advancing freeze. Do not silently fall back to local execution. With no file at all, use local execution.

## Orchestrator

1. Complete sync Steps 0–3. Record the effective execution settings and task list in `.axe/last-sync.md`. Capture the initial working-tree changes so worker edits can be distinguished from pre-existing work; preserve that work.
2. Map the entire delta to existing service boundaries, including affected clients. Use architecture and contracts to identify dependencies. Do not create services to fit tasks. Order tasks by dependency where possible; report a contract/architecture contradiction rather than inventing an order around it.
3. Establish all changed target contracts before workers start. Own shared generated contracts, shared types, wiring, and integration explicitly; do not let different workers improvise incompatible versions. These changes must still derive from the approved delta. A service may implement against a target contract before its dependency implementation is ready.
4. Prepare one task per affected service, with a fresh session per service. Keep prompts/logs in a unique temporary run directory outside `docs/` and freeze; record its path in the sync report. Serialize all workers in the same checkout.
5. After each worker, inspect the actual diff (including new files), evidence, and allowed scope. A successful process exit or worker claim is not acceptance. Fix attributable out-of-scope edits without reverting pre-existing changes, or stop if ownership is ambiguous. Send specific implementation failures back to the same task, within its retry budget. Missing requirements return to the architect immediately.
6. After service tasks, complete shared integration and Step 5 verification across the delta. Local service checks do not prove integration. Attribute failures to a task and use its remaining retry budget; on exhaustion, timeout, or unresolved blocker, report partial progress and leave freeze unchanged. Never mark unfinished work complete or silently take over failed delegated service implementation.
7. Only the orchestrator performs Step 6 and project-required commit/deployment actions within the authorized scope. Recheck that the docs still match the Step 0 snapshot before freeze; if they changed during execution, stop and recompute the delta on the next sync.

## Worker task

Include the following in each prompt (attach or link exact files; avoid unrelated service internals):

- Role: delegated implementation worker, one named service, no nested sync or delegation. Read project `AGENTS.md` and applicable service/framework instructions. Commit/push/deploy and snapshot management belong to the orchestrator, not this assignment.
- The service's exact spec delta and target contract, assumptions, applicable labels, and relevant STP. Include enough unchanged context to preserve existing behavior. Docs remain binding; implementation hints are advisory, not additional requirements.
- The relevant architecture edges and dependency contracts/types; code paths needed for this service. Shared contracts have a designated owner and are read-only to this worker unless explicitly assigned.
- An explicit allowlist of editable files/directories, including any owned tests/assets. No edits to `docs/`, `axe.toml`, freeze, other tasks, or unrelated work. The orchestrator handles the derived `tokens.css` exception. If more scope is needed, report a blocker instead of expanding it.
- Exact project verification commands and required evidence. Tests may be added/changed only for `[test]` from STP; `[look]` needs visual evidence. Distinguish checks deferred until integration from passing checks. Follow project formatting rules.
- Return a final report with `status` (`completed`, `blocked`, or `failed`), changed files, checks with outcomes, remaining blockers, and any deferred integration checks. `completed` means the assigned implementation and its feasible local checks are complete, not that the whole sync passed.

The allowlist is a task boundary, not a filesystem sandbox. The orchestrator must inspect actual changes. A worker must not resolve an impossible spec by changing its source.
