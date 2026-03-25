(** Axiom loader — parses markdown, follows links, applies label cascade *)

open Types

(** Generate anchor slug from heading text.
    Lowercase, spaces to hyphens, remove non-alphanumeric (except hyphens). *)
let heading_to_anchor (heading : string) : string =
  heading
  |> String.lowercase_ascii
  |> String.to_seq
  |> Seq.map (fun c ->
    if c = ' ' || c = '\t' then '-'
    else if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c = '-' then c
    else '\x00')
  |> Seq.filter (fun c -> c <> '\x00')
  |> String.of_seq

(** Parse a context marker like "+code", "+browser", etc. *)
let parse_context_marker (s : string) : context_marker option =
  match String.lowercase_ascii s with
  | "+code" -> Some Code
  | "+browser" -> Some Browser
  | "+api" -> Some Api
  | "+axioms" -> Some Axioms
  | _ -> None

(** Parse a model class like "{smart}", "{balanced}", "{fast}" *)
let parse_model_class (s : string) : model_class option =
  match String.lowercase_ascii s with
  | "{smart}" -> Some Smart
  | "{balanced}" -> Some Balanced
  | "{fast}" -> Some Fast
  | _ -> None

(** Parse a phase like "@implementation", "@validation", "@satisfaction(0.8)" *)
let parse_phase (s : string) : phase option =
  if s = "@implementation" then Some Implementation
  else if s = "@validation" then Some Validation
  else if String.length s > 14 && String.sub s 0 14 = "@satisfaction(" then
    let inner = String.sub s 14 (String.length s - 15) in
    (* inner could be a float or a glossary key — store as-is, resolve later *)
    match float_of_string_opt inner with
    | Some f -> Some (Satisfaction f)
    | None -> Some (Satisfaction (-1.0)) (* placeholder, resolved via glossary *)
  else if s = "@satisfaction" then Some (Satisfaction 0.7)
  else None

(** Extract the satisfaction glossary key if present *)
let extract_satisfaction_key (s : string) : string option =
  if String.length s > 14 && String.sub s 0 14 = "@satisfaction(" then
    let inner = String.sub s 14 (String.length s - 15) in
    match float_of_string_opt inner with
    | Some _ -> None
    | None -> Some inner
  else None

(** Split a string into whitespace-separated tokens *)
let tokenize (s : string) : string list =
  let buf = Buffer.create 32 in
  let tokens = ref [] in
  String.iter (fun c ->
    if c = ' ' || c = '\t' then begin
      if Buffer.length buf > 0 then begin
        tokens := Buffer.contents buf :: !tokens;
        Buffer.clear buf
      end
    end else
      Buffer.add_char buf c
  ) s;
  if Buffer.length buf > 0 then
    tokens := Buffer.contents buf :: !tokens;
  List.rev !tokens

(** Parse a label definition heading like "[test] @implementation @validation +code {smart}"
    Returns label_def option. The heading text comes after "### " *)
let parse_label_heading ?(glossary : glossary_entry list = []) (heading : string) : label_def option =
  (* Extract label name from [name] *)
  match String.index_opt heading '[' with
  | None -> None
  | Some i ->
    match String.index_from_opt heading i ']' with
    | None -> None
    | Some j ->
      let name = String.sub heading (i + 1) (j - i - 1) in
      let rest = String.sub heading (j + 1) (String.length heading - j - 1) in
      let tokens = tokenize rest in
      let phases = ref [] in
      let markers = ref [] in
      let model_class_ref = ref None in
      let glossary_keys = ref [] in
      List.iter (fun tok ->
        (match parse_phase tok with
         | Some p ->
           phases := p :: !phases;
           (match extract_satisfaction_key tok with
            | Some k -> glossary_keys := k :: !glossary_keys
            | None -> ())
         | None ->
           match parse_context_marker tok with
           | Some m -> markers := m :: !markers
           | None ->
             match parse_model_class tok with
             | Some mc -> model_class_ref := Some mc
             | None -> ())
      ) tokens;
      (* Resolve glossary keys for satisfaction thresholds *)
      let phases = List.rev !phases in
      let phases = List.map (fun p ->
        match p with
        | Satisfaction (-1.0) ->
          (* Find the glossary key and resolve *)
          let key = match !glossary_keys with k :: _ -> Some k | [] -> None in
          (match key with
           | Some k ->
             let value = List.find_opt (fun (e : glossary_entry) ->
               String.lowercase_ascii e.term = String.lowercase_ascii k
             ) glossary in
             (match value with
              | Some e ->
                (match float_of_string_opt e.definition with
                 | Some f -> Satisfaction f
                 | None -> Satisfaction 0.7)
              | None -> Satisfaction (-1.0)) (* keep placeholder — consistency will catch *)
           | None -> Satisfaction 0.7)
        | other -> other
      ) phases in
      Some {
        name;
        phases;
        markers = List.rev !markers;
        model_class = !model_class_ref;
        description = ""; (* filled later from content below heading *)
      }

