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

type semantic_result =
  | No_contradictions
  | Contradictions of string
  | Invalid_response of string

type semantic_candidate_result =
  | No_contradiction_candidates
  | Contradiction_candidates of string list
  | Invalid_candidate_response of string

let contradiction_block_marker = "END_CONTRADICTION"

let excerpt text =
  let text = String.trim text in
  if String.length text > 240 then String.sub text 0 240 ^ "..." else text

let contains text needle =
  let text_len = String.length text in
  let needle_len = String.length needle in
  let rec loop i =
    if needle_len = 0
    then true
    else if i + needle_len > text_len
    then false
    else if String.sub text i needle_len = needle
    then true
    else loop (i + 1)
  in
  loop 0

let classify_semantic_result result =
  let result = String.trim result in
  if result = ""
  then
    Invalid_response
      "Semantic consistency check returned an empty response. No contradiction \
       details were provided by the model."
  else if String.starts_with ~prefix:"NO_CONTRADICTIONS" result
  then No_contradictions
  else if String.starts_with ~prefix:"CONTRADICTION" result
          && String.contains result '\n'
          && String.contains result ':'
          && contains result contradiction_block_marker
  then Contradictions result
  else
    Invalid_response
      (Fmt.str
         "Semantic consistency check returned an incomplete or malformed \
          response: %s"
         (excerpt result))

let parse_candidate_ids text =
  let ids =
    text
    |> String.split_on_char ','
    |> List.map String.trim
    |> List.filter (fun s -> s <> "")
  in
  let ids = List.sort_uniq String.compare ids in
  if ids = [] then None else Some ids

let classify_semantic_candidate_result result =
  let result = String.trim result in
  if result = "NO_CONTRADICTIONS"
  then No_contradiction_candidates
  else if String.starts_with ~prefix:"CONTRADICTION_IDS:" result
  then
    let prefix = "CONTRADICTION_IDS:" in
    let ids_part =
      String.sub result (String.length prefix) (String.length result - String.length prefix)
      |> String.trim
    in
    (match parse_candidate_ids ids_part with
    | Some ids -> Contradiction_candidates ids
    | None ->
        Invalid_candidate_response
          "Semantic candidate check returned `CONTRADICTION_IDS:` without any ids.")
  else
    Invalid_candidate_response
      (Fmt.str
         "Semantic candidate check returned an incomplete or malformed \
          response: %s"
         (excerpt result))

let error_message_of_exn exn =
  match exn with
  | Failure msg -> msg
  | _ -> Printexc.to_string exn

let is_non_retryable_error msg =
  let patterns =
    [ "finish_reason=length"
    ; "was truncated because it hit the max token limit"
    ; "ended after reasoning without final answer text"
    ; "returned an incomplete or malformed response"
    ; "returned an invalid response" ]
  in
  List.exists (contains msg) patterns

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

