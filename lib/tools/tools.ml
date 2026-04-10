(** Tool definitions and execution for AI agents *)

(** Todo list state *)
let todos : (string * string) list ref = ref []

let todo_status_marker status =
  match status with
  | "completed" -> "☑"
  | "in_progress" -> "◐"
  | _ -> "☐"

let todo_write ~(todos_list : (string * string) list) : string =
  todos := todos_list ;
  match !todos with
  | [] -> "Todos updated\nNo todos"
  | _ ->
      "Todos updated\n"
      ^ (List.map (fun (t, s) -> Printf.sprintf "%s %s" (todo_status_marker s) t) !todos
        |> String.concat "\n")

let todo_read () : string =
  match !todos with
  | [] -> "No todos"
  | _ ->
      List.map (fun (t, s) -> Printf.sprintf "%s %s" (todo_status_marker s) t) !todos
      |> String.concat "\n"

(** Read a file's content *)
let read_file ~(path : string) : string =
  if Sys.file_exists path
  then begin
    let ic = In_channel.open_text path in
    let content = In_channel.input_all ic in
    In_channel.close ic ;
    content
  end
  else Printf.sprintf "Error: file not found: %s" path

(** Write content to a file *)
let write_file ~(path : string) ~(content : string) : unit =
  (* Ensure parent directory exists *)
  let dir = Filename.dirname path in
  if not (Sys.file_exists dir)
  then ignore (Sys.command (Printf.sprintf "mkdir -p %s" (Filename.quote dir))) ;
  let oc = Out_channel.open_text path in
  Out_channel.output_string oc content ;
  Out_channel.close oc

(** Replace old_string with new_string in a file *)
let edit_file ~(path : string) ~(old_string : string) ~(new_string : string) :
    (unit, string) result =
  if not (Sys.file_exists path)
  then Error (Printf.sprintf "File not found: %s" path)
  else begin
    let ic = In_channel.open_text path in
    let content = In_channel.input_all ic in
    In_channel.close ic ;
    match String.split_on_char '\x00' content with
    | _ ->
        (* Check if old_string exists in the file *)
        let idx = ref None in
        let olen = String.length old_string in
        let clen = String.length content in
        if olen = 0
        then Error "old_string is empty"
        else begin
          let i = ref 0 in
          while !i <= clen - olen && !idx = None do
            if String.sub content !i olen = old_string then idx := Some !i ;
            incr i
          done ;
          match !idx with
          | None -> Error (Printf.sprintf "old_string not found in %s" path)
          | Some pos ->
              let before = String.sub content 0 pos in
              let after = String.sub content (pos + olen) (clen - pos - olen) in
              let new_content = before ^ new_string ^ after in
              let oc = Out_channel.open_text path in
              Out_channel.output_string oc new_content ;
              Out_channel.close oc ;
              Ok ()
        end
  end

(** List files matching a glob pattern in a directory. *)
let list_files ~(glob : string) ~(base_dir : string) : string list =
  let cmd =
    Printf.sprintf
      "cd %s && rg --files -g %s 2>/dev/null | sort"
      (Filename.quote base_dir)
      (Filename.quote glob)
  in
  let ic = Unix.open_process_in cmd in
  let results = ref [] in
  ( try
      while true do
        let line = input_line ic in
        let full_path =
          if Filename.is_relative line
          then Filename.concat base_dir line
          else line
        in
        results := full_path :: !results
      done
    with
  | End_of_file -> () ) ;
  match Unix.close_process_in ic with
  | Unix.WEXITED 0 | Unix.WEXITED 1 -> List.rev !results
  | _ -> []

(** List files matching a glob pattern. Wraps list_files. *)
let glob_search ~(pattern : string) ~(base_dir : string) : string list =
  list_files ~glob:pattern ~base_dir

(** Search file contents with a regex pattern using grep -rn. *)
let grep_search ~(pattern : string) ~(base_dir : string) : string =
  let cmd =
    Printf.sprintf
      "rg -n --color never --glob '*.ml' --glob '*.mli' --glob '*.md' \
       --glob '*.txt' --glob '*.json' --glob '*.dune' -e %s %s 2>&1"
      (Filename.quote pattern)
      (Filename.quote base_dir)
  in
  let ic = Unix.open_process_in cmd in
  let buf = Buffer.create 1024 in
  ( try
      while true do
        Buffer.add_char buf (input_char ic)
      done
    with
  | End_of_file -> () ) ;
  let status = Unix.close_process_in ic in
  let output = Buffer.contents buf in
  match status with
  | Unix.WEXITED 0 -> output
  | Unix.WEXITED 1 -> "" (* rg returns 1 when no match *)
  | Unix.WEXITED code ->
      Printf.sprintf "Error (exit code %d):\n%s" code output
  | Unix.WSIGNALED s ->
      Printf.sprintf "Killed by signal %d:\n%s" s output
  | Unix.WSTOPPED s ->
      Printf.sprintf "Stopped by signal %d:\n%s" s output

(** Run a bash command, return stdout+stderr *)
let bash ~(command : string) : (string, string * int) result =
  let cmd = Printf.sprintf "(%s) 2>&1" command in
  let ic = Unix.open_process_in cmd in
  let buf = Buffer.create 1024 in
  ( try
      while true do
        Buffer.add_char buf (input_char ic)
      done
    with
  | End_of_file -> () ) ;
  let status = Unix.close_process_in ic in
  let output = Buffer.contents buf in
  match status with
  | Unix.WEXITED 0 -> Ok output
  | Unix.WEXITED code -> Error (output, code)
  | Unix.WSIGNALED s -> Error (Printf.sprintf "Killed by signal %d" s, 128 + s)
  | Unix.WSTOPPED s -> Error (Printf.sprintf "Stopped by signal %d" s, 128 + s)

(** JSON schema helpers *)
let string_prop ~description : Yojson.Safe.t =
  `Assoc [("type", `String "string"); ("description", `String description)]

let object_schema ~required (properties : (string * Yojson.Safe.t) list) :
    Yojson.Safe.t =
  `Assoc
    [ ("type", `String "object")
    ; ("properties", `Assoc properties)
    ; ("required", `List (List.map (fun s -> `String s) required)) ]

