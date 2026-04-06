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

(** Check if any of the given labels hides content for the current phase.
    A label hides content if the current phase is in its hidden_phases. *)
let is_hidden ~(system : axiom_system) ~(phase : phase) (labels : string list) : bool =
  if labels = [] then false (* no labels → never hidden *)
  else List.exists (fun ln ->
    match find_label_def system ln with
    | Some ld -> List.mem phase ld.hidden_phases
    | None -> false (* unknown label → not hidden *)
  ) labels

(** Extract label names from parsed labels, ignoring thresholds *)
let label_names (parsed : (string * float option) list) : string list =
  List.map fst parsed

(** Parse a line that may start with inline labels: "[label] text" or just "[label]".
    Returns (labels_found, text_after_labels).
    If labels are not at the start, returns all labels found but keeps original text. *)
let parse_line_labels (line : string) : (string * float option) list * string =
  let trimmed = String.trim line in
  if trimmed = "" then ([], line)
  else if trimmed.[0] = '[' then begin
    (* Labels at the start — find where they end *)
    let labels = Loader.parse_inline_labels trimmed in
    let rec find_end i =
      if i >= String.length trimmed then ("", labels)
      else match trimmed.[i] with
      | ']' ->
          let after = String.trim (String.sub trimmed (i + 1) (String.length trimmed - i - 1)) in
          if after <> "" && after.[0] = '['
          then find_end (i + 1) (* more labels *)
          else (after, labels)
      | _ -> find_end (i + 1)
    in
    let content_after, labels = find_end 0 in
    let content = if content_after = "" then line else content_after in
    (labels, content)
  end
  else begin
    (* Labels elsewhere — just extract them, keep original text *)
    let labels = Loader.parse_inline_labels trimmed in
    (labels, line)
  end

(** Filter axiom content with support for section-level and inline labels.

    Label scope rules:
    - Label on its own line (e.g. "[scenario]") → context switch: applies to all
      content below until a blank line or new label.
    - Label inline with text (e.g. "[scenario] Naglowek jest...") → applies only
      to that single line/paragraph.
    - Label in ## heading (e.g. "## Naglowek [scenario]") → applies to the whole
      section until the next ##.
    - Blank line → resets context to section-level labels.

    Visibility: content is hidden if any active label has the current phase
    in its hidden_phases list (e.g. `-implementation`). *)