let check_semantic_exn
    ~(total_cost : float ref)
    ~(api_key : string option)
    ~(model : string)
    ~(system : Types.system) =
  let candidate_system_prompt =
    {|
    You are a consistency checker for an axiomatic specification.

    Detect only real semantic contradictions:
    - two or more hard requirements that cannot all be true at the same time
    - impossible constraints
    - mutually exclusive obligations or goals

    Ignore ambiguity, underspecification, minor wording differences, tradeoffs,
    and anything that could reasonably coexist by interpretation.

    Output in exactly one of these formats:
    NO_CONTRADICTIONS
    CONTRADICTION_IDS: <comma-separated axiom ids involved in any real contradiction>

    Rules:
    - Output only one line.
    - No explanation.
    - Include only axiom ids that are part of at least one real contradiction.
    - If unsure, prefer NO_CONTRADICTIONS.
    |}
  in
  let detail_system_prompt =
    {|
    You are a consistency checker for an axiomatic specification.

    Your task is to detect only real semantic contradictions:
    - two or more hard requirements that cannot all be true at the same time
    - impossible constraints
    - mutually exclusive obligations or goals

    Do NOT report any of the following as contradictions:
    - minor wording differences
    - ambiguity or underspecification
    - differences in precision or terminology
    - tensions, tradeoffs, or preferences that could be resolved by interpretation
    - requirements that can reasonably coexist with defaults, prioritization, or scoped interpretation

    Be conservative. If there is any reasonable interpretation under which the statements can all be satisfied together, treat that as NO contradiction.

    Only report an issue when you can point to specific statements that are jointly impossible to satisfy.

    If you find NO real contradictions, respond with exactly:
    NO_CONTRADICTIONS

    and nothing else.

    If you do find contradictions, respond using one or more blocks in exactly
    this format:

    CONTRADICTION
    Axiom IDs: <comma-separated axiom ids>
    Statements:
    - <first conflicting statement>
    - <second conflicting statement>
    Why impossible: <short explanation>
    END_CONTRADICTION

    Do not include any intro, summary, or commentary outside these blocks.
    |}
  in
  let axiom_content axioms =
    axioms
    |> List.map (fun axiom ->
           Fmt.str
             "**%s**\n\n%s\n----------------------------------------"
             axiom.id
             axiom.raw_content)
    |> String.concat "\n"
  in
  let candidate_user_prompt =
    Fmt.str
      "Analyze these axioms for real semantic contradictions only. Return only \
       `NO_CONTRADICTIONS` or `CONTRADICTION_IDS: ...`.\n\n%s"
      (axiom_content system.axioms)
  in
  let detail_user_prompt axioms =
    Fmt.str
      "Analyze only these candidate axioms and report real semantic \
       contradictions using the required block format.\n\n%s"
      (axiom_content axioms)
  in
  let find_axioms_by_ids ids =
    ids
    |> List.filter_map (fun id ->
           List.find_opt (fun (axiom : axiom) -> axiom.id = id) system.axioms)
  in
  let rec run_with_retry
      ~label
      ~system_prompt
      ~user_prompt
      ~classify
      attempt
      last_error =
    if attempt > 3
    then
      failwith
        (Fmt.str
           "%s failed after %d attempts.%s"
           label
           (attempt - 1)
           (match last_error with
           | None -> ""
           | Some err -> Fmt.str " Last error: %s" err))
    else
      let attempt_result =
        try
          let response =
            Ai_access.prompt
              ~system_prompt
              ~user_prompt
              ~model
              ~toolset:Ai_access.No_tools
              ?api_key
              ()
          in
          total_cost := !total_cost +. response.Types.cost ;
          Ok (classify response.Types.result)
        with
        | exn -> Error (`Failure (error_message_of_exn exn))
      in
      match attempt_result with
      | Ok (Ok result) -> result
      | Ok (Error msg) ->
          if attempt < 3 && not (is_non_retryable_error msg)
          then (
            Fmt.pr
              "%s attempt %d/3 returned an invalid \
               response, retrying: %s\n%!"
              label
              attempt
              msg ;
            Unix.sleepf (0.75 *. float_of_int attempt) ;
            run_with_retry
              ~label
              ~system_prompt
              ~user_prompt
              ~classify
              (attempt + 1)
              (Some msg) )
          else failwith msg
      | Error (`Failure msg) ->
          if attempt < 3 && not (is_non_retryable_error msg)
          then (
            Fmt.pr
              "%s attempt %d/3 failed, retrying: %s\n%!"
              label
              attempt
              msg ;
            Unix.sleepf (0.75 *. float_of_int attempt) ;
            run_with_retry
              ~label
              ~system_prompt
              ~user_prompt
              ~classify
              (attempt + 1)
              (Some msg) )
          else failwith msg
  in
  let candidate_result =
    run_with_retry
      ~label:"Semantic candidate check"
      ~system_prompt:candidate_system_prompt
      ~user_prompt:candidate_user_prompt
      ~classify:(fun raw ->
        match classify_semantic_candidate_result raw with
        | No_contradiction_candidates -> Ok No_contradiction_candidates
        | Contradiction_candidates ids -> Ok (Contradiction_candidates ids)
        | Invalid_candidate_response msg -> Error msg)
      1
      None
  in
  match candidate_result with
  | No_contradiction_candidates ->
      Fmt.pr "Semantic check passed — no contradictions found.\n@."
  | Contradiction_candidates ids ->
      let candidate_axioms = find_axioms_by_ids ids in
      if candidate_axioms = []
      then
        failwith
          "Semantic candidate check returned contradiction ids that were not \
           found in the loaded axioms."
      else
        let result =
          run_with_retry
            ~label:"Semantic detail check"
            ~system_prompt:detail_system_prompt
            ~user_prompt:(detail_user_prompt candidate_axioms)
            ~classify:(fun raw ->
              match classify_semantic_result raw with
              | No_contradictions -> Ok No_contradictions
              | Contradictions details -> Ok (Contradictions details)
              | Invalid_response msg -> Error msg)
            1
            None
        in
        (match result with
        | No_contradictions ->
            Fmt.pr "Semantic check passed — no contradictions found.\n@."
        | Contradictions details ->
            failwith (Fmt.str "Semantic contradictions found:\n\n%s\n@." details)
        | Invalid_response msg -> failwith msg)
  | Invalid_candidate_response msg -> failwith msg