(** Tool definitions *)
let read_file_def : Types.tool_def =
  { name= "read_file"
  ; description= "Read the contents of a file at the given path"
  ; input_schema=
      object_schema
        ~required:["path"]
        [("path", string_prop ~description:"Absolute path to the file to read")]
  }

let write_file_def : Types.tool_def =
  { name= "write_file"
  ; description= "Write content to a file, creating it if it doesn't exist"
  ; input_schema=
      object_schema
        ~required:["path"; "content"]
        [ ("path", string_prop ~description:"Absolute path to the file to write")
        ; ("content", string_prop ~description:"Content to write to the file")
        ] }

let edit_file_def : Types.tool_def =
  { name= "edit_file"
  ; description= "Replace old_string with new_string in a file (exact match)"
  ; input_schema=
      object_schema
        ~required:["path"; "old_string"; "new_string"]
        [ ("path", string_prop ~description:"Absolute path to the file to edit")
        ; ( "old_string"
          , string_prop ~description:"Exact string to find and replace" )
        ; ("new_string", string_prop ~description:"Replacement string") ] }

let glob_search_def : Types.tool_def =
  { name= "glob_search"
  ; description= "Find files by glob pattern"
  ; input_schema=
      object_schema
        ~required:["pattern"; "base_dir"]
        [ ( "pattern"
          , string_prop ~description:"Glob pattern (e.g. '*.ml', '**/*.md')" )
        ; ("base_dir", string_prop ~description:"Base directory to search in")
        ] }

let grep_search_def : Types.tool_def =
  { name= "grep_search"
  ; description= "Search file contents with a regex pattern"
  ; input_schema=
      object_schema
        ~required:["pattern"; "base_dir"]
        [ ("pattern", string_prop ~description:"Regex pattern to search for")
        ; ("base_dir", string_prop ~description:"Base directory to search in")
        ] }

let todo_write_def : Types.tool_def =
  { name= "TodoWrite"
  ; description= "Update the structured task list for the current session"
  ; input_schema=
      `Assoc
        [ ("type", `String "object")
        ; ( "properties"
          , `Assoc
              [ ( "todos"
                , `Assoc
                    [ ("type", `String "array")
                    ; ("description", `String "The updated todo list")
                    ; ( "items"
                      , `Assoc
                          [ ("type", `String "object")
                          ; ( "properties"
                            , `Assoc
                                [ ( "task"
                                  , `Assoc
                                      [ ("type", `String "string")
                                      ; ( "description"
                                        , `String "Task description" ) ] )
                                ; ( "status"
                                  , `Assoc
                                      [ ("type", `String "string")
                                      ; ( "description"
                                        , `String
                                            "pending/in_progress/completed" ) ]
                                  ) ] )
                          ; ( "required"
                            , `List [`String "task"; `String "status"] ) ] ) ]
                ) ] )
        ; ("required", `List [`String "todos"]) ] }

let bash_def : Types.tool_def =
  { name= "bash"
  ; description= "Run a bash command and return stdout+stderr"
  ; input_schema=
      object_schema
        ~required:["command"]
        [("command", string_prop ~description:"The bash command to execute")] }

