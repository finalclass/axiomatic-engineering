module Config = Config
module Consistency = Consistency
module Types = Types

let use_color () =
  Sys.getenv_opt "NO_COLOR" = None
  &&
  match Sys.getenv_opt "TERM" with
  | Some "dumb" -> false
  | Some _ -> true
  | None -> false

let ansi code text =
  if use_color () then Printf.sprintf "\027[%sm%s\027[0m" code text else text

let cyan text = ansi "36" text

let bold text = ansi "1" text

let dim text = ansi "2" text

type validation_result =
  | Validation_pass
  | Validation_issues of string
  | Validation_invalid of string

type satisfaction_result =
  | Satisfaction_ok of
      { score: float
      ; reason: string }
  | Satisfaction_invalid of string

let excerpt text =
  let text = String.trim text in
  if String.length text > 240 then String.sub text 0 240 ^ "..." else text

type planning_axiom =
  { axiom_id: string
  ; labels: string list
  ; context: string }

let planning_context_budget = 24_000

let planning_context_note =
  "[planning input truncated; inspect the axiom file directly with tools for \
   full details]"

let compact_planning_context ~max_chars text =
  let text = String.trim text in
  if String.length text <= max_chars
  then text
  else
    let note = "\n\n" ^ planning_context_note in
    let gap = "\n\n...\n" in
    let note_len = String.length note in
    let gap_len = String.length gap in
    if max_chars <= note_len + gap_len + 32
    then
      String.sub
        planning_context_note
        0
        (min (String.length planning_context_note) max_chars)
    else
      let available = max_chars - note_len - gap_len in
      let head_len = available / 2 in
      let tail_len = available - head_len in
      let head = String.sub text 0 head_len in
      let tail = String.sub text (String.length text - tail_len) tail_len in
      head ^ gap ^ tail ^ note

let planning_axioms_of_impl_tasks (impl_tasks : Types.task list) :
    planning_axiom list =
  let table : (string, planning_axiom) Hashtbl.t = Hashtbl.create 16 in
  List.iter
    (fun (task : Types.task) ->
      let label_name = task.label.name in
      match Hashtbl.find_opt table task.axiom_id with
      | None ->
          Hashtbl.add
            table
            task.axiom_id
            { axiom_id= task.axiom_id
            ; labels= [label_name]
            ; context= task.context }
      | Some existing ->
          let labels =
            List.sort_uniq String.compare (label_name :: existing.labels)
          in
          let context =
            if String.length task.context > String.length existing.context
            then task.context
            else existing.context
          in
          Hashtbl.replace table task.axiom_id {existing with labels; context} )
    impl_tasks ;
  Hashtbl.to_seq_values table
  |> List.of_seq
  |> List.sort (fun a b -> String.compare a.axiom_id b.axiom_id)

let apply_planning_context_budget
    ?(total_budget = planning_context_budget)
    (axioms : planning_axiom list) : planning_axiom list =
  let total_chars =
    List.fold_left (fun acc axiom -> acc + String.length axiom.context) 0 axioms
  in
  if total_chars <= total_budget || axioms = []
  then axioms
  else
    let per_axiom_budget = max 1200 (total_budget / List.length axioms) in
    List.map
      (fun axiom ->
        { axiom with
          context=
            compact_planning_context ~max_chars:per_axiom_budget axiom.context
        } )
      axioms

let render_planning_axioms (axioms : planning_axiom list) : string =
  axioms
  |> List.map (fun axiom ->
      Fmt.str
        {|
          Axiom id: %s
          Implementation labels: %s
          Content:
%s |}
        axiom.axiom_id
        (String.concat ", " axiom.labels)
        axiom.context )
  |> String.concat "\n\n"

let substring_from text start =
  String.sub text start (String.length text - start)

let rec find_substring_from text pattern start =
  let text_len = String.length text in
  let pattern_len = String.length pattern in
  if pattern_len = 0
  then Some start
  else if start + pattern_len > text_len
  then None
  else if String.sub text start pattern_len = pattern
  then Some start
  else find_substring_from text pattern (start + 1)

