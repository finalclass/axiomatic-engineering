(** Snapshot management — freeze/current diffing *)

open Types

(** Run a shell command and return stdout *)
let run_cmd (cmd : string) : string =
  let ic = Unix.open_process_in cmd in
  let buf = Buffer.create 1024 in
  (try while true do
    Buffer.add_char buf (input_char ic)
  done with End_of_file -> ());
  let _ = Unix.close_process_in ic in
  Buffer.contents buf

(** Run a shell command, ignoring output *)
let run_cmd_unit (cmd : string) : unit =
  let _ = Sys.command cmd in ()

(** Ensure a directory exists *)
let ensure_dir (path : string) : unit =
  run_cmd_unit (Printf.sprintf "mkdir -p %s" (Filename.quote path))

(** Remove directory contents *)
let clear_dir (path : string) : unit =
  if Sys.file_exists path then
    run_cmd_unit (Printf.sprintf "rm -rf %s/*" (Filename.quote path))

(** Copy axioms/ to .axioms/current/ *)
let create_snapshot ~(project_path : string) : unit =
  let axioms_dir = Filename.concat project_path "axioms" in
  let dot_axioms = Filename.concat project_path ".axioms" in
  let current_dir = Filename.concat dot_axioms "current" in
  ensure_dir dot_axioms;
  ensure_dir current_dir;
  clear_dir current_dir;
  (* Copy all .md files and other relevant files *)
  run_cmd_unit (Printf.sprintf "cp -r %s/* %s/ 2>/dev/null || true"
    (Filename.quote axioms_dir) (Filename.quote current_dir))

(** Check if a string ends with the given suffix *)
let ends_with s suffix =
  let sl = String.length s and sufl = String.length suffix in
  sl >= sufl && String.sub s (sl - sufl) sufl = suffix

(** Extract the relative file path after "freeze/" or "current/" in a path.
    Works with both relative paths like "current/file.md" and absolute paths
    like "/tmp/snap-123/.axioms/current/file.md". *)
let strip_snapshot_prefix (path : string) : string =
  (* Find the last occurrence of "/freeze/" or "/current/" in the path,
     or check if it starts with "freeze/" or "current/" *)
  let try_strip marker =
    let mlen = String.length marker in
    (* Check "marker/" at start *)
    let plen = String.length path in
    if plen > mlen && String.sub path 0 mlen = marker then
      Some (String.sub path mlen (plen - mlen))
    else
      (* Search for "/marker/" in the path *)
      let slash_marker = "/" ^ marker in
      let smlen = String.length slash_marker in
      let rec search i =
        if i + smlen > plen then None
        else if String.sub path i smlen = slash_marker then
          Some (String.sub path (i + smlen) (plen - i - smlen))
        else search (i + 1)
      in
      search 0
  in
  match try_strip "current/" with
  | Some rest -> rest
  | None ->
    match try_strip "freeze/" with
    | Some rest -> rest
    | None ->
      (* Fallback: strip up to first / *)
      match String.index_opt path '/' with
      | Some i -> String.sub path (i + 1) (String.length path - i - 1)
      | None -> path

(** Determine if an "Only in" directory refers to freeze or current.
    The dir part may be relative ("freeze") or absolute ("/tmp/.../freeze"). *)
