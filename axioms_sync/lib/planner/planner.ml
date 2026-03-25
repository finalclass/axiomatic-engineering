(** Planner — generates filtered task lists per phase *)

open Types

(** Check if a label name has a given phase in its definition *)
let label_has_phase (system : axiom_system) (label_name : string) (phase_check : phase -> bool) : bool =
  match List.find_opt (fun (ld : label_def) -> ld.name = label_name) system.label_defs with
  | Some ld -> List.exists phase_check ld.phases
  | None -> false

(** Check if a label is implementation-visible (has @implementation) *)
let is_implementation_label (system : axiom_system) (label_name : string) : bool =
  label_has_phase system label_name (fun p -> match p with Implementation -> true | _ -> false)

(** Check if a label is validation-only (has @validation but NOT @implementation) *)
let is_validation_only_label (system : axiom_system) (label_name : string) : bool =
  let has_validation = label_has_phase system label_name (fun p ->
    match p with Validation -> true | _ -> false) in
  let has_implementation = is_implementation_label system label_name in
  has_validation && not has_implementation

(** Check if a label is satisfaction-only *)
let is_satisfaction_only_label (system : axiom_system) (label_name : string) : bool =
  label_has_phase system label_name (fun p ->
    match p with Satisfaction _ -> true | _ -> false)
  && not (label_has_phase system label_name (fun p ->
    match p with Implementation | Validation -> true | _ -> false))

(** Get label_def by name *)
let find_label_def (system : axiom_system) (name : string) : label_def option =
  List.find_opt (fun (ld : label_def) -> ld.name = name) system.label_defs

(** Filter axiom content: remove sections tagged with labels not in allowed set.
    For implementation: strip @validation-only and @satisfaction-only blocks. *)
let filter_content ~(allowed_labels : string list) (axiom : axiom) : string =
  let buf = Buffer.create (String.length axiom.raw_content) in
  let lines = String.split_on_char '\n' axiom.raw_content in
  let in_section = ref false in
  let section_visible = ref true in
  let header_done = ref false in

  List.iter (fun line ->
    if String.length line >= 3 && String.sub line 0 3 = "## " then begin
      in_section := true;
      section_visible := true; (* default visible, check labels below *)
      header_done := false;
      Buffer.add_string buf line;
      Buffer.add_char buf '\n'
    end
    else if !in_section && not !header_done then begin
      (* Check for label line right after section heading *)
      let trimmed = String.trim line in
      if trimmed <> "" && trimmed.[0] = '[' then begin
        let labels = Loader.parse_inline_labels trimmed in
        let label_names = List.map fst labels in
        (* If any label is NOT in allowed_labels, hide the section *)
        let has_forbidden = List.exists (fun ln ->
          not (List.mem ln allowed_labels) &&
          ln <> "" (* ignore empty *)
        ) label_names in
        if has_forbidden && label_names <> [] then
          section_visible := false;
        header_done := true;
        if !section_visible then begin
          Buffer.add_string buf line;
          Buffer.add_char buf '\n'
        end
      end else begin
        header_done := true;
        if !section_visible then begin
          Buffer.add_string buf line;
          Buffer.add_char buf '\n'
        end
      end
    end
    else begin
      if !section_visible || not !in_section then begin
        Buffer.add_string buf line;
        Buffer.add_char buf '\n'
      end
    end
  ) lines;
  Buffer.contents buf |> String.trim

(** Get axioms that are in scope based on changes *)
let axioms_in_scope (system : axiom_system) (changes : (string * axiom_change) list) : axiom list =
  if changes = [] then
    (* Full sync: all axioms *)
    system.axioms
  else
    List.filter (fun (a : axiom) ->
      List.exists (fun (id, change) ->
        id = a.id && (match change with Deleted -> false | _ -> true)
      ) changes
    ) system.axioms

(** Generate implementation tasks (Step 5 context).
    Strips @validation-only and @satisfaction-only blocks. *)