let find_substring text pattern = find_substring_from text pattern 0

let standalone_line text target =
  text
  |> String.split_on_char '\n'
  |> List.exists (fun line -> String.trim line = target)

let extract_from_marker text marker =
  match find_substring text marker with
  | Some idx -> Some (String.trim (substring_from text idx))
  | None -> None

let extract_first_json_object text =
  let len = String.length text in
  let rec find_start i =
    if i >= len
    then None
    else if text.[i] = '{'
    then Some i
    else find_start (i + 1)
  in
  let rec find_end i depth in_string escaped =
    if i >= len
    then None
    else
      let ch = text.[i] in
      if in_string
      then
        if escaped
        then find_end (i + 1) depth true false
        else if ch = '\\'
        then find_end (i + 1) depth true true
        else if ch = '"'
        then find_end (i + 1) depth false false
        else find_end (i + 1) depth true false
      else if ch = '"'
      then find_end (i + 1) depth true false
      else if ch = '{'
      then find_end (i + 1) (depth + 1) false false
      else if ch = '}'
      then
        if depth = 1 then Some i else find_end (i + 1) (depth - 1) false false
      else find_end (i + 1) depth false false
  in
  match find_start 0 with
  | None -> None
  | Some start -> (
    match find_end (start + 1) 1 false false with
    | None -> None
    | Some stop -> Some (String.sub text start (stop - start + 1)) )

let classify_validation_result raw =
  let result = String.trim raw in
  let normalized =
    if result = "NO ISSUES"
    then Some "NO ISSUES"
    else if standalone_line result "NO ISSUES"
    then Some "NO ISSUES"
    else extract_from_marker result "ISSUES:"
  in
  match normalized with
  | Some "NO ISSUES" -> Validation_pass
  | Some issues when String.starts_with ~prefix:"ISSUES:" issues ->
      Validation_issues issues
  | _ ->
      Validation_invalid
        (Fmt.str
           "Validation returned an incomplete or malformed response: %s"
           (excerpt result) )

let classify_satisfaction_result raw =
  let parse_json () =
    let candidate =
      match extract_first_json_object raw with
      | Some json -> json
      | None -> raw
    in
    let json = Yojson.Safe.from_string candidate in
    let open Yojson.Safe.Util in
    let score = json |> member "score" |> to_float in
    let reason = json |> member "reason" |> to_string in
    if score < 0.0 || score > 1.0
    then
      Satisfaction_invalid
        (Fmt.str
           "Satisfaction score must be within 0.0-1.0, got %.3f in response: %s"
           score
           (excerpt raw) )
    else Satisfaction_ok {score; reason= String.trim reason}
  in
  try parse_json () with
  | _ ->
      Satisfaction_invalid
        (Fmt.str
           "Satisfaction returned an incomplete or malformed JSON response: %s"
           (excerpt raw) )

let section title =
  Fmt.pr
    "%s\n%s\n%s\n@."
    (dim
       "────────────────────────────────────────────────────────────────────────────────────────────────────" )
    (bold (cyan title))
    (dim
       "────────────────────────────────────────────────────────────────────────────────────────────────────" )

let add_cost ~(total_cost : float ref) (response : Types.ai_response) =
  total_cost := !total_cost +. response.cost ;
  response

let prompt_result ~(total_cost : float ref) response =
  add_cost ~total_cost response |> fun response -> response.Types.result

let format_total_cost total_cost =
  Fmt.str "Sync complete. Total cost: $%.4f @." total_cost

let absolute_project_path (project_path : string) : string =
  let path =
    if Filename.is_relative project_path
    then Filename.concat (Sys.getcwd ()) project_path
    else project_path
  in
  try Unix.realpath path with
  | _ -> path

