(** Merge — hierarchical merging of TOML configuration sources *)

let merge sources =
  List.fold_left
    (fun acc source -> Well.Toml.patch acc source)
    Well.Toml.empty
    sources