(** Parse glossary entries from content. Format: "- **Term** — definition" or "**Term** — definition" *)
let parse_glossary (content : string) : glossary_entry list =
  let lines = String.split_on_char '\n' content in
  List.filter_map (fun line ->
    let line = String.trim line in
    (* Strip leading "- " if present *)
    let line =
      if String.length line >= 2 && String.sub line 0 2 = "- " then
        String.sub line 2 (String.length line - 2) |> String.trim
      else line
    in
    (* Look for **Term** — definition *)
    if String.length line >= 4 && String.sub line 0 2 = "**" then
      match String.index_from_opt line 2 '*' with
      | Some i when i + 1 < String.length line && line.[i + 1] = '*' ->
        let term = String.sub line 2 (i - 2) in
        let rest = String.sub line (i + 2) (String.length line - i - 2) in
        (* Look for " — " or " - " separator *)
        let definition =
          let rest = String.trim rest in
          if String.length rest >= 4 && String.sub rest 0 4 = "\xe2\x80\x94 " then
            (* em dash UTF-8 *)
            String.sub rest 4 (String.length rest - 4) |> String.trim
          else if String.length rest >= 3 && String.sub rest 0 3 = "\xe2\x80\x94" then
            String.sub rest 3 (String.length rest - 3) |> String.trim
          else if String.length rest >= 2 && String.sub rest 0 2 = "—" then
            String.sub rest 2 (String.length rest - 2) |> String.trim
          else if String.length rest >= 3 && String.sub rest 0 3 = " — " then
            String.sub rest 3 (String.length rest - 3) |> String.trim
          else
            rest
        in
        if term <> "" && definition <> "" then
          Some { term; definition }
        else None
      | _ -> None
    else None
  ) lines

(** Extract markdown links in format [Name](./file.md) — returns relative paths *)
let extract_links (content : string) : string list =
  let links = ref [] in
  let len = String.length content in
  let i = ref 0 in
  while !i < len - 4 do
    if content.[!i] = ']' && content.[!i + 1] = '(' && content.[!i + 2] = '.' && content.[!i + 3] = '/' then begin
      (* Find closing paren *)
      let start = !i + 4 in
      match String.index_from_opt content start ')' with
      | Some j ->
        let path = String.sub content start (j - start) in
        (* Only .md files *)
        if String.length path > 3 && String.sub path (String.length path - 3) 3 = ".md" then
          links := path :: !links;
        i := j + 1
      | None -> i := !i + 1
    end else
      i := !i + 1
  done;
  List.rev !links

