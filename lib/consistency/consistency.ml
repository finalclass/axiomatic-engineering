(** Consistency checks on the axiom system *)

open Types

type error =
  | Missing_link of { from_axiom: string; target: string }
  | Duplicate_name of string
  | Label_without_phase of string
  | Missing_glossary_key of { label: string; key: string }

(** Check that all referenced axiom files exist in the system *)
let check_references (system : axiom_system) : error list =
  let known_ids = List.map (fun (a : axiom) -> a.id) system.axioms in
  List.concat_map (fun (a : axiom) ->
    List.filter_map (fun ref_path ->
      if List.mem ref_path known_ids then None
      else Some (Missing_link { from_axiom = a.id; target = ref_path })
    ) a.refs
  ) system.axioms

(** Check for duplicate axiom names *)
let check_duplicates (system : axiom_system) : error list =
  let names = List.map (fun (a : axiom) -> a.name) system.axioms in
  let seen = Hashtbl.create 16 in
  List.filter_map (fun name ->
    if Hashtbl.mem seen name then
      Some (Duplicate_name name)
    else begin
      Hashtbl.add seen name true;
      None
    end
  ) names

(** Check that all labels have at least one phase *)
let check_label_phases (system : axiom_system) : error list =
  List.filter_map (fun (ld : label_def) ->
    if ld.phases = [] then
      Some (Label_without_phase ld.name)
    else None
  ) system.label_defs

(** Check that satisfaction glossary keys actually exist.
    Labels with Satisfaction(-1.0) have unresolved keys. *)
let check_glossary_keys (system : axiom_system) : error list =
  List.filter_map (fun (ld : label_def) ->
    let has_unresolved = List.exists (fun p ->
      match p with
      | Satisfaction f -> f = -1.0
      | _ -> false
    ) ld.phases in
    if has_unresolved then
      Some (Missing_glossary_key { label = ld.name; key = "(unresolved)" })
    else None
  ) system.label_defs

(** Run all consistency checks. Returns Ok () or Error with list of problems. *)
let check (system : axiom_system) : (unit, error list) result =
  let errors =
    check_references system
    @ check_duplicates system
    @ check_label_phases system
    @ check_glossary_keys system
  in
  if errors = [] then Ok ()
  else Error errors

(** Check for semantic contradictions using AI.
    dispatch is a callback to avoid coupling to ai_access. *)
let check_semantic
    ~(dispatch : system:string -> prompt:string -> (string, string) result)
    (axiom_content : string)
  : (unit, string) result =
  let system = "You are a consistency checker. Analyze the axioms below for semantic \
    contradictions — requirements that conflict with each other, impossible constraints, \
    or mutually exclusive goals. If you find NO contradictions, respond with exactly: \
    NO_CONTRADICTIONS. If you find contradictions, describe each one clearly." in
  let prompt = Printf.sprintf "Analyze these axioms for contradictions:\n\n%s" axiom_content in
  match dispatch ~system ~prompt with
  | Error e -> Error (Printf.sprintf "Semantic check failed: %s" e)
  | Ok text ->
    let trimmed = String.trim text in
    let needle = "NO_CONTRADICTIONS" in
    let nlen = String.length needle in
    if String.length trimmed >= nlen &&
       String.uppercase_ascii (String.sub trimmed 0 nlen) = needle
    then Ok ()
    else Error text

(** Format error for display *)
let error_to_string = function
  | Missing_link { from_axiom; target } ->
    Printf.sprintf "Axiom '%s' references '%s' which does not exist" from_axiom target
  | Duplicate_name name ->
    Printf.sprintf "Duplicate axiom name: '%s'" name
  | Label_without_phase name ->
    Printf.sprintf "Label '[%s]' has no phase (@implementation/@validation/@satisfaction)" name
  | Missing_glossary_key { label; key } ->
    Printf.sprintf "Label '[%s]' references glossary key '%s' which does not exist" label key
