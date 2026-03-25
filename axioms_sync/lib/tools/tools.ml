(** Tool definitions and execution for AI agents *)

open Ai_access

(** Read a file's content *)
let read_file ~(path : string) : string =
  if Sys.file_exists path then begin
    let ic = In_channel.open_text path in
    let content = In_channel.input_all ic in
    In_channel.close ic;
    content
  end else
    Printf.sprintf "Error: file not found: %s" path

(** Write content to a file *)
let write_file ~(path : string) ~(content : string) : unit =
  (* Ensure parent directory exists *)
  let dir = Filename.dirname path in
  if not (Sys.file_exists dir) then
    ignore (Sys.command (Printf.sprintf "mkdir -p %s" (Filename.quote dir)));
  let oc = Out_channel.open_text path in
  Out_channel.output_string oc content;
  Out_channel.close oc

(** Replace old_string with new_string in a file *)
let edit_file ~(path : string) ~(old_string : string) ~(new_string : string) : (unit, string) result =
  if not (Sys.file_exists path) then
    Error (Printf.sprintf "File not found: %s" path)
  else begin
    let ic = In_channel.open_text path in
    let content = In_channel.input_all ic in
    In_channel.close ic;
    match String.split_on_char '\x00' content with
    | _ ->
      (* Check if old_string exists in the file *)
      let idx = ref None in
      let olen = String.length old_string in
      let clen = String.length content in
      if olen = 0 then
        Error "old_string is empty"
      else begin
        let i = ref 0 in
        while !i <= clen - olen && !idx = None do
          if String.sub content !i olen = old_string then
            idx := Some !i;
          incr i
        done;
        match !idx with
        | None -> Error (Printf.sprintf "old_string not found in %s" path)
        | Some pos ->
          let before = String.sub content 0 pos in
          let after = String.sub content (pos + olen) (clen - pos - olen) in
          let new_content = before ^ new_string ^ after in
          let oc = Out_channel.open_text path in
          Out_channel.output_string oc new_content;
          Out_channel.close oc;
          Ok ()
      end
  end

(** List files matching a simple glob pattern in a directory.
    Supports * wildcard in the filename part. *)
let list_files ~(glob : string) ~(base_dir : string) : string list =
  let cmd = Printf.sprintf "find %s -name %s -type f 2>/dev/null | sort"
    (Filename.quote base_dir) (Filename.quote glob) in
  let ic = Unix.open_process_in cmd in
  let results = ref [] in
  (try while true do
    results := input_line ic :: !results
  done with End_of_file -> ());
  let _ = Unix.close_process_in ic in
  List.rev !results

(** Run a bash command, return stdout+stderr *)
let bash ~(command : string) : (string, string * int) result =
  let cmd = Printf.sprintf "(%s) 2>&1" command in
  let ic = Unix.open_process_in cmd in
  let buf = Buffer.create 1024 in
  (try while true do
    Buffer.add_char buf (input_char ic)
  done with End_of_file -> ());
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

let object_schema ~required (properties : (string * Yojson.Safe.t) list) : Yojson.Safe.t =
  `Assoc [
    ("type", `String "object");
    ("properties", `Assoc properties);
    ("required", `List (List.map (fun s -> `String s) required));
  ]

(** Tool definitions *)
let read_file_def : tool_def = {
  name = "read_file";
  description = "Read the contents of a file at the given path";
  input_schema = object_schema ~required:["path"] [
    ("path", string_prop ~description:"Absolute path to the file to read");
  ];
}

let write_file_def : tool_def = {
  name = "write_file";
  description = "Write content to a file, creating it if it doesn't exist";
  input_schema = object_schema ~required:["path"; "content"] [
    ("path", string_prop ~description:"Absolute path to the file to write");
    ("content", string_prop ~description:"Content to write to the file");
  ];
}

let edit_file_def : tool_def = {
  name = "edit_file";
  description = "Replace old_string with new_string in a file (exact match)";
  input_schema = object_schema ~required:["path"; "old_string"; "new_string"] [
    ("path", string_prop ~description:"Absolute path to the file to edit");
    ("old_string", string_prop ~description:"Exact string to find and replace");
    ("new_string", string_prop ~description:"Replacement string");
  ];
}

let list_files_def : tool_def = {
  name = "list_files";
  description = "List files matching a glob pattern";
  input_schema = object_schema ~required:["glob"] [
    ("glob", string_prop ~description:"Glob pattern (e.g. '*.md', '*.html')");
  ];
}

let bash_def : tool_def = {
  name = "bash";
  description = "Run a bash command and return stdout+stderr";
  input_schema = object_schema ~required:["command"] [
    ("command", string_prop ~description:"The bash command to execute");
  ];
}

(** Tool definitions filtered by context markers.
    +code -> read_file, write_file, edit_file, list_files
    +browser -> bash (for agent-browser)
    +api -> bash (restricted to curl)
    default -> bash *)
let tool_defs_for_markers (markers : Types.context_marker list) : tool_def list =
  let has_code = List.mem Types.Code markers in
  let has_browser = List.mem Types.Browser markers in
  let has_api = List.mem Types.Api markers in
  let tools = ref [] in
  if has_code then
    tools := read_file_def :: write_file_def :: edit_file_def :: list_files_def :: !tools;
  if has_browser || has_api then
    tools := bash_def :: !tools;
  (* Default: if no specific markers, provide bash *)
  if not has_code && not has_browser && not has_api then
    tools := bash_def :: !tools;
  List.rev !tools

(** Extract a string field from JSON input *)
let json_string (input : Yojson.Safe.t) (field : string) : string =
  let open Yojson.Safe.Util in
  input |> member field |> to_string

(** Execute a tool call by name *)
let execute ~(base_dir : string) (name : string) (input : Yojson.Safe.t) : string =
  match name with
  | "read_file" ->
    let path = json_string input "path" in
    let full_path = if Filename.is_relative path then Filename.concat base_dir path else path in
    read_file ~path:full_path
  | "write_file" ->
    let path = json_string input "path" in
    let content = json_string input "content" in
    let full_path = if Filename.is_relative path then Filename.concat base_dir path else path in
    write_file ~path:full_path ~content;
    "File written successfully"
  | "edit_file" ->
    let path = json_string input "path" in
    let old_string = json_string input "old_string" in
    let new_string = json_string input "new_string" in
    let full_path = if Filename.is_relative path then Filename.concat base_dir path else path in
    (match edit_file ~path:full_path ~old_string ~new_string with
     | Ok () -> "File edited successfully"
     | Error msg -> Printf.sprintf "Error: %s" msg)
  | "list_files" ->
    let glob = json_string input "glob" in
    let files = list_files ~glob ~base_dir in
    String.concat "\n" files
  | "bash" ->
    let command = json_string input "command" in
    (match bash ~command with
     | Ok output -> output
     | Error (output, code) ->
       Printf.sprintf "Exit code %d:\n%s" code output)
  | _ ->
    Printf.sprintf "Unknown tool: %s" name
