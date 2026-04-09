(** Config — hierarchical configuration loading *)

let _cached : Types.config option ref = ref None

let merge_toml (sources : Otoml.t list) : Otoml.t =
  List.fold_left
    (fun acc source -> Well.Toml.patch acc [source])
    Well.Toml.empty
    sources

let source_of_string = function
  | "global" -> `Global
  | "project" -> `Project
  | "cli" -> `Cli
  | "env" -> `Env
  | _ -> `Global

let get_string toml key default =
  match Well.Toml.get_string toml key with
  | Some v -> v
  | None -> default

let get_bool toml key default =
  match Well.Toml.get_string toml key with
  | Some "true"
   |Some "1" ->
      true
  | Some "false"
   |Some "0" ->
      false
  | _ -> default

let get_int toml key default =
  match Well.Toml.get_string toml key with
  | Some s -> (
    try int_of_string s with
    | Failure _ -> default )
  | None -> default

let get_string_opt toml key = Well.Toml.get_string toml key

let provider_of_string = function
  | "openrouter" -> Types.OpenRouter
  | _ -> Types.OpenRouter

let load_impl ?(project_path = ".") () : Types.config =
  let global = Sources.load_global () in
  let project = Sources.load_project project_path in
  let cli = Sources.parse_cli_args (Array.to_list Sys.argv |> List.tl) in
  let env = Sources.load_env () in
  let merged = merge_toml [global; project; cli; env] in
  let quiet = get_bool merged ["quiet"] false in
  { project_path= get_string merged ["project_path"] "."
  ; mode=
      ( match get_string merged ["mode"] "diff" with
      | "full" -> `Full
      | _ -> (
        match get_string_opt merged ["axiom"] with
        | Some axiom -> `Specific [axiom]
        | None -> `Diff ) )
  ; planner= get_string merged ["planner"] "deepseek-v3.2"
  ; implementer= get_string merged ["implementer"] "m2.7"
  ; smart= get_string merged ["smart"] "m2.7"
  ; balanced= get_string merged ["balanced"] "m2.7"
  ; fast= get_string merged ["fast"] "k2.5"
  ; vision= get_string merged ["vision"] "google/gemini-3-flash-preview"
  ; preprompt= get_string merged ["preprompt"] ""
  ; max_cycles= get_int merged ["max_cycles"] 3
  ; no_semantic= get_bool merged ["no_semantic"] false
  ; axiom= get_string_opt merged ["axiom"]
  ; timings= get_bool merged ["timings"] false
  ; provider=
      ( match get_string_opt merged ["provider"] with
      | Some p -> provider_of_string p
      | None -> Types.OpenRouter )
  ; api_key= get_string_opt merged ["api_key"]
  ; model_overrides= []
  ; quiet }

let load ?(project_path = ".") () : Types.config =
  match !_cached with
  | Some c -> c
  | None ->
      let result = load_impl ~project_path () in
      _cached := Some result ;
      result

let reset () = _cached := None
