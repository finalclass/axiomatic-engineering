# axioms_sync

Built with [well](https://github.com/anthropics/well) — full-stack OCaml web framework.

## Getting started

```bash
make dev          # start dev server with hot reload (dune exec -w)
make build        # build
make test         # run tests
make check        # type-check only (faster)
well build        # production build (patchelf + bundled .so)
well release      # deployable .tar.gz archive
```

The dev server runs at **http://localhost:4000**.

`make dev` uses `dune exec -w` which watches for file changes, rebuilds, and restarts the server automatically.

## Project structure

```
bin/main.ml                        # entry point → App.run ()
lib/
  app.ml                           # middleware, services, routes, Well.run ()
  events.ml                        # typed pub/sub topics
  note_access/note_access_impl.ml  # NoteAccess service implementation
  task_access/task_access_impl.ml  # TaskAccess service implementation
  task_manager/task_manager_impl.ml # TaskManager service implementation
  client/
    widgets/layout.mlx             # HTML layout
    pages/                         # route pages (home, counter, notes, ...)
    live/                          # LiveView modules (counter, activity log)
    request_id.ml                  # request ID middleware
  contract/                        # service contracts (TOML → generated code)
static/                            # CSS, JS, assets
test/                              # tests
data/                              # SQLite databases (gitignored)
```

## File types

- `.ml` — OCaml (logic, models, queries)
- `.mlx` — OCaml + JSX (views, components)
- `.ts` — TypeScript (compiled to JS via bun, wired through dune)
