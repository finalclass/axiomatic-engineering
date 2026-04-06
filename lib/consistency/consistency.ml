(** Consistency checks on the axiom system *)

open Types

type error =
  | Missing_link of
      { from_axiom: string
      ; target: string }
  | Label_without_phase of string
  | Missing_glossary_key of
      { label: string
      ; key: string }

(** Check that all referenced axiom files exist in the system *)
let check_references (system : axiom_system) : error list =
  let known_ids = List.map (fun (a : axiom) -> a.id) system.axioms in
  let resolve_ref ~base_id ref_path =
    let base_dir = Filename.dirname base_id in
    let ref_path' =
      if String.length ref_path >= 2 && String.sub ref_path 0 2 = "./"
      then String.sub ref_path 2 (String.length ref_path - 2)
      else ref_path
    in
    if base_dir = "" then ref_path' else Filename.concat base_dir ref_path'
  in
  List.concat_map
    (fun (a : axiom) ->
      List.filter_map
        (fun ref_path ->
          let resolved = resolve_ref ~base_id:a.id ref_path in
          if List.mem resolved known_ids
          then None
          else Some (Missing_link {from_axiom= a.id; target= ref_path}) )
        a.refs )
    system.axioms

(** Check that all labels have at least one phase *)
let check_label_phases (system : axiom_system) : error list =
  List.filter_map
    (fun (ld : label_def) ->
      if ld.phases = [] then Some (Label_without_phase ld.name) else None )
    system.label_defs

(** Check that satisfaction glossary keys actually exist.
    Labels with Satisfaction(-1.0) have unresolved keys. *)
let check_glossary_keys (system : axiom_system) : error list =
  List.filter_map
    (fun (ld : label_def) ->
      let has_unresolved =
        List.exists
          (fun p ->
            match p with
            | Satisfaction f -> f = -1.0
            | _ -> false )
          ld.phases
      in
      if has_unresolved
      then Some (Missing_glossary_key {label= ld.name; key= "(unresolved)"})
      else None )
    system.label_defs

(** Run all consistency checks. Returns Ok () or Error with list of problems. *)
let check (system : axiom_system) : (unit, error list) result =
  let errors =
    check_references system
    @ check_label_phases system
    @ check_glossary_keys system
  in
  if errors = [] then Ok () else Error errors

(** Format error for display *)
let error_to_string = function
  | Missing_link {from_axiom; target} ->
      Printf.sprintf
        "Axiom '%s' references '%s' which does not exist"
        from_axiom
        target
  | Label_without_phase name ->
      Printf.sprintf
        "Label '[%s]' has no phase (@implementation/@validation/@satisfaction)"
        name
  | Missing_glossary_key {label; key} ->
      Printf.sprintf
        "Label '[%s]' references glossary key '%s' which does not exist"
        label
        key

let check_exn (system : axiom_system) =
  match check system with
  | Ok () -> Printf.printf "All checks passed.\n%!"
  | Error errs ->
      List.iter (fun e -> Printf.eprintf "  %s\n" (error_to_string e)) errs ;
      exit 1

let check_semantic_exn ~(system : Types.system) =
  let _system_prompt =
    "You are a consistency checker. Analyze the axioms below for semantic \
     contradictions — requirements that conflict with each other, impossible \
     constraints, or mutually exclusive goals. If you find NO contradictions, \
     respond with exactly: NO_CONTRADICTIONS. If you find contradictions, \
     describe each one clearly."
  in
  let axiom_content =
    system.axioms
    |> List.map (fun axiom ->
        Fmt.str
          "**%s**\n\n%s\n----------------------------------------"
          axiom.id
          axiom.raw_content )
    |> String.concat "\n"
  in
  let _prompt =
    Fmt.str "Analyze these axioms for contradictions:\n\n%s" axiom_content
  in

  Fmt.pr "CALL AI"
