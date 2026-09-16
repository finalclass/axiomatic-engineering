# Grok worker adapter

Use only when `axe.toml` selects `worker.runner = "grok"`, after reading
[the execution protocol](execution.md). Task ownership, scope and validation
are defined there.

Honor execution.order, execution.task_scope, worker.runner, worker.model,
worker.max_retries and worker.timeout_seconds. For runner = "grok", use the
installed Grok Build CLI. Resolve the native model ID with grok models; never
pass an OpenRouter-prefixed ID to this runner. Inspect grok --help when the
installed CLI changes. Launch one fresh headless process per service:

    timeout --kill-after=10s <timeout_seconds>s grok --cwd <checkout> --model <model> --no-subagents --disable-web-search --output-format json --prompt-file <task-packet>

Pass arguments as an array or with proper shell quoting. Capture stdout/stderr
in separate private artifacts; bound each orchestration wait to at most 60s.
No --always-approve, bypassPermissions, automatic model fallback or recursive
workers. Start with default permissions; report a required permission/tool denial
rather than treating an unchanged retry as progress. Scoped allowances require
review of the installed CLI rule syntax and the task's write allowlist.

Before first use or a runner/model change, run a no-tools READY probe from an
isolated temporary directory, using --tools '' --no-subagents --disable-web-search
--max-turns 1 --output-format json --verbatim -p 'Reply with exactly READY. Do not
use any tools.'. Check text, stop reason and modelUsage. Store actual usage and
cost if returned. CLI/system-context tokens are overhead; a tiny user prompt does
not imply a tiny input count. A successful probe verifies model access only,
not worker file permissions, compilation or spec consistency. Do not launch an
implementation worker until those separate readiness gates pass.
