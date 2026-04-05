(** axioms-sync CLI — orchestrates axiom synchronization *)

open Axioms_sync

let section title = Printf.printf "\n── %s ──\n%!" title

(** Prepend preprompt to a system prompt if non-empty *)
let with_preprompt (config : Types.config) (system : string) : string =
  if config.preprompt = "" then system else config.preprompt ^ "\n\n" ^ system

(** Build system prompt for a task *)
let system_prompt_of_task
    ~(config : Types.config)
    ~(code_dir : string)
    (task : Types.task) : string =
  with_preprompt
    config
    (Printf.sprintf
       "You are an AI agent working on the project. Phase: %s. Label: %s.\n\n\
        Your task is defined by the following axiom specification:\n\n\
        %s\n\n\
        Label description: %s\n\n\
        Work in the code/ directory: %s"
       ( match task.phase with
       | Types.Implementation -> "implementation"
       | Validation -> "validation"
       | Satisfaction f -> Printf.sprintf "satisfaction (threshold: %.1f)" f )
       task.label.name
       task.context
       task.label.description
       code_dir )

let prompt_of_task (task : Types.task) : string =
  match task.phase with
  | Types.Implementation ->
      Printf.sprintf
        "Implement the requirements from axiom '%s' for label [%s]. Use @axiom \
         markers to trace code back to the axiom file."
        task.axiom_id
        task.label.name
  | Validation ->
      Printf.sprintf
        "Validate the implementation of axiom '%s' for label [%s]. Report any \
         issues found. End your response with exactly VALIDATION_PASS if \
         everything is OK, or VALIDATION_FAIL if there are any issues."
        task.axiom_id
        task.label.name
  | Satisfaction threshold ->
      Printf.sprintf
        "Review the implementation of axiom '%s' for label [%s]. Rate \
         satisfaction from 0.0 to 1.0 (threshold: %.1f). Return your rating as \
         a number on the last line."
        task.axiom_id
        task.label.name
        threshold

(** Run the planner model to create an implementation plan for a task *)
let run_planner
    ~(config : Types.config)
    ~(code_dir : string)
    ~(quiet : bool)
    ~(total_cost : float ref)
    ?provider
    (task : Types.task) : string option =
  let planner_alias = config.planner in
  let model_id =
    match Ai_access.resolve_alias planner_alias with
    | Some (_, id) -> id
    | None ->
        failwith
          (Printf.sprintf "Unknown planner model alias: %s" planner_alias)
  in
  let executor = Ai_access.executor_for_alias planner_alias in
  let system =
    with_preprompt
      config
      (Printf.sprintf
         "You are a planning agent. Your job is to analyze the axiom \
          specification and create a detailed implementation plan. Do NOT \
          implement anything — only plan.\n\n\
          Axiom specification:\n\n\
          %s\n\n\
          Label: %s — %s\n\n\
          Code directory: %s\n\n\
          Output a step-by-step plan describing:\n\
          - What files to create or modify\n\
          - What each file should contain\n\
          - How to use @axiom markers for traceability\n\
          - Any dependencies between steps"
         task.context
         task.label.name
         task.label.description
         code_dir )
  in
  let prompt =
    Printf.sprintf
      "Create an implementation plan for axiom '%s', label [%s]."
      task.axiom_id
      task.label.name
  in
  (* Planner gets read-only tools — can inspect code but not modify *)
  let tools = Tools.tool_defs_for_markers [Types.Code] in
  let read_only_tools =
    List.filter
      (fun (td : Ai_access.tool_def) ->
        td.name = "read_file" || td.name = "list_files" )
      tools
  in
  Printf.printf
    "  planning [%s] %s (%s) ... %!"
    task.label.name
    task.axiom_id
    planner_alias ;
  match
    Ai_access.dispatch
      ~executor
      ~model:model_id
      ~system
      ~prompt
      ~cwd:code_dir
      ~quiet
      ?provider
      ~tools:read_only_tools
      ~execute_tool:(Tools.execute ~base_dir:code_dir)
      ~max_iterations:10
      ()
  with
  | Ok (plan, cost) ->
      ( match cost with
      | Some c -> total_cost := !total_cost +. c.cost_usd
      | None -> () ) ;
      Printf.printf "done\n%!" ;
      Some plan
  | Error msg ->
      Printf.printf "FAILED: %s\n%!" msg ;
      None