(** All tool definitions available to agents *)
let all_tool_defs : Types.tool_def list =
  [ read_file_def
  ; write_file_def
  ; edit_file_def
  ; glob_search_def
  ; grep_search_def
  ; bash_def
  ; todo_write_def ]

(** Convert Types.tool_def list to Ai_access tool tuple format *)
let to_ai_tools (defs : Types.tool_def list) :
    (string * string * Yojson.Safe.t) list =
  List.map
    (fun (d : Types.tool_def) -> (d.name, d.description, d.input_schema))
    defs

(** Extract a string field from JSON input *)
let json_string_opt (input : Yojson.Safe.t) (field : string) : string option =
  let open Yojson.Safe.Util in
  input |> member field |> to_string_option

let require_json_string (input : Yojson.Safe.t) (field : string) :
    (string, string) result =
  match json_string_opt input field with
  | Some value when String.trim value <> "" -> Ok value
  | _ ->
      Error
        (Printf.sprintf
           "missing or invalid string field `%s` in tool input"
           field )

let require_tool_string
    (input : Yojson.Safe.t)
    ~(field : string)
    ~(fallback : string option) : (string, string) result =
  match require_json_string input field with
  | Ok value -> Ok value
  | Error msg -> (
      match fallback with
      | Some value when String.trim value <> "" -> Ok value
      | _ -> Error msg )

let starts_with ~prefix s =
  let plen = String.length prefix in
  String.length s >= plen && String.sub s 0 plen = prefix

let normalize_path path =
  try Unix.realpath path with
  | _ -> path

let path_within ~(root : string) (path : string) : bool =
  let root = normalize_path root in
  let path = normalize_path path in
  path = root || starts_with ~prefix:(root ^ "/") path

let resolve_dir ~(base_dir : string) (dir : string) : string =
  let candidate =
    if Filename.is_relative dir then Filename.concat base_dir dir else dir
  in
  if
    Sys.file_exists candidate
    && Sys.is_directory candidate
    && path_within ~root:base_dir candidate
  then candidate
  else base_dir

let axioms_root ~(base_dir : string) : string =
  normalize_path (Filename.concat base_dir "axioms")

let path_in_axioms ~(base_dir : string) (path : string) : bool =
  let resolved = normalize_path path in
  let axioms = axioms_root ~base_dir in
  resolved = axioms || starts_with ~prefix:(axioms ^ "/") resolved

let reject_axiom_write ~(base_dir : string) (path : string) :
    (unit, string) result =
  if path_in_axioms ~base_dir path
  then Error "Writing to axioms/ is forbidden. Axioms are read-only."
  else Ok ()

let contains s sub =
  let slen = String.length s in
  let sublen = String.length sub in
  let rec loop i =
    if i + sublen > slen then false
    else if String.sub s i sublen = sub then true
    else loop (i + 1)
  in
  sublen = 0 || loop 0

let bash_touches_axioms ~(base_dir : string) (command : string) : bool =
  let axioms = axioms_root ~base_dir in
  let mentions_axioms =
    List.exists (contains command) ["/axioms/"; " axioms/"; axioms]
  in
  let looks_mutating =
    List.exists
      (contains command)
      [" >"; ">>"; "tee "; "sed -i"; "perl -pi"; "mv "; "cp "; "rm "; "touch "]
  in
  mentions_axioms && looks_mutating

(** Try to find a file under base_dir by trying successive suffixes
    of the path. E.g. for "/home/user/planner/metadata/add-schema.md"
    tries: "home/user/...", "user/...", "planner/metadata/add-schema.md",
    "metadata/add-schema.md", "add-schema.md".
    Also tries with "axioms/" and "code/" prefixes for each suffix. *)
let try_resolve ~(base_dir : string) (path : string) : string option =
  let parts = String.split_on_char '/' path in
  let prefixes = [""; "axioms/"; "code/"] in
  let rec try_suffixes idx =
    if idx >= List.length parts
    then None
    else
      let suffix =
        let rec skip n lst =
          if n <= 0
          then lst
          else
            match lst with
            | [] -> []
            | _ :: t -> skip (n - 1) t
        in
        skip idx parts |> String.concat "/"
      in
      let found =
        List.exists
          (fun p ->
            let candidate = Filename.concat base_dir (p ^ suffix) in
            Sys.file_exists candidate )
          prefixes
      in
      if found
      then begin
        let p =
          List.find
            (fun p ->
              let candidate = Filename.concat base_dir (p ^ suffix) in
              Sys.file_exists candidate )
            prefixes
        in
        Some (Filename.concat base_dir (p ^ suffix))
      end
      else try_suffixes (idx + 1)
  in
  try_suffixes 0