let implementation_tasks (system : axiom_system) (changes : (string * axiom_change) list)
  : task list =
  let in_scope = axioms_in_scope system changes in
  (* Collect implementation-visible label names *)
  let impl_labels = List.filter_map (fun (ld : label_def) ->
    if List.exists (fun p -> match p with Implementation -> true | _ -> false) ld.phases then
      Some ld.name
    else None
  ) system.label_defs in
  List.concat_map (fun (axiom : axiom) ->
    (* Get all labels on this axiom that have @implementation *)
    let axiom_impl_labels = List.filter (fun ln ->
      List.mem ln impl_labels
    ) axiom.labels in
    (* Also check section-level labels *)
    let section_impl_labels = List.concat_map (fun (s : section) ->
      List.filter (fun ln -> List.mem ln impl_labels) s.labels
    ) axiom.sections in
    let all_labels = axiom_impl_labels @ section_impl_labels in
    let all_labels = List.sort_uniq String.compare all_labels in
    (* Generate one task per axiom with implementation labels *)
    if all_labels <> [] then begin
      let allowed = List.filter_map (fun (ld : label_def) ->
        if List.exists (fun p -> match p with Implementation -> true | _ -> false) ld.phases then
          Some ld.name
        else if not (List.exists (fun p ->
          match p with Validation | Satisfaction _ -> true | _ -> false) ld.phases) then
          Some ld.name (* labels without any phase — keep visible *)
        else None
      ) system.label_defs in
      let context = filter_content ~allowed_labels:allowed axiom in
      List.map (fun label_name ->
        let ld = match find_label_def system label_name with
          | Some ld -> ld | None -> { name = label_name; phases = []; markers = []; model_class = None; description = "" }
        in
        {
          axiom_id = axiom.id;
          section_anchor = None;
          label = ld;
          phase = Implementation;
          context;
          model_class = resolve_model_class ?label_class:ld.model_class Implementation;
        }
      ) all_labels
    end else []
  ) in_scope

(** Generate validation tasks (Step 6 context).
    One task per label with @validation phase. *)
let validation_tasks (system : axiom_system) (changes : (string * axiom_change) list)
  : task list =
  let in_scope = axioms_in_scope system changes in
  let validation_labels = List.filter (fun (ld : label_def) ->
    List.exists (fun p -> match p with Validation -> true | _ -> false) ld.phases
  ) system.label_defs in
  List.concat_map (fun (axiom : axiom) ->
    let axiom_all_labels = axiom.labels @
      List.concat_map (fun (s : section) -> s.labels) axiom.sections in
    let axiom_all_labels = List.sort_uniq String.compare axiom_all_labels in
    List.filter_map (fun (ld : label_def) ->
      if List.mem ld.name axiom_all_labels then
        Some {
          axiom_id = axiom.id;
          section_anchor = None;
          label = ld;
          phase = Validation;
          context = axiom.raw_content;
          model_class = resolve_model_class ?label_class:ld.model_class Validation;
        }
      else None
    ) validation_labels
  ) in_scope

(** Generate satisfaction tasks (Step 7 context).
    One task per @satisfaction scenario. *)
let satisfaction_tasks (system : axiom_system) (changes : (string * axiom_change) list)
  : task list =
  let in_scope = axioms_in_scope system changes in
  let satisfaction_labels = List.filter (fun (ld : label_def) ->
    List.exists (fun p -> match p with Satisfaction _ -> true | _ -> false) ld.phases
  ) system.label_defs in
  List.concat_map (fun (axiom : axiom) ->
    let axiom_all_labels = axiom.labels @
      List.concat_map (fun (s : section) -> s.labels) axiom.sections in
    let axiom_all_labels = List.sort_uniq String.compare axiom_all_labels in
    List.filter_map (fun (ld : label_def) ->
      if List.mem ld.name axiom_all_labels then begin
        let threshold = List.find_map (fun p ->
          match p with Satisfaction f -> Some f | _ -> None
        ) ld.phases in
        let threshold = match threshold with Some f -> f | None -> 0.7 in
        Some {
          axiom_id = axiom.id;
          section_anchor = None;
          label = ld;
          phase = Satisfaction threshold;
          context = axiom.raw_content;
          model_class = resolve_model_class ?label_class:ld.model_class (Satisfaction threshold);
        }
      end else None
    ) satisfaction_labels
  ) in_scope