(** Run a single task — executor is resolved from model alias by ai_access.
    If plan is provided, it's injected into the implementation prompt. *)
let run_task
    ~(mu : Mutex.t)
    ~(config : Types.config)
    ~(code_dir : string)
    ~(quiet : bool)
    ~(total_cost : float ref)
    ?provider
    ?plan
    (task : Types.task) : (string, string) result =
  let model_alias = Types.model_alias_of_class config task.model_class in
  let model_id =
    match Ai_access.resolve_alias model_alias with
    | Some (_, id) -> id
    | None -> failwith (Printf.sprintf "Unknown model alias: %s" model_alias)
  in
  let executor = Ai_access.executor_for_alias model_alias in
  let system = system_prompt_of_task ~config ~code_dir task in
  let prompt =
    match plan with
    | Some p ->
        Printf.sprintf
          "%s\n\nFollow this implementation plan:\n\n%s"
          (prompt_of_task task)
          p
    | None -> prompt_of_task task
  in
  let tools = Tools.tool_defs_for_markers task.label.markers in
  match
    Ai_access.dispatch
      ~executor
      ~model:model_id
      ~system
      ~prompt
      ~cwd:code_dir
      ~quiet
      ?provider
      ~tools
      ~execute_tool:(Tools.execute ~base_dir:code_dir)
      ~max_iterations:25
      ()
  with
  | Ok (text, cost) ->
      Mutex.lock mu ;
      ( match cost with
      | Some c -> total_cost := !total_cost +. c.cost_usd
      | None -> () ) ;
      Mutex.unlock mu ;
      Ok text
  | Error e -> Error e

(** Parse HTTP response from raw socket data *)
let parse_http_response (data : string) : int * string =
  match String.split_on_char '\n' data with
  | [] -> failwith "Empty HTTP response"
  | status_line :: _ ->
      let status =
        match String.split_on_char ' ' status_line with
        | _ :: code :: _ -> (
          try int_of_string code with
          | _ -> 0 )
        | _ -> 0
      in
      let sep = "\r\n\r\n" in
      let sep_len = String.length sep in
      let data_len = String.length data in
      let body_start = ref data_len in
      for i = 0 to data_len - sep_len do
        if !body_start = data_len && String.sub data i sep_len = sep
        then body_start := i + sep_len
      done ;
      let body = String.sub data !body_start (data_len - !body_start) in
      (status, body)

(** Wire EIO-based HTTPS client into Anthropic provider *)
let wire_http_client net =
  Anthropic.send_request_ref :=
    fun ~url ~headers ~body ->
      let host = "api.anthropic.com" in
      let path =
        let prefix = "https://" ^ host in
        if String.length url > String.length prefix
        then
          String.sub
            url
            (String.length prefix)
            (String.length url - String.length prefix)
        else "/"
      in
      ignore url ;
      let addr =
        match Eio.Net.getaddrinfo_stream net host ~service:"443" with
        | addr :: _ -> addr
        | [] -> failwith "DNS resolution failed for api.anthropic.com"
      in
      Eio.Switch.run @@ fun sw ->
      let tcp_flow = Eio.Net.connect ~sw net addr in
      let authenticator =
        match Ca_certs.authenticator () with
        | Ok a -> a
        | Error (`Msg m) -> failwith ("CA certs: " ^ m)
      in
      let tls_config =
        match Tls.Config.client ~authenticator () with
        | Ok c -> c
        | Error (`Msg m) -> failwith ("TLS config: " ^ m)
      in
      let tls_flow =
        Tls_eio.client_of_flow
          tls_config
          ~host:(Domain_name.of_string_exn host |> Domain_name.host_exn)
          tcp_flow
      in
      let headers_str =
        String.concat
          ""
          (List.map (fun (k, v) -> Printf.sprintf "%s: %s\r\n" k v) headers)
      in
      let req =
        Printf.sprintf
          "POST %s HTTP/1.1\r\n\
           Host: %s\r\n\
           Connection: close\r\n\
           Content-Length: %d\r\n\
           %s\r\n\
           %s"
          path
          host
          (String.length body)
          headers_str
          body
      in
      Eio.Flow.copy_string req tls_flow ;
      Eio.Flow.shutdown tls_flow `Send ;
      let buf = Buffer.create 4096 in
      let chunk = Cstruct.create 4096 in
      ( try
          while true do
            let n = Eio.Flow.single_read tls_flow chunk in
            Buffer.add_string buf (Cstruct.to_string ~len:n chunk)
          done
        with
      | End_of_file
       |Eio.Io _ ->
          () ) ;
      parse_http_response (Buffer.contents buf)

(** Check if any model alias uses Http executor (including planner) *)
let needs_http (config : Types.config) (tasks : Types.task list) : bool =
  let planner_http =
    match Ai_access.executor_for_alias config.planner with
    | Ai_access.Http -> true
    | Ai_access.Cli _ -> false
  in
  planner_http
  || List.exists
       (fun (task : Types.task) ->
         let alias = Types.model_alias_of_class config task.model_class in
         match Ai_access.executor_for_alias alias with
         | Ai_access.Http -> true
         | Ai_access.Cli _ -> false )
       tasks

(** Validate that required directories exist *)
let validate_directories (project_path : string) (axioms_dir : string) : unit =
  if not (Sys.file_exists axioms_dir)
  then begin
    Printf.eprintf "Error: axioms/ directory not found in %s\n" project_path ;
    exit 1
  end

(** Load axiom system from directory *)
let load_system (axioms_dir : string) : Types.system =
  match Loader.load ~axioms_dir with
  | Ok s ->
      Printf.printf
        "Loaded: %s (%d axioms, %d labels)\n%!"
        s.name
        (List.length s.axioms)
        (List.length s.label_defs) ;
      s
  | Error msg ->
      Printf.eprintf "Error loading axioms: %s\n" msg ;
      exit 1

(** Run consistency checks on system *)
let run_consistency_check (system : Types.system) : unit =
  match Consistency.check system with
  | Ok () -> Printf.printf "All checks passed.\n%!"
  | Error errs ->
      List.iter
        (fun e -> Printf.eprintf "  %s\n" (Consistency.error_to_string e))
        errs ;
      exit 1

(** Compute changes based on mode (full or diff) *)
let compute_changes
    ~(config : Types.config)
    ~(project_path : string)
    ~(system : Types.system) : (string * Types.change) list option =
  match config.mode with
  | `Full ->
      Printf.printf "Full sync mode — all axioms in scope.\n%!" ;
      Snapshot.create_snapshot ~project_path ;
      None
  | `Diff -> (
      Snapshot.create_snapshot ~project_path ;
      match Snapshot.diff ~project_path with
      | None ->
          Printf.printf "No freeze found — full sync.\n%!" ;
          None
      | Some changes ->
          if changes = []
          then begin
            Printf.printf "No changes detected. Nothing to sync.\n%!" ;
            exit 0
          end ;
          Printf.printf "%d axiom(s) changed:\n%!" (List.length changes) ;
          List.iter
            (fun (id, change) ->
              let desc =
                match change with
                | Types.Added -> "added"
                | Deleted -> "deleted"
                | Modified _ -> "modified"
              in
              Printf.printf "  %s: %s\n%!" id desc )
            changes ;
          Some changes )

(** Validate markers in code directory *)
let validate_markers (code_dir : string) (system : Types.system) : unit =
  if Sys.file_exists code_dir
  then
    match Markers.validate ~code_dir system with
    | Ok () -> Printf.printf "All markers valid.\n%!"
    | Error errs ->
        Printf.printf "%d marker error(s):\n%!" (List.length errs) ;
        List.iter
          (fun e -> Printf.printf "  %s\n%!" (Markers.error_to_string e))
          errs

(** Setup HTTP provider if needed *)
let setup_http_provider ~(config : Types.config) ~(tasks : Types.task list) :
    Anthropic.provider option =
  if needs_http config tasks
  then begin
    Eio_main.run @@ fun env ->
    Mirage_crypto_rng_unix.use_default () ;
    let net = Eio.Stdenv.net env in
    wire_http_client net ;
    Some (Anthropic.provider ())
  end
  else None

(** Run semantic consistency check *)
let run_semantic_check
    ~(config : Types.config)
    ~(changes : (string * Types.change) list option)
    ~(system : Types.system)
    ~(project_path : string)
    ~(total_cost : float ref)
    ~(provider : Anthropic.provider option) : unit =
  let semantic_axioms =
    match changes with
    | Some ch ->
        let changed_ids = List.map fst ch in
        List.filter
          (fun (a : Types.axiom) -> List.mem a.id changed_ids)
          system.axioms
    | None -> system.axioms
  in
  if semantic_axioms <> [] && not config.no_semantic
  then begin
    section "Semantic consistency" ;
    let axiom_texts =
      List.map
        (fun (a : Types.axiom) ->
          Printf.sprintf "## %s\n%s" a.name a.raw_content )
        semantic_axioms
    in
    let combined = String.concat "\n\n" axiom_texts in
    match
      Consistency.check_semantic
        ~dispatch:(fun ~system ~prompt ->
          let fast_alias = config.fast in
          let model_id =
            match Ai_access.resolve_alias fast_alias with
            | Some (_, id) -> id
            | None ->
                failwith
                  (Printf.sprintf "Unknown fast model alias: %s" fast_alias)
          in
          let executor = Ai_access.executor_for_alias fast_alias in
          match
            Ai_access.dispatch
              ~executor
              ~model:model_id
              ~system
              ~prompt
              ~cwd:project_path
              ~quiet:true
              ?provider
              ()
          with
          | Ok (text, cost) ->
              ( match cost with
              | Some c -> total_cost := !total_cost +. c.cost_usd
              | None -> () ) ;
              Ok text
          | Error e -> Error e )
        combined
    with
    | Ok () -> Printf.printf "No contradictions found.\n%!"
    | Error msg ->
        Printf.eprintf "Semantic contradiction detected:\n%s\n" msg ;
        exit 1
  end

(** Create outcome recorder with mutex *)
let create_outcome_recorder () :
    Sync_result.task_outcome list ref * (Types.task -> string -> string -> unit)
    =
  let mu = Mutex.create () in
  let outcomes : Sync_result.task_outcome list ref = ref [] in
  let record_outcome (task : Types.task) (status : string) (output : string) =
    Mutex.lock mu ;
    outcomes :=
      { Sync_result.axiom_id= task.axiom_id
      ; label= task.label.name
      ; phase=
          ( match task.phase with
          | Implementation -> "implementation"
          | Validation -> "validation"
          | Satisfaction f -> Printf.sprintf "satisfaction(%.1f)" f )
      ; status
      ; output }
      :: !outcomes ;
    Mutex.unlock mu
  in
  (outcomes, record_outcome)

(** Check if validation output indicates failure *)
let validation_failed (text : string) : bool =
  let lines =
    String.split_on_char '\n' text
    |> List.filter (fun s -> String.trim s <> "")
    |> List.rev
  in
  match lines with
  | last :: _ ->
      let last = String.trim last in
      last = "VALIDATION_FAIL" || last = "FAIL"
  | [] -> false

(** Run implementation phase with planning *)
let run_implementation_phase
    ~(config : Types.config)
    ~(code_dir : string)
    ~(quiet : bool)
    ~(total_cost : float ref)
    ~(provider : Anthropic.provider option)
    ~(record_outcome : Types.task -> string -> string -> unit)
    ~(impl_tasks : Types.task list) : unit =
  if impl_tasks <> []
  then begin
    section "Planning" ;
    let plans =
      List.map
        (fun task ->
          (task, run_planner ~config ~code_dir ~quiet ~total_cost ?provider task) )
        impl_tasks
    in

    section "Implementation" ;
    List.iter
      (fun (task, plan) ->
        let model_alias =
          Types.model_alias_of_class config task.Types.model_class
        in
        Printf.printf
          "  [%s] %s impl (%s)\n%!"
          task.Types.label.name
          task.axiom_id
          model_alias ;
        let mu = Mutex.create () in
        match
          run_task ~mu ~config ~code_dir ~quiet ~total_cost ?provider ?plan task
        with
        | Ok _text ->
            Printf.printf "done\n%!" ;
            record_outcome task "ok" "implemented"
        | Error msg ->
            Printf.printf "FAILED: %s\n%!" msg ;
            record_outcome task "error" msg )
      plans
  end

(** Run validation phase in parallel *)
let run_validation_phase
    ~(config : Types.config)
    ~(code_dir : string)
    ~(quiet : bool)
    ~(total_cost : float ref)
    ~(provider : Anthropic.provider option)
    ~(record_outcome : Types.task -> string -> string -> unit)
    ~(outcomes : Sync_result.task_outcome list ref)
    ~(valid_tasks : Types.task list) : unit =
  if valid_tasks <> []
  then begin
    section "Validation" ;
    let mu = Mutex.create () in
    let run task =
      let model_alias =
        Types.model_alias_of_class config task.Types.model_class
      in
      Printf.printf
        "  [%s] %s valid (%s)\n%!"
        task.label.name
        task.axiom_id
        model_alias ;
      match
        run_task ~mu ~config ~code_dir ~quiet ~total_cost ?provider task
      with
      | Ok text ->
          record_outcome
            task
            "ok"
            (String.sub text 0 (min 200 (String.length text))) ;
          (text, true)
      | Error msg ->
          Printf.printf "FAILED: %s\n%!" msg ;
          record_outcome task "error" msg ;
          ("", false)
    in
    let slots =
      List.map
        (fun task ->
          let result = ref ("", false) in
          let t = Thread.create (fun () -> result := run task) () in
          (task, t, result) )
        valid_tasks
    in
    let results =
      List.map
        (fun (task, t, result) ->
          Thread.join t ;
          (task, !result) )
        slots
    in
    List.iter
      (fun (task, (text, ok)) ->
        if ok
        then
          if validation_failed text
          then begin
            let preview = String.sub text 0 (min 200 (String.length text)) in
            Printf.printf "  %s FAILED\n  %s\n%!" task.axiom_id preview ;
            outcomes :=
              List.map
                (fun (o : Sync_result.task_outcome) ->
                  if
                    o.axiom_id = task.axiom_id
                    && o.label = task.label.name
                    && o.status = "ok"
                  then
                    { o with
                      status= "failed"
                    ; output= String.sub text 0 (min 500 (String.length text))
                    }
                  else o )
                !outcomes
          end
          else begin
            let preview = String.sub text 0 (min 200 (String.length text)) in
            Printf.printf "  %s done\n  %s\n%!" task.axiom_id preview
          end )
      results
  end

(** Run satisfaction phase in parallel *)
let run_satisfaction_phase
    ~(config : Types.config)
    ~(code_dir : string)
    ~(quiet : bool)
    ~(total_cost : float ref)
    ~(provider : Anthropic.provider option)
    ~(satisfy_tasks : Types.task list) : unit =
  if satisfy_tasks <> []
  then begin
    section "Satisfaction" ;
    let all_pass = ref true in
    let mu = Mutex.create () in
    let run task =
      let model_alias =
        Types.model_alias_of_class config task.Types.model_class
      in
      Printf.printf
        "  [%s] %s sat (%s)\n%!"
        task.label.name
        task.axiom_id
        model_alias ;
      match
        run_task ~mu ~config ~code_dir ~quiet ~total_cost ?provider task
      with
      | Ok text -> (text, true)
      | Error msg ->
          Printf.printf "FAILED: %s\n%!" msg ;
          ("", false)
    in
    let slots =
      List.map
        (fun task ->
          let result = ref ("", false) in
          let t = Thread.create (fun () -> result := run task) () in
          (task, t, result) )
        satisfy_tasks
    in
    let results =
      List.map
        (fun (task, t, result) ->
          Thread.join t ;
          (task, !result) )
        slots
    in
    List.iter
      (fun (task, (text, ok)) ->
        if ok
        then begin
          let lines =
            String.split_on_char '\n' text
            |> List.filter (fun s -> String.trim s <> "")
          in
          let last_line =
            match List.rev lines with
            | l :: _ -> l
            | [] -> ""
          in
          try
            let rating = float_of_string (String.trim last_line) in
            let threshold =
              match task.phase with
              | Satisfaction f -> f
              | _ -> 0.7
            in
            if rating >= threshold
            then
              Printf.printf
                "  %s PASS (%.1f >= %.1f)\n%!"
                task.axiom_id
                rating
                threshold
            else begin
              Printf.printf
                "  %s FAIL (%.1f < %.1f)\n%!"
                task.axiom_id
                rating
                threshold ;
              all_pass := false
            end
          with
          | Failure _ ->
              let preview = String.sub text 0 (min 200 (String.length text)) in
              Printf.printf
                "  %s done (no rating parsed)\n  %s\n%!"
                task.axiom_id
                preview
        end
        else all_pass := false )
      results ;
    if not !all_pass
    then begin
      Printf.eprintf "\nSome satisfaction checks failed.\n" ;
      exit 1
    end
  end

(** Run fix cycle for failing axioms *)
let run_fix_cycle
    ~(config : Types.config)
    ~(code_dir : string)
    ~(quiet : bool)
    ~(total_cost : float ref)
    ~(provider : Anthropic.provider option)
    ~(record_outcome : Types.task -> string -> string -> unit)
    ~(outcomes : Sync_result.task_outcome list ref)
    ~(impl_tasks : Types.task list)
    ~(valid_tasks : Types.task list)
    ~(satisfy_tasks : Types.task list) : unit =
  let failing_axiom_ids =
    !outcomes
    |> List.filter (fun (o : Sync_result.task_outcome) ->
        o.status = "error" || o.status = "failed" )
    |> List.map (fun (o : Sync_result.task_outcome) -> o.axiom_id)
    |> List.sort_uniq String.compare
  in
  if failing_axiom_ids <> [] && config.max_cycles > 0
  then begin
    section "Fix cycle" ;
    let cycle = ref 0 in
    let still_failing = ref failing_axiom_ids in
    let mu = Mutex.create () in
    while !still_failing <> [] && !cycle < config.max_cycles do
      incr cycle ;
      Printf.printf
        "Cycle %d/%d — re-implementing %d axiom(s)\n%!"
        !cycle
        config.max_cycles
        (List.length !still_failing) ;
      let failing_errors =
        !outcomes
        |> List.filter (fun (o : Sync_result.task_outcome) ->
            o.status = "error" && List.mem o.axiom_id !still_failing )
        |> List.map (fun (o : Sync_result.task_outcome) ->
            Printf.sprintf "[%s] %s: %s" o.label o.phase o.output )
      in
      let feedback = String.concat "\n" failing_errors in
      let fix_impl_tasks =
        List.filter
          (fun (t : Types.task) -> List.mem t.axiom_id !still_failing)
          impl_tasks
      in
      List.iter
        (fun task ->
          Printf.printf "  fix [%s] %s ... %!" task.label.name task.axiom_id ;
          let fix_prompt =
            Printf.sprintf
              "%s\n\n\
               Previous attempt failed with these errors:\n\
               %s\n\n\
               Fix the issues."
              (prompt_of_task task)
              feedback
          in
          let model_alias =
            Types.model_alias_of_class config task.model_class
          in
          let model_id =
            match Ai_access.resolve_alias model_alias with
            | Some (_, id) -> id
            | None -> failwith "Unknown model alias"
          in
          let executor = Ai_access.executor_for_alias model_alias in
          let system = system_prompt_of_task ~config ~code_dir task in
          let tools = Tools.tool_defs_for_markers task.label.markers in
          match
            Ai_access.dispatch
              ~executor
              ~model:model_id
              ~system
              ~prompt:fix_prompt
              ~cwd:code_dir
              ~quiet
              ?provider
              ~tools
              ~execute_tool:(Tools.execute ~base_dir:code_dir)
              ~max_iterations:25
              ()
          with
          | Ok (_text, cost) ->
              ( match cost with
              | Some c -> total_cost := !total_cost +. c.cost_usd
              | None -> () ) ;
              Printf.printf "done\n%!" ;
              record_outcome task "ok" "fixed"
          | Error msg ->
              Printf.printf "FAILED: %s\n%!" msg ;
              record_outcome task "error" msg )
        fix_impl_tasks ;
      let fix_valid_tasks =
        List.filter
          (fun (t : Types.task) -> List.mem t.axiom_id !still_failing)
          (valid_tasks @ satisfy_tasks)
      in
      let run task =
        let model_alias =
          Types.model_alias_of_class config task.Types.model_class
        in
        Printf.printf
          "  [%s] %s fix (%s)\n%!"
          task.label.name
          task.axiom_id
          model_alias ;
        match
          run_task ~mu ~config ~code_dir ~quiet ~total_cost ?provider task
        with
        | Ok text -> (text, true)
        | Error msg ->
            Printf.printf "FAILED: %s\n%!" msg ;
            ("", false)
      in
      let new_failures = ref [] in
      List.iter
        (fun task ->
          let text, ok = run task in
          if (not ok) || validation_failed text
          then new_failures := task.axiom_id :: !new_failures )
        fix_valid_tasks ;
      still_failing := List.sort_uniq String.compare !new_failures
    done ;
    if !still_failing <> []
    then begin
      Printf.eprintf
        "Fix cycle exhausted. Still failing: %s\n"
        (String.concat ", " !still_failing) ;
      exit 1
    end
  end

(** Write sync results and save freeze *)
let save_results
    ~(project_path : string)
    ~(total_cost : float)
    ~(outcomes : Sync_result.task_outcome list)
    ~(mode : [`Full | `Diff]) : unit =
  let summary : Sync_result.sync_summary =
    { total_cost
    ; outcomes
    ; mode=
        ( match mode with
        | `Full -> "full"
        | `Diff -> "diff" ) }
  in
  Sync_result.write ~project_path summary ;
  section "Saving freeze" ;
  Snapshot.save_freeze ~project_path ;
  Printf.printf "Sync complete. Total cost: $%.4f\n%!" total_cost

(** Main entry point *)
let () =
  let config, quiet = Config.load () in
  let project_path = config.project_path in
  let axioms_dir = Filename.concat project_path "axioms" in
  let code_dir = Filename.concat project_path "code" in

  validate_directories project_path axioms_dir ;

  section "Loading axioms" ;
  let system = load_system axioms_dir in

  section "Consistency checks" ;
  run_consistency_check system ;

  section "Snapshot & diff" ;
  let changes = compute_changes ~config ~project_path ~system in
  let change_list =
    match changes with
    | None ->
        List.map (fun (a : Types.axiom) -> (a.id, Types.Added)) system.axioms
    | Some c -> c
  in

  section "Marker validation" ;
  validate_markers code_dir system ;

  section "Planning tasks" ;
  let impl_tasks = Planner.implementation_tasks system change_list in
  let valid_tasks = Planner.validation_tasks system change_list in
  let satisfy_tasks = Planner.satisfaction_tasks system change_list in
  Printf.printf "Implementation: %d tasks\n%!" (List.length impl_tasks) ;
  Printf.printf "Validation:     %d tasks\n%!" (List.length valid_tasks) ;
  Printf.printf "Satisfaction:   %d tasks\n%!" (List.length satisfy_tasks) ;

  if impl_tasks = [] && valid_tasks = [] && satisfy_tasks = []
  then begin
    Printf.printf "\nNo tasks to execute.\n%!" ;
    Snapshot.save_freeze ~project_path ;
    exit 0
  end ;

  let all_tasks = impl_tasks @ valid_tasks @ satisfy_tasks in
  let provider = setup_http_provider ~config ~tasks:all_tasks in

  let total_cost = ref 0.0 in

  run_semantic_check
    ~config
    ~changes
    ~system
    ~project_path
    ~total_cost
    ~provider ;

  let outcomes, record_outcome = create_outcome_recorder () in

  run_implementation_phase
    ~config
    ~code_dir
    ~quiet
    ~total_cost
    ~provider
    ~record_outcome
    ~impl_tasks ;

  run_validation_phase
    ~config
    ~code_dir
    ~quiet
    ~total_cost
    ~provider
    ~record_outcome
    ~outcomes
    ~valid_tasks ;

  run_satisfaction_phase
    ~config
    ~code_dir
    ~quiet
    ~total_cost
    ~provider
    ~satisfy_tasks ;

  run_fix_cycle
    ~config
    ~code_dir
    ~quiet
    ~total_cost
    ~provider
    ~record_outcome
    ~outcomes
    ~impl_tasks
    ~valid_tasks
    ~satisfy_tasks ;

  save_results
    ~project_path
    ~total_cost:!total_cost
    ~outcomes:(List.rev !outcomes)
    ~mode:config.mode