let classify_only_in_dir (dir : string) : [ `Freeze | `Current | `Unknown ] =
  if dir = "freeze" || ends_with dir "/freeze" then `Freeze
  else if dir = "current" || ends_with dir "/current" then `Current
  else `Unknown

(** Parse unified diff output into axiom changes *)
let parse_diff_output (diff_output : string) : (string * axiom_change) list =
  if String.trim diff_output = "" then []
  else begin
    let lines = String.split_on_char '\n' diff_output in
    let changes = Hashtbl.create 8 in
    let current_file = ref None in
    let current_sections = ref [] in
    let is_new_file = ref false in
    let is_deleted_file = ref false in

    let flush () =
      match !current_file with
      | Some f ->
        let change =
          if !is_new_file then Added
          else if !is_deleted_file then Deleted
          else Modified (List.rev !current_sections)
        in
        Hashtbl.replace changes f change;
        current_file := None;
        current_sections := [];
        is_new_file := false;
        is_deleted_file := false
      | None -> ()
    in

    List.iter (fun line ->
      if String.length line >= 4 && String.sub line 0 4 = "diff" then begin
        flush ();
        (* Extract filename from "diff -ru freeze/file.md current/file.md"
           or "diff -ru /tmp/.../freeze/file.md /tmp/.../current/file.md" *)
        let parts = String.split_on_char ' ' line in
        let last = List.nth_opt parts (List.length parts - 1) in
        (match last with
         | Some path ->
           let basename = strip_snapshot_prefix path in
           current_file := Some basename
         | None -> ())
      end
      else if String.length line >= 8 && String.sub line 0 8 = "Only in " then begin
        (* "Only in <dir>: <filename>" — dir may be relative or absolute *)
        flush ();
        (* Split on ": " to get dir and filename.
           Format: "Only in <dir>: <name>" — first ": " after "Only in " *)
        let rest = String.sub line 8 (String.length line - 8) in
        let colon_pos =
          let rec find i =
            if i + 1 >= String.length rest then None
            else if rest.[i] = ':' && i + 1 < String.length rest && rest.[i+1] = ' ' then Some i
            else find (i + 1)
          in
          find 0
        in
        (match colon_pos with
         | Some cp ->
           let dir = String.sub rest 0 cp in
           let name = String.trim (String.sub rest (cp + 1) (String.length rest - cp - 1)) in
           (match classify_only_in_dir dir with
            | `Freeze -> Hashtbl.replace changes name Deleted
            | `Current -> Hashtbl.replace changes name Added
            | `Unknown -> ())
         | None -> ())
      end
      else if String.length line >= 4 && String.sub line 0 4 = "--- " then begin
        if String.length line >= 13 && String.sub line 4 9 = "/dev/null" then
          is_new_file := true
      end
      else if String.length line >= 4 && String.sub line 0 4 = "+++ " then begin
        if String.length line >= 13 && String.sub line 4 9 = "/dev/null" then
          is_deleted_file := true
      end
      else if String.length line >= 1 then begin
        (* Look for changed section headings in context *)
        let c = line.[0] in
        if (c = '+' || c = '-') && String.length line > 1 then begin
          let rest = String.sub line 1 (String.length line - 1) in
          let trimmed = String.trim rest in
          if String.length trimmed >= 3 && String.sub trimmed 0 3 = "## " then begin
            let heading = String.sub trimmed 3 (String.length trimmed - 3) in
            let anchor = Loader.heading_to_anchor heading in
            if not (List.mem anchor !current_sections) then
              current_sections := anchor :: !current_sections
          end
        end
      end
    ) lines;
    flush ();
    Hashtbl.fold (fun k v acc -> (k, v) :: acc) changes []
  end

(** Compare .axioms/current/ with .axioms/freeze/
    Returns None if freeze/ doesn't exist (treat as full sync),
    Some [] if no changes, Some changes otherwise *)
let diff ~(project_path : string) : (string * axiom_change) list option =
  let dot_axioms = Filename.concat project_path ".axioms" in
  let freeze_dir = Filename.concat dot_axioms "freeze" in
  let current_dir = Filename.concat dot_axioms "current" in
  if not (Sys.file_exists freeze_dir) then
    None (* No freeze = first run = full sync *)
  else begin
    let cmd = Printf.sprintf "diff -ru %s %s 2>/dev/null || true"
      (Filename.quote freeze_dir) (Filename.quote current_dir) in
    let output = run_cmd cmd in
    Some (parse_diff_output output)
  end

(** Copy .axioms/current/ to .axioms/freeze/ *)
let save_freeze ~(project_path : string) : unit =
  let dot_axioms = Filename.concat project_path ".axioms" in
  let freeze_dir = Filename.concat dot_axioms "freeze" in
  let current_dir = Filename.concat dot_axioms "current" in
  ensure_dir freeze_dir;
  clear_dir freeze_dir;
  run_cmd_unit (Printf.sprintf "cp -r %s/* %s/ 2>/dev/null || true"
    (Filename.quote current_dir) (Filename.quote freeze_dir))