let filter_content ~(system : axiom_system) ~(phase : phase) (axiom : axiom) : string =
  let buf = Buffer.create (String.length axiom.raw_content) in
  let lines = String.split_on_char '\n' axiom.raw_content in

  (* Section-level labels: set when we see ## heading *)
  let section_labels = ref ([] : string list) in
  (* Context labels: set by standalone label lines, reset by blank lines *)
  let context_labels = ref ([] : string list) in

  List.iter (fun line ->
    let trimmed = String.trim line in

    (* Check if this is a ## heading *)
    if String.length line >= 3 && String.sub line 0 3 = "## " then begin
      let heading_text = String.sub line 3 (String.length line - 3) in
      let labels, _ = parse_line_labels heading_text in
      let ln = label_names labels in
      section_labels := ln;
      context_labels := [];
      (* Emit heading only if not hidden *)
      if not (is_hidden ~system ~phase ln) then begin
        Buffer.add_string buf line;
        Buffer.add_char buf '\n'
      end
    end

    (* Check if this is a # heading (axiom title) — reset context *)
    else if String.length trimmed >= 2 && trimmed.[0] = '#' && trimmed.[1] = ' ' then begin
      Buffer.add_string buf line;
      Buffer.add_char buf '\n';
      section_labels := [];
      context_labels := []
    end

    (* Blank line → reset context labels *)
    else if trimmed = "" then begin
      Buffer.add_string buf line;
      Buffer.add_char buf '\n';
      context_labels := []
    end

    else begin
      (* Parse labels from this line *)
      let labels, content = parse_line_labels line in
      let ln = label_names labels in

      if labels <> [] then begin
        (* Determine if this is a standalone label line or inline *)
        if content = "" || String.trim content = "" then begin
          (* Standalone label line — context switch *)
          let hidden = is_hidden ~system ~phase ln in
          if not hidden then begin
            Buffer.add_string buf line;
            Buffer.add_char buf '\n'
          end;
          context_labels := ln
        end
        else begin
          (* Inline label — applies only to this line *)
          if not (is_hidden ~system ~phase ln) then begin
            Buffer.add_string buf line;
            Buffer.add_char buf '\n'
          end
        end
      end
      else begin
        (* No labels on this line — check section and context *)
        let effective_labels = !context_labels @ !section_labels in
        if not (is_hidden ~system ~phase effective_labels) then begin
          Buffer.add_string buf line;
          Buffer.add_char buf '\n'
        end
      end
    end
  ) lines;
  Buffer.contents buf |> String.trim

(** Get axioms that are in scope based on changes *)
let axioms_in_scope (system : axiom_system) (changes : (axiom * axiom_change) list) : axiom list =
  if changes = [] then
    (* Full sync: all axioms *)
    system.axioms
  else
    List.filter_map (fun (a, change) ->
      match change with Deleted -> None | _ -> Some a
    ) changes

(** Generate implementation tasks (Step 5 context).
    Strips @validation-only and @satisfaction-only blocks. *)
let implementation_tasks (system : axiom_system) (changes : (axiom * axiom_change) list)
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
    (* Also check inline labels *)
    let inline_impl_labels = List.filter (fun ln ->
      List.mem ln impl_labels
    ) axiom.inline_labels in
    let all_labels = axiom_impl_labels @ section_impl_labels @ inline_impl_labels in
    let all_labels = List.sort_uniq String.compare all_labels in
    (* Generate one task per axiom with implementation labels *)
    if all_labels <> [] then begin
      let context = filter_content ~system ~phase:Implementation axiom in
      List.map (fun label_name ->
        let ld = match find_label_def system label_name with
          | Some ld -> ld | None -> { name = label_name; phases = []; hidden_phases = []; markers = []; model_class = None; description = "" }
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
let validation_tasks (system : axiom_system) (changes : (axiom * axiom_change) list)
  : task list =
  let in_scope = axioms_in_scope system changes in
  let validation_labels = List.filter (fun (ld : label_def) ->
    List.exists (fun p -> match p with Validation -> true | _ -> false) ld.phases
  ) system.label_defs in
  List.concat_map (fun (axiom : axiom) ->
    let axiom_all_labels = axiom.labels @
      List.concat_map (fun (s : section) -> s.labels) axiom.sections @
      axiom.inline_labels in
    let axiom_all_labels = List.sort_uniq String.compare axiom_all_labels in
    let context = filter_content ~system ~phase:Validation axiom in
    List.filter_map (fun (ld : label_def) ->
      if List.mem ld.name axiom_all_labels then
        Some {
          axiom_id = axiom.id;
          section_anchor = None;
          label = ld;
          phase = Validation;
          context;
          model_class = resolve_model_class ?label_class:ld.model_class Validation;
        }
      else None
    ) validation_labels
  ) in_scope

(** Generate satisfaction tasks (Step 7 context).
    One task per @satisfaction scenario. *)
let satisfaction_tasks (system : axiom_system) (changes : (axiom * axiom_change) list)
  : task list =
  let in_scope = axioms_in_scope system changes in
  let satisfaction_labels = List.filter (fun (ld : label_def) ->
    List.exists (fun p -> match p with Satisfaction _ -> true | _ -> false) ld.phases
  ) system.label_defs in
  List.concat_map (fun (axiom : axiom) ->
    let axiom_all_labels = axiom.labels @
      List.concat_map (fun (s : section) -> s.labels) axiom.sections @
      axiom.inline_labels in
    let axiom_all_labels = List.sort_uniq String.compare axiom_all_labels in
    List.filter_map (fun (ld : label_def) ->
      if List.mem ld.name axiom_all_labels then begin
        let threshold = List.find_map (fun p ->
          match p with Satisfaction f -> Some f | _ -> None
        ) ld.phases in
        let threshold = match threshold with Some f -> f | None -> 0.7 in
        let context = filter_content ~system ~phase:(Satisfaction threshold) axiom in
        Some {
          axiom_id = axiom.id;
          section_anchor = None;
          label = ld;
          phase = Satisfaction threshold;
          context;
          model_class = resolve_model_class ?label_class:ld.model_class (Satisfaction threshold);
        }
      end else None
    ) satisfaction_labels
  ) in_scope
