# Repository Guidelines

## Project Structure & Module Organization
Core OCaml code lives in `lib/`, split into focused modules such as `config/`, `loader/`, `planner/`, `snapshot/`, and `tools/`. The CLI entrypoint is `bin/main.ml`, built as `axioms-sync`. Dune files sit beside each target (`lib/dune`, `bin/dune`, `test/dune`). Repository examples live in `example/` and `example-hello/`; use them as fixtures when changing sync behavior. Dependency locks are tracked in `dune.lock/`.

## Build, Test, and Development Commands
Use `make build` to compile the project with Dune. Run `make check` for Dune checks, and `make test` to execute the test target. `make dev` runs the CLI in watch mode via `dune exec -w bin/main.exe`. Refresh the lockfile with `make lock`. Install a local binary with `make install PREFIX=~/.local`; remove it with `make uninstall`.

## Coding Style & Naming Conventions
Follow the existing OCaml style: 2-space indentation, short modules with clear boundaries, and snake_case for values and filenames (`axioms_sync.ml`, `ai_access.ml`). Prefer pure helper functions and explicit record or variant types over ad hoc structures. Keep Dune stanzas minimal and colocated with the code they build. No formatter config is checked in, so match surrounding style carefully before submitting changes.

## Testing Guidelines
Tests are wired through Dune and `well.test` in `test/dune`. Add coverage in `test/` using descriptive `_test.ml` names and keep fixtures under `example/` when exercising axiom sync flows. The current `test/axioms_sync_test.ml` is empty, so new behavior should usually arrive with the first targeted regression test. Run `make test` before opening a PR.

## Commit & Pull Request Guidelines
Recent history uses short imperative subjects such as `Add AI tool presets and implementation sessions`, but also includes weak messages like `fix` and `-`. Prefer the stronger pattern: concise, imperative, and specific to one change. PRs should explain the user-visible impact, note any changes to sync semantics or examples, link the relevant issue or plan, and include terminal output for `make build` and `make test`.

## Configuration Notes
This project targets OCaml 5.4+ and Dune 3.17 (`dune-project`). The `well` package is pinned from Git, so avoid changing dependency sources casually and regenerate locks when dependencies move.

## Agent Runtime Rules
Do not add or reintroduce hard limits on AI tool-use rounds or agent iteration count as a workaround for context-growth bugs. If long-running planning or implementation workflows hit context problems, fix context management or resumption logic instead of stopping the agent after an arbitrary number of tool calls.
