(** @axiom marker validation in code/ *)

open Types

type marker_error =
  | Unpaired_open of { file: string; marker: string }
  | Unpaired_close of { file: string; marker: string }
  | Unknown_axiom of { file: string; marker: string }
  | Orphaned_code of { file: string; line: int }

(** Marker patterns for different comment styles *)
let marker_patterns = [
  (* HTML: <!-- @axiom: X --> and <!-- /@axiom: X --> *)
  ("<!-- @axiom: ", " -->", "<!-- /@axiom: ", " -->");
  (* JS/CSS single-line: // @axiom: X and // /@axiom: X *)
  ("// @axiom: ", "", "// /@axiom: ", "");
  (* CSS block: /* @axiom: X */ and /* /@axiom: X */ *)
  ("/* @axiom: ", " */", "/* /@axiom: ", " */");
  (* Bash: # @axiom: X and # /@axiom: X *)
  ("# @axiom: ", "", "# /@axiom: ", "");
]

(** Try to extract an opening @axiom marker from a line *)
let extract_open_marker (line : string) : string option =
  let trimmed = String.trim line in
  List.find_map (fun (open_prefix, open_suffix, _, _) ->
    let plen = String.length open_prefix in
    if String.length trimmed >= plen && String.sub trimmed 0 plen = open_prefix then begin
      let rest = String.sub trimmed plen (String.length trimmed - plen) in
      let marker =
        if open_suffix <> "" then
          let slen = String.length open_suffix in
          if String.length rest >= slen &&
             String.sub rest (String.length rest - slen) slen = open_suffix then
            String.sub rest 0 (String.length rest - slen) |> String.trim
          else
            String.trim rest
        else
          String.trim rest
      in
      if marker <> "" then Some marker else None
    end else None
  ) marker_patterns

(** Try to extract a closing /@axiom marker from a line *)
let extract_close_marker (line : string) : string option =
  let trimmed = String.trim line in
  List.find_map (fun (_, _, close_prefix, close_suffix) ->
    let plen = String.length close_prefix in
    if String.length trimmed >= plen && String.sub trimmed 0 plen = close_prefix then begin
      let rest = String.sub trimmed plen (String.length trimmed - plen) in
      let marker =
        if close_suffix <> "" then
          let slen = String.length close_suffix in
          if String.length rest >= slen &&
             String.sub rest (String.length rest - slen) slen = close_suffix then
            String.sub rest 0 (String.length rest - slen) |> String.trim
          else
            String.trim rest
        else
          String.trim rest
      in
      if marker <> "" then Some marker else None
    end else None
  ) marker_patterns

(** Parse @axiom markers from a single file's content.
    Returns list of (axiom_id, line_number) for opening markers. *)
let parse_markers (content : string) : (string * int) list =
  let lines = String.split_on_char '\n' content in
  let results = ref [] in
  List.iteri (fun i line ->
    match extract_open_marker line with
    | Some marker -> results := (marker, i + 1) :: !results
    | None -> ()
  ) lines;
  List.rev !results

(** Collect all files in a directory recursively, skipping tests/ *)
let rec collect_files (dir : string) : string list =
  if not (Sys.file_exists dir) then []
  else begin
    let entries = Sys.readdir dir |> Array.to_list in
    List.concat_map (fun entry ->
      let path = Filename.concat dir entry in
      if Sys.is_directory path then begin
        (* Skip tests/ directory *)
        if entry = "tests" then []
        else collect_files path
      end else
        [path]
    ) entries
  end

(** Build the set of valid axiom IDs from the system.
    Markers anchor to whole axiom files, not sections. *)
let valid_axiom_ids (system : axiom_system) : string list =
  List.map (fun (a : axiom) -> a.id) system.axioms

(** Strip #anchor from a marker, returning just the axiom file ID *)
let strip_anchor (marker : string) : string =
  match String.index_opt marker '#' with
  | Some pos -> String.sub marker 0 pos
  | None -> marker

(** Validate all markers in a single file *)
let validate_file ~(valid_ids : string list) (file_path : string) (content : string) : marker_error list =
  let lines = String.split_on_char '\n' content in
  let open_stack = ref [] in (* stack of (marker_name, line_number) *)
  let errors = ref [] in

  List.iteri (fun i line ->
    let line_num = i + 1 in
    match extract_open_marker line with
    | Some marker ->
      (* Check if axiom file exists (strip #anchor if present) *)
      let axiom_id = strip_anchor marker in
      if not (List.mem axiom_id valid_ids) then
        errors := Unknown_axiom { file = file_path; marker } :: !errors;
      open_stack := (marker, line_num) :: !open_stack
    | None ->
      match extract_close_marker line with
      | Some marker ->
        (* Find matching open *)
        let found = ref false in
        open_stack := List.filter (fun (m, _) ->
          if not !found && m = marker then begin
            found := true;
            false (* remove from stack *)
          end else true
        ) !open_stack;
        if not !found then
          errors := Unpaired_close { file = file_path; marker } :: !errors
      | None -> ()
  ) lines;

  (* Any remaining open markers are unpaired *)
  List.iter (fun (marker, _) ->
    errors := Unpaired_open { file = file_path; marker } :: !errors
  ) !open_stack;

  List.rev !errors

(** Read file content *)
let read_file_content (path : string) : string option =
  if Sys.file_exists path then begin
    let ic = In_channel.open_text path in
    let content = In_channel.input_all ic in
    In_channel.close ic;
    Some content
  end else
    None

(** Validate all markers in code/ against the axiom system *)
let validate ~(code_dir : string) (system : axiom_system) : (unit, marker_error list) result =
  if not (Sys.file_exists code_dir) then Ok ()
  else begin
    let valid_ids = valid_axiom_ids system in
    let files = collect_files code_dir in
    let all_errors = List.concat_map (fun file_path ->
      match read_file_content file_path with
      | Some content -> validate_file ~valid_ids file_path content
      | None -> []
    ) files in
    if all_errors = [] then Ok ()
    else Error all_errors
  end

(** Format marker error for display *)
let error_to_string = function
  | Unpaired_open { file; marker } ->
    Printf.sprintf "%s: opening @axiom: %s has no matching close" file marker
  | Unpaired_close { file; marker } ->
    Printf.sprintf "%s: closing /@axiom: %s has no matching open" file marker
  | Unknown_axiom { file; marker } ->
    Printf.sprintf "%s: @axiom: %s does not match any axiom" file marker
  | Orphaned_code { file; line } ->
    Printf.sprintf "%s:%d: code outside @axiom markers" file line
