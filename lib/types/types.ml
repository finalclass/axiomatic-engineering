(** Core types for axioms-sync *)

type phase =
  | Implementation
  | Validation
  | Satisfaction of float (** threshold 0.0–1.0 *)

type context_marker = Code | Browser | Api | Axioms

type model_class = Smart | Balanced | Fast

type label_def = {
  name: string;
  phases: phase list;
  markers: context_marker list;
  model_class: model_class option; (** None = use default for phase *)
  description: string;
}

type section = {
  heading: string;
  anchor: string;
  content: string;
  labels: string list; (** label names after cascade *)
}

type axiom = {
  id: string; (** e.g. "patient-client/booking.md" *)
  name: string;
  sections: section list;
  labels: string list; (** file-level labels after cascade *)
  refs: string list; (** links to other axiom files *)
  raw_content: string;
}

type glossary_entry = {
  term: string;
  definition: string;
}

type axiom_system = {
  name: string;
  glossary: glossary_entry list;
  label_defs: label_def list;
  axioms: axiom list;
  global_labels: string list; (** labels from ## Axioms section *)
}

type axiom_change =
  | Added
  | Deleted
  | Modified of string list (** changed section anchors *)

type task = {
  axiom_id: string;
  section_anchor: string option;
  label: label_def;
  phase: phase;
  context: string; (** filtered axiom content for this agent *)
  model_class: model_class; (** resolved: label override or phase default *)
}

type config = {
  project_path: string;
  mode: [ `Diff | `Full ];
  implementer: string; (** model alias e.g. "opus4.6" *)
  planner: string;
  smart: string;
  balanced: string;
  fast: string;
  preprompt: string; (** extra system prompt prepended to every AI call *)
}

let default_config = {
  project_path = ".";
  mode = `Diff;
  implementer = "opus4.6";
  planner = "sonnet4.6";
  smart = "opus4.6";
  balanced = "sonnet4.6";
  fast = "haiku4.5";
  preprompt = "";
}

(** Resolve model class for a task. Label override takes priority, then phase default. *)
let resolve_model_class ?label_class phase =
  match label_class with
  | Some c -> c
  | None ->
    match phase with
    | Implementation -> Smart
    | Validation -> Balanced
    | Satisfaction _ -> Fast

(** Map model class to model alias from config *)
let model_alias_of_class config = function
  | Smart -> config.smart
  | Balanced -> config.balanced
  | Fast -> config.fast