let classify_plan_result raw =
  let text = String.trim raw in
  let lower = String.lowercase_ascii text in
  let looks_like_greeting =
    String.length lower < 240
    && ( String.starts_with ~prefix:"hello" lower
       || String.starts_with ~prefix:"hi" lower
       || String.starts_with ~prefix:"cze" lower )
  in
  let has_plan_signal =
    String.contains text '\n'
    || String.contains text '-'
    || String.contains text '1'
  in
  if text = "" || looks_like_greeting || not has_plan_signal
  then
    Error
      (Fmt.str
         "Planning returned an incomplete or malformed response: %s"
         (excerpt text) )
  else Ok text

let implementation_system_prompt =
  {|
      This is an axiomatic project. User writes axioms and then your job is
      to adjust the implementation to the axioms and what we have in the code.
      Each portion of code has to be wrapped in "@axiom" marks. For exapmle, for OCaml code:
      (* @axiom: todo/item.md *)
      type item = { id: string; name: string; }
      let items: item list = []
      (* /@axiom: todo/item.md *)
    |}

let ensure_sth_to_implement ~impl_tasks f =
  match impl_tasks with
  | [] ->
      Fmt.pr "\nNo tasks to execute.\n%!@." ;
      ()
  | _ -> f ()

let planning_phase
    ~(total_cost : float ref)
    ~(api_key : string option)
    ~(model : string)
    ~(tool_base_dir : string)
    ~impl_tasks =
  let tasks_str =
    impl_tasks
    |> planning_axioms_of_impl_tasks
    |> apply_planning_context_budget
    |> render_planning_axioms
  in
  let system_prompt =
    let p = tool_base_dir in
    String.concat
      "\n"
      [ Printf.sprintf "You are working on an axiomatic project at: %s" p
      ; ""
      ; "Axioms (specifications) live in the `axioms/` subdirectory. \
         Implementation code lives in the `code/` subdirectory. Your job is to \
         investigate the codebase and propose a thorough implementation plan \
         for bringing the codebase into compliance with the axioms below."
      ; "Never propose changing axioms. Axioms are the source of truth."
      ; ""
      ; Printf.sprintf
          "IMPORTANT: Always use the project root path `%s` when referencing \
           files. For example:"
          p
      ; Printf.sprintf
          "- To list files: glob_search with base_dir=\"%s\", \
           pattern=\"**/*.md\""
          p
      ; Printf.sprintf
          "- To read an axiom: read_file with path=\"%s/axioms/...\""
          p
      ; Printf.sprintf "- To read code: read_file with path=\"%s/code/...\"" p
      ; Printf.sprintf
          "- In bash commands: use `cd %s && ...` or absolute paths starting \
           with %s/"
          p
          p
      ; ""
      ; "The axiom excerpts in the prompt may be truncated for context budget \
         reasons. If anything looks shortened or incomplete, read the full \
         axiom files with tools before planning."
      ; ""
      ; "Do NOT guess or invent paths. Use the tools to explore the directory \
         structure first."
      ; ""
      ; "Your final answer must be only the implementation plan."
      ; "Do not greet. Do not chat. Do not say hello."
      ; "Return a concrete multi-step plan with file references, risks, and \
         verification steps." ]
  in
  let user_prompt =
    Fmt.str
      {|
    Here are axioms that describe required behavior. Propose a thorough plan
    for changing the implementation so the code becomes compliant with them.
    Do not propose edits to axioms. Investigate the repository first if needed,
    then return only the final implementation plan.
    %s
             |}
      tasks_str
  in
  let rec run_with_retry attempt last_error =
    if attempt > 3
    then
      failwith
        (Fmt.str
           "Planning failed after %d attempts.%s"
           (attempt - 1)
           ( match last_error with
           | None -> ""
           | Some err -> Fmt.str " Last error: %s" err ) )
    else
      let raw =
        Ai_access.prompt
          ~system_prompt
          ~user_prompt
          ~tool_base_dir
          ~model
          ~stream_output:false
          ?api_key
          ()
        |> prompt_result ~total_cost
      in
      match classify_plan_result raw with
      | Ok plan -> plan
      | Error msg ->
          if attempt < 3
          then (
            Fmt.pr
              "Planning attempt %d/3 returned an invalid response, retrying: %s\n\
               %!"
              attempt
              msg ;
            Unix.sleepf (0.75 *. float_of_int attempt) ;
            run_with_retry (attempt + 1) (Some msg) )
          else failwith msg
  in
  run_with_retry 1 None

