# Legacy contract layout

Read only when project instructions explicitly retain standalone authored TOML
or an existing `methods/` directory. Do not migrate formats as a side effect of
an unrelated change.

- `sdd.md` owns the service boundary and indexes methods. Existing
  `methods/<rpc>.md` files own each method's behavior; `types.md` owns shared types.
- For standalone contracts, `docs/<service>/sdd.toml` owns executable RPC and
  message declarations. Markdown specifies behavior without restating declarations.
- During sync, parse the authored TOML and check agreement with the affected
  method specs. Project it without comments to `lib/contract/<Service>.toml`
  and run the project contract build. Never author API in the generated file.
- A change to authored TOML triggers projection and compilation independently of
  whether the project defines a `[contract]` label.
- Follow the project's selected format. Do not introduce standalone authored TOML
  into a project whose contract source is TOML fences in Markdown.