(** Resolve a file path: relative paths are joined with base_dir.
    For absolute paths that don't exist, try resolving as relative
    under base_dir (AI models often hallucinate wrong absolute paths). *)
let resolve_path ~(base_dir : string) (path : string) : string =
  let candidate =
    if Filename.is_relative path then Filename.concat base_dir path else path
  in
  if Sys.file_exists candidate && path_within ~root:base_dir candidate
  then candidate
  else
    let relative =
      if String.length path > 0 && String.get path 0 = '/'
      then String.sub path 1 (String.length path - 1)
      else path
    in
    let under_base = Filename.concat base_dir relative in
    if Sys.file_exists under_base && path_within ~root:base_dir under_base
    then under_base
    else
      match try_resolve ~base_dir path with
      | Some found when path_within ~root:base_dir found -> found
      | _ -> under_base

(** Execute a tool call by name *)
let execute ~(base_dir : string) (name : string) (input : Yojson.Safe.t) :
    string =
  let open Yojson.Safe.Util in
  let scalar_string =
    match input with
    | `String s when String.trim s <> "" -> Some s
    | _ -> None
  in
  match name with
  | "read_file" -> (
    match require_tool_string input ~field:"path" ~fallback:scalar_string with
    | Error msg -> "Error: " ^ msg
    | Ok path ->
        let full_path = resolve_path ~base_dir path in
        read_file ~path:full_path )
  | "write_file" -> (
    match
      (require_json_string input "path", require_json_string input "content")
    with
    | Error msg, _
     |_, Error msg ->
        "Error: " ^ msg
    | Ok path, Ok content ->
        let full_path = resolve_path ~base_dir path in
        (match reject_axiom_write ~base_dir full_path with
         | Error msg -> "Error: " ^ msg
         | Ok () ->
             write_file ~path:full_path ~content ;
             "File written successfully") )
  | "edit_file" -> (
    match
      ( require_json_string input "path"
      , require_json_string input "old_string"
      , require_json_string input "new_string" )
    with
    | Error msg, _, _
     |_, Error msg, _
     |_, _, Error msg ->
        "Error: " ^ msg
    | Ok path, Ok old_string, Ok new_string -> (
        let full_path = resolve_path ~base_dir path in
        match reject_axiom_write ~base_dir full_path with
        | Error msg -> "Error: " ^ msg
        | Ok () -> (
            match edit_file ~path:full_path ~old_string ~new_string with
            | Ok () -> "File edited successfully"
            | Error msg -> Printf.sprintf "Error: %s" msg ) ) )
  | "glob_search" -> (
    match require_tool_string input ~field:"pattern" ~fallback:scalar_string with
    | Error msg -> "Error: " ^ msg
    | Ok pattern ->
        let base_dir' =
          match input |> member "base_dir" |> to_string_option with
          | Some d when String.trim d <> "" -> resolve_dir ~base_dir d
          | _ -> base_dir
        in
        String.concat "\n" (glob_search ~pattern ~base_dir:base_dir') )
  | "grep_search" -> (
    match require_tool_string input ~field:"pattern" ~fallback:scalar_string with
    | Error msg -> "Error: " ^ msg
    | Ok pattern ->
        let base_dir' =
          match input |> member "base_dir" |> to_string_option with
          | Some d when String.trim d <> "" -> resolve_dir ~base_dir d
          | _ -> base_dir
        in
        grep_search ~pattern ~base_dir:base_dir' )
  | "bash" -> (
    match require_tool_string input ~field:"command" ~fallback:scalar_string with
    | Error msg -> "Error: " ^ msg
    | Ok command ->
        if bash_touches_axioms ~base_dir command
        then "Error: Modifying axioms/ via bash is forbidden. Axioms are read-only."
        else (
      match bash ~command with
      | Ok output -> output
      | Error (output, code) -> Printf.sprintf "Exit code %d:\n%s" code output ))
  | "TodoWrite" ->
      let todos_arr = input |> member "todos" |> to_list in
      let todos_list =
        List.map
          (fun item ->
            let task =
              match item |> member "task" with
              | `String s -> s
              | task_json -> (
                  match
                    task_json |> member "description" |> to_string_option
                  with
                  | Some d -> d
                  | None -> "" )
            in
            let status =
              match item |> member "status" |> to_string_option with
              | Some s -> s
              | None -> "pending"
            in
            (task, status) )
          todos_arr
      in
      todo_write ~todos_list
  | _ -> Printf.sprintf "Unknown tool: %s" name
