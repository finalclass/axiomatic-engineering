(** Sources — loads configuration from various sources as TOML tables *)

let global_config_path () =
  let home =
    match Sys.getenv_opt "HOME" with
    | Some h -> h
    | None -> "/tmp"
  in
  Filename.concat (Filename.concat home ".config") "axioms-sync.toml"

let load_global () =
  let path = global_config_path () in
  if Sys.file_exists path
  then (
    try Well.Toml.from_file path with
    | exn ->
        Printf.eprintf
          "Warning: failed to parse %s: %s\n"
          path
          (Printexc.to_string exn) ;
        Well.Toml.empty )
  else Well.Toml.empty

let load_project (project_path : string) =
  let path = Filename.concat project_path ".axioms/axioms-sync.toml" in
  if Sys.file_exists path
  then (
    try Well.Toml.from_file path with
    | exn ->
        Printf.eprintf
          "Warning: failed to parse %s: %s\n"
          path
          (Printexc.to_string exn) ;
        Well.Toml.empty )
  else Well.Toml.empty

let parse_cli_args (args : string list) =
  let toml = ref Well.Toml.empty in
  let set_string key value = toml := Well.Toml.set_string !toml [key] value in
  let set_int key value = toml := Well.Toml.set_int !toml [key] value in
  let set_bool key value = toml := Well.Toml.set_bool !toml [key] value in
  let rec parse = function
    | [] -> ()
    | "--full" :: rest ->
        set_string "mode" "full" ;
        parse rest
    | ("--quiet" | "-q") :: rest ->
        set_bool "quiet" true ;
        parse rest
    | ("--progress" | "-p") :: rest ->
        set_bool "quiet" true ;
        set_bool "progress" true ;
        parse rest
    | "--timings" :: rest ->
        set_bool "timings" true ;
        parse rest
    | "--no-semantic" :: rest ->
        set_bool "no_semantic" true ;
        parse rest
    | "--models" :: rest ->
        set_bool "show_models" true ;
        parse rest
    | "--max-cycles" :: v :: rest ->
        ( try set_int "max_cycles" (int_of_string v) with
        | Failure _ -> () ) ;
        parse rest
    | "--planner" :: v :: rest ->
        set_string "planner" v ;
        parse rest
    | "--implementer" :: v :: rest ->
        set_string "implementer" v ;
        parse rest
    | "--smart" :: v :: rest ->
        set_string "smart" v ;
        parse rest
    | "--balanced" :: v :: rest ->
        set_string "balanced" v ;
        parse rest
    | "--fast" :: v :: rest ->
        set_string "fast" v ;
        parse rest
    | "--vision" :: v :: rest ->
        set_string "vision" v ;
        parse rest
    | "--preprompt" :: v :: rest ->
        set_string "preprompt" v ;
        parse rest
    | "--axiom" :: v :: rest ->
        set_string "axiom" v ;
        parse rest
    | "--provider" :: v :: rest ->
        set_string "provider" v ;
        parse rest
    | path :: rest when not (String.length path > 0 && path.[0] = '-') ->
        set_string "project_path" path ;
        parse rest
    | ("--help" | "-h") :: _ ->
        print_endline "Usage: axioms-sync [PATH] [OPTIONS]" ;
        exit 0
    | unknown :: _ ->
        Printf.eprintf "Unknown argument: %s\n" unknown ;
        exit 1
  in
  parse args ;
  !toml

let load_env () =
  let toml = ref Well.Toml.empty in
  Array.iter
    (fun entry ->
      match String.index_opt entry '=' with
      | Some eq_pos ->
          let key = String.sub entry 0 eq_pos in
          let value =
            String.sub entry (eq_pos + 1) (String.length entry - eq_pos - 1)
          in
          if String.length key >= 3 && String.sub key 0 3 = "AS_"
          then
            let toml_key =
              let suffix = String.sub key 3 (String.length key - 3) in
              String.map (fun c -> if c = '_' then '-' else c) suffix
              |> String.map (fun c -> if c = '-' then '_' else c)
            in
            let toml_v =
              if value = "true"
              then Well.Toml.boolean true
              else if value = "false"
              then Well.Toml.boolean false
              else
                try Well.Toml.integer (int_of_string value) with
                | Failure _ -> (
                  try Well.Toml.float (float_of_string value) with
                  | Failure _ -> Well.Toml.string value )
            in
            toml := Well.Toml.set !toml [toml_key] toml_v
      | None -> () )
    (Unix.environment ()) ;
  !toml