(** Parse labels from a line like "[label1] [label2]" or "[label1(0.9)]" *)
let parse_inline_labels (line : string) : (string * float option) list =
  let results = ref [] in
  let len = String.length line in
  let i = ref 0 in
  while !i < len do
    if line.[!i] = '[' then begin
      match String.index_from_opt line (!i + 1) ']' with
      | Some j ->
        let inner = String.sub line (!i + 1) (j - !i - 1) in
        (* Check for threshold override: [name(0.9)] *)
        (match String.index_opt inner '(' with
         | Some k when k + 1 < String.length inner ->
           let name = String.sub inner 0 k in
           let thresh_str = String.sub inner (k + 1) (String.length inner - k - 2) in
           let thresh = float_of_string_opt thresh_str in
           results := (name, thresh) :: !results
         | _ ->
           (* Make sure it doesn't look like a markdown link *)
           if not (j + 1 < len && line.[j + 1] = '(') then
             results := (inner, None) :: !results);
        i := j + 1
      | None -> i := !i + 1
    end else
      i := !i + 1
  done;
  List.rev !results

(** Parse a single axiom file into an axiom record *)
let parse_axiom_file ~(id : string) (content : string) : axiom =
  let lines = String.split_on_char '\n' content in
  (* First heading # is the axiom name *)
  let name = ref "" in
  let file_labels = ref [] in
  let sections = ref [] in
  let current_heading = ref None in
  let current_labels = ref [] in
  let current_content = Buffer.create 256 in
  let in_header_area = ref true in
  let refs = extract_links content in

  let flush_section () =
    match !current_heading with
    | Some heading ->
      let anchor = heading_to_anchor heading in
      sections := {
        heading;
        anchor;
        content = Buffer.contents current_content |> String.trim;
        labels = !current_labels;
      } :: !sections;
      Buffer.clear current_content;
      current_labels := [];
      current_heading := None
    | None ->
      Buffer.clear current_content
  in

  List.iter (fun line ->
    if String.length line >= 2 && String.sub line 0 2 = "# " && !name = "" then begin
      name := String.sub line 2 (String.length line - 2) |> String.trim;
      in_header_area := true
    end
    else if String.length line >= 3 && String.sub line 0 3 = "## " then begin
      flush_section ();
      let heading = String.sub line 3 (String.length line - 3) |> String.trim in
      current_heading := Some heading;
      in_header_area := true
    end
    else begin
      (* Check for label lines *)
      let trimmed = String.trim line in
      if trimmed <> "" && trimmed.[0] = '[' && !in_header_area then begin
        let labels = parse_inline_labels trimmed in
        let label_names = List.map fst labels in
        if !current_heading = None && !name <> "" then
          file_labels := !file_labels @ label_names
        else
          current_labels := !current_labels @ label_names
      end else begin
        if trimmed <> "" then in_header_area := false;
        if !current_heading <> None then begin
          Buffer.add_string current_content line;
          Buffer.add_char current_content '\n'
        end
      end
    end
  ) lines;
  flush_section ();

  {
    id;
    name = !name;
    sections = List.rev !sections;
    labels = !file_labels;
    refs;
    raw_content = content;
  }

(** Parse sections from main.md to get Glossary, Labels, and Axioms sections *)
type main_sections = {
  system_name: string;
  glossary_content: string;
  labels_content: string;
  axioms_content: string;
}

let parse_main_md (content : string) : main_sections =
  let lines = String.split_on_char '\n' content in
  let system_name = ref "" in
  let current_section = ref "" in
  let glossary_buf = Buffer.create 256 in
  let labels_buf = Buffer.create 256 in
  let axioms_buf = Buffer.create 256 in
  List.iter (fun line ->
    if String.length line >= 2 && String.sub line 0 2 = "# " && !system_name = "" then
      system_name := String.sub line 2 (String.length line - 2) |> String.trim
    else if String.length line >= 3 && String.sub line 0 3 = "## " then begin
      let section = String.sub line 3 (String.length line - 3) |> String.trim in
      current_section := String.lowercase_ascii section
    end else begin
      let buf = match !current_section with
        | "glossary" -> Some glossary_buf
        | "labels" -> Some labels_buf
        | "axioms" -> Some axioms_buf
        | _ -> None
      in
      match buf with
      | Some b ->
        Buffer.add_string b line;
        Buffer.add_char b '\n'
      | None -> ()
    end
  ) lines;
  {
    system_name = !system_name;
    glossary_content = Buffer.contents glossary_buf;
    labels_content = Buffer.contents labels_buf;
    axioms_content = Buffer.contents axioms_buf;
  }

(** Parse label definitions from ## Labels content.
    Each label starts with ### [name] ... and has description content below. *)
let parse_label_defs ?(glossary : glossary_entry list = []) (content : string) : label_def list =
  let lines = String.split_on_char '\n' content in
  let defs = ref [] in
  let current_def = ref None in
  let desc_buf = Buffer.create 128 in

  let flush () =
    match !current_def with
    | Some ld ->
      let description = Buffer.contents desc_buf |> String.trim in
      defs := { ld with description } :: !defs;
      Buffer.clear desc_buf;
      current_def := None
    | None ->
      Buffer.clear desc_buf
  in

  List.iter (fun line ->
    if String.length line >= 4 && String.sub line 0 4 = "### " then begin
      flush ();
      let heading = String.sub line 4 (String.length line - 4) |> String.trim in
      current_def := parse_label_heading ~glossary heading
    end else if !current_def <> None then begin
      Buffer.add_string desc_buf line;
      Buffer.add_char desc_buf '\n'
    end
  ) lines;
  flush ();
  List.rev !defs

(** Parse global labels from ## Axioms section.
    Labels appear as [label] on lines before the link list. *)
let parse_global_labels (axioms_content : string) : string list =
  let lines = String.split_on_char '\n' axioms_content in
  let labels = ref [] in
  List.iter (fun line ->
    let trimmed = String.trim line in
    if trimmed <> "" && trimmed.[0] = '[' then begin
      let parsed = parse_inline_labels trimmed in
      (* Only if it's not a markdown link line like "- [Name](./file.md)" *)
      let is_link_line = String.contains trimmed '(' &&
        (let idx = String.index trimmed ']' in
         idx + 1 < String.length trimmed && trimmed.[idx + 1] = '(') in
      if not is_link_line then
        labels := !labels @ (List.map fst parsed)
    end
  ) lines;
  !labels

(** Read a file's contents, returning None if it doesn't exist *)
let read_file (path : string) : string option =
  if Sys.file_exists path then begin
    let ic = In_channel.open_text path in
    let content = In_channel.input_all ic in
    In_channel.close ic;
    Some content
  end else
    None

(** Compute axiom ID from relative path. E.g. "technology.md" or "patient-client/booking.md" *)
let axiom_id_of_path (rel_path : string) : string =
  rel_path

(** Load the full axiom system starting from main.md *)
let load ~(axioms_dir : string) : (axiom_system, string) result =
  let main_path = Filename.concat axioms_dir "main.md" in
  match read_file main_path with
  | None -> Error (Printf.sprintf "Cannot read %s" main_path)
  | Some main_content ->
    let main = parse_main_md main_content in
    let glossary = parse_glossary main.glossary_content in
    let label_defs = parse_label_defs ~glossary main.labels_content in
    let global_labels = parse_global_labels main.axioms_content in

    (* Extract axiom file links from ## Axioms section *)
    let axiom_links = extract_links main.axioms_content in

    (* Recursively follow links, loading axiom files *)
    let loaded = Hashtbl.create 16 in
    let axioms = ref [] in

    let rec load_axiom (rel_path : string) =
      if not (Hashtbl.mem loaded rel_path) then begin
        Hashtbl.add loaded rel_path true;
        let full_path = Filename.concat axioms_dir rel_path in
        match read_file full_path with
        | None -> () (* Will be caught by consistency check *)
        | Some content ->
          let id = axiom_id_of_path rel_path in
          let axiom = parse_axiom_file ~id content in
          (* Apply label cascade: global labels + file labels -> sections *)
          let file_labels = global_labels @ axiom.labels in
          let sections = List.map (fun (s : section) ->
            { s with labels = file_labels @ s.labels }
          ) axiom.sections in
          let axiom = { axiom with labels = file_labels; sections } in
          axioms := axiom :: !axioms;
          (* Follow links from this axiom *)
          let sub_links = extract_links content in
          List.iter load_axiom sub_links
      end
    in

    List.iter load_axiom axiom_links;

    Ok {
      name = main.system_name;
      glossary;
      label_defs;
      axioms = List.rev !axioms;
      global_labels;
    }
