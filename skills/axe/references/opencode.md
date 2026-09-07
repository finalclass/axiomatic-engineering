# OpenCode worker adapter

Use only when `axe.toml` selects `worker.runner = "opencode"`. The orchestrator launches the CLI and reads its results; the human does not have to copy prompts.

## Preflight

Check `opencode --version`, `opencode run --help`, and `opencode models <provider>` (provider is the first segment of `worker.model`). Verify the exact configured model exists. Use existing provider authentication; never copy keys into config, prompts, or logs. A listed model does not prove the account can call it: treat authentication, quota, and API failures as blockers.

The invocation below was checked against OpenCode 1.18.23 and the [official CLI reference](https://dev.opencode.ai/docs/cli). Recheck installed flags when versions differ.

## Invocation

Write the complete service task to a UTF-8 file in the temporary run directory. Resolve config values with a TOML parser and pass them as argument values, never as executable shell text. Set `axe_project_root`, `axe_model`, `axe_task_file`, `axe_events_file`, `axe_stderr_file`, and `axe_timeout_seconds` from those resolved values and the current task. Then run:

```bash
timeout --kill-after=10s "${axe_timeout_seconds}s" \
  opencode run --dir "$axe_project_root" \
  --model "$axe_model" --agent build --format json \
  --file "$axe_task_file" -- \
  'Execute only the attached delegated Axe service task. Do not start axe sync. Return the requested final report.' \
  > "$axe_events_file" 2> "$axe_stderr_file"
```

Use a process tool that yields while the command runs so the orchestrator can report progress and inspect logs. Record the exit status. On systems without `timeout`, enforce the same deadline through the process supervisor, including terminating the worker before starting another one.

Start a new session for each service: omit `--continue`, `--session`, and `--fork`. For corrections to that same task, pass its recorded session ID with `--session` and attach the specific failure/correction prompt. Never use the last ambient session. Use distinct output files per attempt.

Preserve existing OpenCode permissions and project rules. Do not add blanket `--auto` merely to avoid interaction. If headless execution encounters a denied operation or permission prompt, surface it as a blocker; configure only the needed permissions within existing authorization. Do not publish/share sessions.

## Result handling

`--format json` emits a stream of JSON events, not a single result object. Retain the session ID, final assistant text, tool failures, and usage/cost fields when present. Do not treat an intermediate step completion as task completion.

Wait for process completion and inspect both event and stderr logs. Nonzero exit, timeout, error events, permission failures, missing final report, or a blocked/failed report require investigation even if some files changed. The final report is worker-provided evidence; validate it against the working tree and required commands using the orchestrator protocol. Keep partial edits available for a bounded correction attempt; do not advance freeze on failure.