let validation_phase
    ~(total_cost : float ref)
    ~(api_key : string option)
    ~(model : string)
    ~(valid_tasks : Types.task list) : string option =
  match valid_tasks with
  | [] -> None
  | _ ->
      let tasks_str =
        valid_tasks
        |> List.map (fun (task : Types.task) ->
            Fmt.str
              {|
          Axiom id: %s
          Content:
%s |}
              task.axiom_id
              task.context )
        |> String.concat "\n\n"
      in
      let rec run_with_retry attempt last_error =
        if attempt > 3
        then
          failwith
            (Fmt.str
               "Validation failed after %d attempts.%s"
               (attempt - 1)
               ( match last_error with
               | None -> ""
               | Some err -> Fmt.str " Last error: %s" err ) )
        else
          let raw =
            Ai_access.prompt
              ~system_prompt:
                {|
                This is an axiomatic project. User writes axioms which then get converted
                into code. Your job is to validate the implementation against the axioms.
                Check the code for compliance with the axioms.

                If everything is correct, respond with exactly:
                NO ISSUES

                If there are issues, respond with:
                ISSUES:
                - <issue 1>
                - <issue 2>

                Do not include any intro, summary, or commentary outside this format.
                |}
              ~user_prompt:
                (Fmt.str
                   {|
              Validate the following axioms against the current implementation:
              %s
                   |}
                   tasks_str )
              ~model
              ~stream_output:false
              ?api_key
              ()
            |> prompt_result ~total_cost
          in
          match classify_validation_result raw with
          | Validation_pass -> None
          | Validation_issues issues -> Some issues
          | Validation_invalid msg ->
              if attempt < 3
              then (
                Fmt.pr
                  "Validation attempt %d/3 returned an invalid response, \
                   retrying: %s\n\
                   %!"
                  attempt
                  msg ;
                Unix.sleepf (0.75 *. float_of_int attempt) ;

                run_with_retry (attempt + 1) (Some msg) )
              else failwith msg
      in
      run_with_retry 1 None

(** Run a single satisfaction task, returns (task, score, reason) *)
let run_one_satisfaction_task
    ~(total_cost : float ref)
    ~(api_key : string option)
    ~(model : string)
    (task : Types.task) : Types.task * float * string =
  let threshold =
    match task.phase with
    | Types.Satisfaction t -> t
    | _ -> 0.7
  in
  let has_code_marker =
    List.exists
      (function
        | Types.Code -> true
        | _ -> false )
      task.label.markers
  in
  let code_access_instr =
    if has_code_marker
    then
      "You HAVE access to the `code/` directory. You can examine files there \
       to verify compliance."
    else
      "You DO NOT have access to the `code/` directory. You must evaluate \
       based solely on the axiom content and label instructions provided \
       below."
  in
  let system_prompt =
    Fmt.str
      {|
      This is an axiomatic project. User writes axioms which then get converted
      into code. Your job is to evaluate how well the implementation satisfies
      the axiom requirements.

      %s

      You MUST respond with a JSON object in this exact format:
      {"score": <float 0.0-1.0>, "reason": "<brief explanation>"}

      The score should reflect how well the implementation meets the axiom requirements.
      Be strict but fair. Do NOT include any text outside the JSON object.
      |}
      code_access_instr
  in
  let user_prompt =
    Fmt.str
      {|
      Axiom ID: %s
      Label: %s
      Label description: %s
      Threshold: %.2f

      Axiom content:
%s
      |}
      task.axiom_id
      task.label.name
      task.label.description
      threshold
      task.context
  in
  let raw =
    let rec run_with_retry attempt last_error =
      if attempt > 3
      then
        failwith
          (Fmt.str
             "Satisfaction check for %s [%s] failed after %d attempts.%s"
             task.axiom_id
             task.label.name
             (attempt - 1)
             ( match last_error with
             | None -> ""
             | Some err -> Fmt.str " Last error: %s" err ) )
      else
        let raw =
          Ai_access.prompt
            ~system_prompt
            ~user_prompt
            ~model
            ~stream_output:false
            ?api_key
            ()
          |> prompt_result ~total_cost
        in
        match classify_satisfaction_result raw with
        | Satisfaction_ok {score; reason} -> (score, reason)
        | Satisfaction_invalid msg ->
            if attempt < 3
            then (
              Fmt.pr
                "Satisfaction attempt %d/3 for %s [%s] returned an invalid \
                 response, retrying: %s\n\
                 %!"
                attempt
                task.axiom_id
                task.label.name
                msg ;
              Unix.sleepf (0.75 *. float_of_int attempt) ;
              run_with_retry (attempt + 1) (Some msg) )
            else failwith msg
    in
    run_with_retry 1 None
  in
  let score, reason = raw in
  (task, score, reason)

