module Config = Config

let section title =
  Fmt.pr
    "────────────────────────────────────────────────────────────────────────────────────────────────────\n\
     %s\n\
     ────────────────────────────────────────────────────────────────────────────────────────────────────\n"
    title

let add_cost ~(total_cost : float ref) (response : Types.ai_response) =
  total_cost := !total_cost +. response.cost ;
  response

let prompt_result ~(total_cost : float ref) response =
  add_cost ~total_cost response |> fun response -> response.Types.result

let format_total_cost total_cost =
  Fmt.str "Sync complete. Total cost: $%.4f @." total_cost

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

let planning_phase ~(total_cost : float ref) ~(api_key : string option)
    ~(model : string) ~impl_tasks =
  let tasks_str =
    impl_tasks
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
  Ai_access.prompt
    ~system_prompt:
      {|
      This is an axiomatic project. User writes axioms which then get converter
        into code. The code is being synchronized with the axioms.
        Your job is to prepare an implementation plan according the changes user wants to make.
        Investigate the repo (the `code/` directtory), also if you need to see all the axioms you will find them in
        `axioms/` directory and propose an implementation plan including architecture, interfaces, best practices.
        You don't need to include any estamets in the plan, your plan will be given as is to 
        the next AI model for implementation.
               |}
    ~user_prompt:
      (Fmt.str
         {|
    Here are axioms that needs changing, propose a thourough plan for them.
    %s
               |}
         tasks_str )
    ~model
    ?api_key
    ()
  |> prompt_result ~total_cost

let validation_phase ~(total_cost : float ref) ~(api_key : string option)
    ~(model : string)
    ~(valid_tasks : Types.task list)
    : string option =
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
      let result =
        Ai_access.prompt
          ~system_prompt:
            {|
            This is an axiomatic project. User writes axioms which then get converted
            into code. Your job is to validate the implementation against the axioms.
            Check the code for compliance with the axioms. If everything is correct, respond
            with exactly "NO ISSUES". If there are issues, list them clearly.
            |}
          ~user_prompt:
            (Fmt.str
               {|
          Validate the following axioms against the current implementation:
          %s
               |}
               tasks_str )
          ~model
          ?api_key
          ()
        |> prompt_result ~total_cost
      in
      if String.trim result = "NO ISSUES" then None else Some result

(** Parse AI satisfaction response JSON. Expects {"score": 0.85, "reason": "..."} *)
let parse_satisfaction_json (raw : string) : float * string =
  try
    let json = Yojson.Safe.from_string raw in
    let open Yojson.Safe.Util in
    let score = json |> member "score" |> to_float in
    let reason =
      try json |> member "reason" |> to_string with
      | _ -> ""
    in
    (score, reason)
  with
  | _ -> (
      (* Fallback: try to extract first float from the response *)
      let re = Str.regexp "[0-9]+\\.[0-9]+" in
      try
        let _ = Str.search_forward re raw 0 in
        let matched = Str.matched_string raw in
        (float_of_string matched, "Could not parse JSON, extracted score only")
      with
      | Not_found -> (0.0, "Failed to parse score from response: " ^ raw) )

(** Run a single satisfaction task, returns (task, score, reason) *)
let run_one_satisfaction_task ~(total_cost : float ref)
    ~(api_key : string option) ~(model : string)
    (task : Types.task) :
    Types.task * float * string =
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
    Ai_access.prompt
      ~system_prompt
      ~user_prompt
      ~model
      ?api_key
      ()
    |> prompt_result ~total_cost
  in
  let score, reason = parse_satisfaction_json raw in
  (task, score, reason)

(** Run satisfaction checks in parallel. Returns None if all pass, Some issues string otherwise. *)
let satisfaction_phase ~(total_cost : float ref) ~(api_key : string option)
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
  let project_path = Eio.Path.(fs / config.project_path) in
  let project_path_str = Eio.Path.native_exn project_path in
  let total_cost = ref 0.0 in
  let axioms_dir = Eio.Path.(project_path / "axioms") in
  let code_dir = Eio.Path.(project_path / "code") in
  let system = Loader.load_exn axioms_dir in

  section "Initializing" ;
  Consistency.check_exn system ;
  let changes = Changes.compute_changes_exn ~config ~project_path ~system in
  Markers.validate_exn code_dir system ;

  section "Planning" ;

  let impl_tasks = Planner.implementation_tasks system changes in
  let valid_tasks = Planner.validation_tasks system changes in
  let satisfy_tasks = Planner.satisfaction_tasks system changes in

  ensure_sth_to_implement ~impl_tasks @@ fun () ->
  section "Checking" ;
  Consistency.check_semantic_exn
    ~total_cost
    ~api_key:config.api_key
    ~model:config.planner
    ~system ;

  let plan =
    planning_phase
      ~total_cost
      ~api_key:config.api_key
      ~model:config.planner
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