(** Run satisfaction checks in parallel. Returns None if all pass, Some issues string otherwise. *)
let satisfaction_phase
    ~(total_cost : float ref)
    ~(api_key : string option)
    ~(model : string)
    ~(satisfy_tasks : Types.task list) : string option =
  match satisfy_tasks with
  | [] -> None
  | _ ->
      (* Collect results from parallel fibers *)
      let results : (Types.task * float * string) list ref = ref [] in
      let fiber_for_task task () =
        let result =
          run_one_satisfaction_task ~total_cost ~api_key ~model task
        in
        results := result :: !results
      in
      let fibers : (unit -> unit) list =
        List.map (fun task -> fiber_for_task task) satisfy_tasks
      in
      Eio.Fiber.all fibers ;
      let results : (Types.task * float * string) list = List.rev !results in

      (* Collect failures: tasks where score < threshold *)
      let failures : string list =
        List.filter_map
          (fun (t, score, reason) ->
            let t : Types.task = t in
            let threshold =
              match t.Types.phase with
              | Types.Satisfaction t -> t
              | _ -> 0.7
            in
            if score < threshold
            then
              Some
                (Fmt.str
                   "AXIOM: %s | LABEL: %s | SCORE: %.2f / %.2f (FAILED) | \
                    REASON: %s"
                   t.axiom_id
                   t.label.name
                   score
                   threshold
                   reason )
            else None )
          results
      in

      (* Print summary *)
      List.iter
        (fun (t, score, reason) ->
          let t : Types.task = t in
          let threshold =
            match t.Types.phase with
            | Types.Satisfaction t -> t
            | _ -> 0.7
          in
          let status = if score >= threshold then "PASS" else "FAIL" in
          Fmt.pr
            "  [%s] %s / %s → %.2f / %.2f — %s\n%!"
            status
            t.axiom_id
            t.label.name
            score
            threshold
            reason )
        results ;

      if failures = [] then None else Some (String.concat "\n" failures)

let implementation_phase
    ~(total_cost : float ref)
    ~(api_key : string option)
    ~(plan : string)
    ~(session_id : string)
    ~(tool_base_dir : string)
    ~(model : string) =
  Ai_access.prompt
    ~system_prompt:implementation_system_prompt
    ~user_prompt:plan
    ?api_key
    ~session_id
    ~tool_base_dir
    ~model
    ()
  |> add_cost ~total_cost

let fix_implementation
    ~(total_cost : float ref)
    ~(api_key : string option)
    ~(issues : string)
    ~(session_id : string)
    ~(tool_base_dir : string)
    ~(model : string) =
  Ai_access.prompt
    ~system_prompt:implementation_system_prompt
    ~user_prompt:
      (Fmt.str
         {|
Continue the current implementation session and fix the issues below.

Requirements:
- Reuse the existing context from this session instead of starting over.
- Apply the smallest correct code changes needed.
- Keep the code aligned with the original implementation plan and the axioms.
- Preserve existing `@axiom` markers or add them where required.
- After making fixes, briefly summarize what you changed.

Issues to fix:
%s
|}
         issues )
    ?api_key
    ~session_id
    ~tool_base_dir
    ~model
    ()
  |> add_cost ~total_cost

let run ~(config : Types.config) =
  Mirage_crypto_rng_unix.use_default () ;
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun _sw ->
  Ai_access.set_net (Eio.Stdenv.net env) ;
  let fs = Eio.Stdenv.fs env in
  let project_path_real = absolute_project_path config.project_path in
  let project_path = Eio.Path.(fs / config.project_path) in
  let project_path_str = project_path_real in
  let total_cost = ref 0.0 in
  let axioms_dir = Eio.Path.(project_path / "axioms") in
  let code_dir = Eio.Path.(project_path / "code") in
  let system = Loader.load_exn axioms_dir in

  section "Initializing" ;
  Consistency.check_exn system ;
  let changes = Changes.compute_changes_exn ~config ~project_path ~system in
  Markers.validate_exn code_dir system ;
  let impl_tasks = Planner.implementation_tasks system changes in
  let valid_tasks = Planner.validation_tasks system changes in
  let satisfy_tasks = Planner.satisfaction_tasks system changes in

  ensure_sth_to_implement ~impl_tasks @@ fun () ->
  section "Checking" ;
  if config.no_semantic
  then Fmt.pr "Semantic consistency check skipped (--no-semantic).\n@."
  else
    Consistency.check_semantic_exn
      ~total_cost
      ~api_key:config.api_key
      ~model:config.semantic
      ~system ;

  section "Planning" ;

  let plan =
    planning_phase
      ~total_cost
      ~api_key:config.api_key
      ~model:config.planner
      ~tool_base_dir:project_path_str
      ~impl_tasks
  in
  let implementation_session_id = "axioms-sync:implementation" in

  section "Implementing" ;
  implementation_phase
    ~total_cost
    ~api_key:config.api_key
    ~plan
    ~session_id:implementation_session_id
    ~tool_base_dir:project_path_str
    ~model:config.implementer
  |> ignore ;

  section "Validating" ;
  let rec loop iterations_left on_success =
    let run_loop () =
      if iterations_left < 1
      then failwith "Maximum number of validation iterations reached"
      else loop (iterations_left - 1) on_success
    in

    if iterations_left <= 0 then failwith "Implementation retry limit exceeded" ;
    let check_satisfaction () =
      section "Satisfying" ;
      let satisfaction_result =
        satisfaction_phase
          ~total_cost
          ~api_key:config.api_key
          ~model:config.fast
          ~satisfy_tasks
      in
      ( match satisfaction_result with
      | None ->
          Fmt.pr "All satisfaction checks passed.%!\n%!" ;
          on_success ()
      | Some issues ->
          Fmt.pr "Satisfaction issues:\n%s\n%!" issues ;
          fix_implementation
            ~total_cost
            ~api_key:config.api_key
            ~issues
            ~session_id:implementation_session_id
            ~tool_base_dir:project_path_str
            ~model:config.implementer
          |> ignore ;
          run_loop () ) ;
      ()
    in

    let validation_result =
      validation_phase
        ~total_cost
        ~api_key:config.api_key
        ~model:config.balanced
        ~valid_tasks
    in
    match validation_result with
    | None ->
        Fmt.pr "No validation issues found.%!\n%!" ;
        check_satisfaction ()
    | Some issues ->
        Fmt.pr "Validation issues:\n%s\n%!" issues ;
        fix_implementation
          ~total_cost
          ~api_key:config.api_key
          ~issues
          ~session_id:implementation_session_id
          ~tool_base_dir:project_path_str
          ~model:config.implementer
        |> ignore ;
        run_loop ()
  in

  loop 50 @@ fun () ->
  section "Saving freeze" ;
  Snapshot.save_freeze ~project_path ;
  Fmt.pr "%s" (format_total_cost !total_cost)
