(** axioms-sync CLI — orchestrates axiom synchronization *)

open Axioms_sync

(** Parse CLI arguments into config + quiet flag *)
let parse_args () : Types.config * bool =
  let config = ref Types.default_config in
  let quiet = ref false in
  let args = Array.to_list Sys.argv |> List.tl in
  let rec parse = function
    | [] -> ()
    | "--full" :: rest ->
      config := { !config with mode = `Full }; parse rest
    | ("--quiet" | "-q") :: rest ->
      quiet := true; parse rest
    | "--implementer" :: v :: rest ->
      config := { !config with implementer = v }; parse rest
    | "--planner" :: v :: rest ->
      config := { !config with planner = v }; parse rest
    | "--smart" :: v :: rest ->
      config := { !config with smart = v }; parse rest
    | "--balanced" :: v :: rest ->
      config := { !config with balanced = v }; parse rest
    | "--fast" :: v :: rest ->
      config := { !config with fast = v }; parse rest
    | path :: rest when not (String.length path > 0 && path.[0] = '-') ->
      config := { !config with project_path = path }; parse rest
    | unknown :: _ ->
      Printf.eprintf "Unknown argument: %s\n" unknown;
      Printf.eprintf "Usage: axioms-sync [PATH] [OPTIONS]\n";
      Printf.eprintf "  --full              Full sync (not diff)\n";
      Printf.eprintf "  -q, --quiet         Suppress agent streaming output\n";
      Printf.eprintf "  --implementer MODEL Model alias for implementation\n";
      Printf.eprintf "  --planner MODEL     Model alias for planning\n";
      Printf.eprintf "  --smart MODEL       Model alias for smart class\n";
      Printf.eprintf "  --balanced MODEL    Model alias for balanced class\n";
      Printf.eprintf "  --fast MODEL        Model alias for fast class\n";
      exit 1
  in
  parse args;
  (!config, !quiet)

let section title =
  Printf.printf "\n── %s ──\n%!" title

(** Build system prompt for a task *)
let system_prompt_of_task ~(code_dir : string) (task : Types.task) : string =
  Printf.sprintf
    "You are an AI agent working on the project. Phase: %s. Label: %s.\n\n\
     Your task is defined by the following axiom specification:\n\n%s\n\n\
     Label description: %s\n\n\
     Work in the code/ directory: %s"
    (match task.phase with
     | Types.Implementation -> "implementation"
     | Validation -> "validation"
     | Satisfaction f -> Printf.sprintf "satisfaction (threshold: %.1f)" f)
    task.label.name
    task.context
    task.label.description
    code_dir

let prompt_of_task (task : Types.task) : string =
  match task.phase with
  | Types.Implementation ->
    Printf.sprintf "Implement the requirements from axiom '%s' for label [%s]. \
      Use @axiom markers to trace code back to the axiom file." task.axiom_id task.label.name
  | Validation ->
    Printf.sprintf "Validate the implementation of axiom '%s' for label [%s]. \
      Report any issues found." task.axiom_id task.label.name
  | Satisfaction threshold ->
    Printf.sprintf "Review the implementation of axiom '%s' for label [%s]. \
      Rate satisfaction from 0.0 to 1.0 (threshold: %.1f). \
      Return your rating as a number on the last line." task.axiom_id task.label.name threshold

(** Run the planner model to create an implementation plan for a task *)
let run_planner ~(config : Types.config) ~(code_dir : string) ~(quiet : bool) ?provider (task : Types.task) : string option =
  let planner_alias = config.planner in
  let model_id = match Ai_access.resolve_alias planner_alias with
    | Some (_, id) -> id
    | None -> failwith (Printf.sprintf "Unknown planner model alias: %s" planner_alias)
  in
  let executor = Ai_access.executor_for_alias planner_alias in
  let system = Printf.sprintf
    "You are a planning agent. Your job is to analyze the axiom specification and \
     create a detailed implementation plan. Do NOT implement anything — only plan.\n\n\
     Axiom specification:\n\n%s\n\n\
     Label: %s — %s\n\n\
     Code directory: %s\n\n\
     Output a step-by-step plan describing:\n\
     - What files to create or modify\n\
     - What each file should contain\n\
     - How to use @axiom markers for traceability\n\
     - Any dependencies between steps"
    task.context task.label.name task.label.description code_dir
  in
  let prompt = Printf.sprintf
    "Create an implementation plan for axiom '%s', label [%s]."
    task.axiom_id task.label.name
  in
  (* Planner gets read-only tools — can inspect code but not modify *)
  let tools = Tools.tool_defs_for_markers [Types.Code] in
  let read_only_tools = List.filter (fun (td : Ai_access.tool_def) ->
    td.name = "read_file" || td.name = "list_files"
  ) tools in
  Printf.printf "  planning [%s] %s (%s) ... %!" task.label.name task.axiom_id planner_alias;
  match Ai_access.dispatch
    ~executor ~model:model_id ~system ~prompt ~cwd:code_dir ~quiet
    ?provider ~tools:read_only_tools ~execute_tool:(Tools.execute ~base_dir:code_dir)
    ~max_iterations:10 ()
  with
  | Ok plan ->
    Printf.printf "done\n%!";
    Some plan
  | Error msg ->
    Printf.printf "FAILED: %s\n%!" msg;
    None

(** Run a single task — executor is resolved from model alias by ai_access.
    If plan is provided, it's injected into the implementation prompt. *)
let run_task ~(config : Types.config) ~(code_dir : string) ~(quiet : bool) ?provider ?plan (task : Types.task) : (string, string) result =
  let model_alias = Types.model_alias_of_class config task.model_class in
  let model_id = match Ai_access.resolve_alias model_alias with
    | Some (_, id) -> id
    | None -> failwith (Printf.sprintf "Unknown model alias: %s" model_alias)
  in
  let executor = Ai_access.executor_for_alias model_alias in
  let system = system_prompt_of_task ~code_dir task in
  let prompt = match plan with
    | Some p ->
      Printf.sprintf "%s\n\nFollow this implementation plan:\n\n%s" (prompt_of_task task) p
    | None -> prompt_of_task task
  in
  let tools = Tools.tool_defs_for_markers task.label.markers in
  Ai_access.dispatch
    ~executor ~model:model_id ~system ~prompt ~cwd:code_dir ~quiet
    ?provider ~tools ~execute_tool:(Tools.execute ~base_dir:code_dir)
    ~max_iterations:25 ()

(** Parse HTTP response from raw socket data *)
let parse_http_response (data : string) : int * string =
  match String.split_on_char '\n' data with
  | [] -> failwith "Empty HTTP response"
  | status_line :: _ ->
    let status = match String.split_on_char ' ' status_line with
      | _ :: code :: _ -> (try int_of_string code with _ -> 0)
      | _ -> 0
    in
    let sep = "\r\n\r\n" in
    let sep_len = String.length sep in
    let data_len = String.length data in
    let body_start = ref data_len in
    for i = 0 to data_len - sep_len do
      if !body_start = data_len && String.sub data i sep_len = sep then
        body_start := i + sep_len
    done;
    let body = String.sub data !body_start (data_len - !body_start) in
    (status, body)

(** Wire EIO-based HTTPS client into Anthropic provider *)
let wire_http_client net =
  Anthropic.send_request_ref := (fun ~url ~headers ~body ->
    let host = "api.anthropic.com" in
    let path =
      let prefix = "https://" ^ host in
      if String.length url > String.length prefix then
        String.sub url (String.length prefix) (String.length url - String.length prefix)
      else "/"
    in
    ignore url;
    let addr = match Eio.Net.getaddrinfo_stream net host ~service:"443" with
      | addr :: _ -> addr
      | [] -> failwith "DNS resolution failed for api.anthropic.com"
    in
    Eio.Switch.run @@ fun sw ->
    let tcp_flow = Eio.Net.connect ~sw net addr in
    let authenticator = match Ca_certs.authenticator () with
      | Ok a -> a | Error (`Msg m) -> failwith ("CA certs: " ^ m) in
    let tls_config = match Tls.Config.client ~authenticator () with
      | Ok c -> c | Error (`Msg m) -> failwith ("TLS config: " ^ m) in
    let tls_flow = Tls_eio.client_of_flow tls_config
      ~host:(Domain_name.of_string_exn host |> Domain_name.host_exn)
      tcp_flow in
    let headers_str = String.concat ""
      (List.map (fun (k, v) -> Printf.sprintf "%s: %s\r\n" k v) headers) in
    let req = Printf.sprintf
      "POST %s HTTP/1.1\r\nHost: %s\r\nConnection: close\r\nContent-Length: %d\r\n%s\r\n%s"
      path host (String.length body) headers_str body in
    Eio.Flow.copy_string req tls_flow;
    Eio.Flow.shutdown tls_flow `Send;
    let buf = Buffer.create 4096 in
    let chunk = Cstruct.create 4096 in
    (try while true do
      let n = Eio.Flow.single_read tls_flow chunk in
      Buffer.add_string buf (Cstruct.to_string ~len:n chunk)
    done with End_of_file | Eio.Io _ -> ());
    parse_http_response (Buffer.contents buf)
  )

(** Check if any model alias uses Http executor (including planner) *)
let needs_http (config : Types.config) (tasks : Types.task list) : bool =
  let planner_http = match Ai_access.executor_for_alias config.planner with
    | Ai_access.Http -> true | Ai_access.Cli _ -> false in
  planner_http || List.exists (fun (task : Types.task) ->
    let alias = Types.model_alias_of_class config task.model_class in
    match Ai_access.executor_for_alias alias with
    | Ai_access.Http -> true
    | Ai_access.Cli _ -> false
  ) tasks

(** Main entry point *)
let () =
  let (config, quiet) = parse_args () in
  let project_path = config.project_path in
  let axioms_dir = Filename.concat project_path "axioms" in
  let code_dir = Filename.concat project_path "code" in

  if not (Sys.file_exists axioms_dir) then begin
    Printf.eprintf "Error: axioms/ directory not found in %s\n" project_path;
    exit 1
  end;

  section "Loading axioms";
  let system = match Loader.load ~axioms_dir with
    | Ok s -> s
    | Error msg ->
      Printf.eprintf "Error loading axioms: %s\n" msg;
      exit 1
  in
  Printf.printf "Loaded: %s (%d axioms, %d labels)\n%!"
    system.name (List.length system.axioms) (List.length system.label_defs);

  section "Consistency checks";
  (match Consistency.check system with
   | Ok () -> Printf.printf "All checks passed.\n%!"
   | Error errs ->
     List.iter (fun e -> Printf.eprintf "  %s\n" (Consistency.error_to_string e)) errs;
     exit 1);

  section "Snapshot & diff";
  let changes = match config.mode with
    | `Full ->
      Printf.printf "Full sync mode — all axioms in scope.\n%!";
      Snapshot.create_snapshot ~project_path;
      None
    | `Diff ->
      Snapshot.create_snapshot ~project_path;
      (match Snapshot.diff ~project_path with
       | None ->
         Printf.printf "No freeze found — full sync.\n%!";
         None
       | Some changes ->
         if changes = [] then begin
           Printf.printf "No changes detected. Nothing to sync.\n%!";
           exit 0
         end;
         Printf.printf "%d axiom(s) changed:\n%!" (List.length changes);
         List.iter (fun (id, change) ->
           let desc = match change with
             | Types.Added -> "added"
             | Deleted -> "deleted"
             | Modified _ -> "modified"
           in
           Printf.printf "  %s: %s\n%!" id desc
         ) changes;
         Some changes)
  in
  let change_list = match changes with
    | None -> List.map (fun (a : Types.axiom) -> (a.id, Types.Added)) system.axioms
    | Some c -> c
  in

  section "Marker validation";
  if Sys.file_exists code_dir then
    (match Markers.validate ~code_dir system with
     | Ok () -> Printf.printf "All markers valid.\n%!"
     | Error errs ->
       Printf.printf "%d marker error(s):\n%!" (List.length errs);
       List.iter (fun e -> Printf.printf "  %s\n%!" (Markers.error_to_string e)) errs);

  section "Planning tasks";
  let impl_tasks = Planner.implementation_tasks system change_list in
  let valid_tasks = Planner.validation_tasks system change_list in
  let satisfy_tasks = Planner.satisfaction_tasks system change_list in
  Printf.printf "Implementation: %d tasks\n%!" (List.length impl_tasks);
  Printf.printf "Validation:     %d tasks\n%!" (List.length valid_tasks);
  Printf.printf "Satisfaction:   %d tasks\n%!" (List.length satisfy_tasks);

  if impl_tasks = [] && valid_tasks = [] && satisfy_tasks = [] then begin
    Printf.printf "\nNo tasks to execute.\n%!";
    Snapshot.save_freeze ~project_path;
    exit 0
  end;

  let all_tasks = impl_tasks @ valid_tasks @ satisfy_tasks in

  (* Wire HTTP client only if needed *)
  let provider = ref None in
  if needs_http config all_tasks then begin
    Eio_main.run @@ fun env ->
    Mirage_crypto_rng_unix.use_default ();
    let net = Eio.Stdenv.net env in
    wire_http_client net;
    provider := Some (Anthropic.provider ())
  end;

  let run task =
    Printf.printf "  [%s] %s ... %!" task.Types.label.name task.axiom_id;
    match run_task ~config ~code_dir ~quiet ?provider:!provider task with
    | Ok text -> (text, true)
    | Error msg -> Printf.printf "FAILED: %s\n%!" msg; ("", false)
  in

  if impl_tasks <> [] then begin
    (* Step 5a: Planning *)
    section "Planning";
    let plans = List.map (fun task ->
      (task, run_planner ~config ~code_dir ~quiet ?provider:!provider task)
    ) impl_tasks in

    (* Step 5b: Implementation with plans *)
    section "Implementation";
    List.iter (fun (task, plan) ->
      Printf.printf "  [%s] %s ... %!" task.Types.label.name task.axiom_id;
      match run_task ~config ~code_dir ~quiet ?provider:!provider ?plan task with
      | Ok _text -> Printf.printf "done\n%!"
      | Error msg -> Printf.printf "FAILED: %s\n%!" msg
    ) plans
  end;

  if valid_tasks <> [] then begin
    section "Validation";
    List.iter (fun task ->
      let (text, ok) = run task in
      if ok then begin
        let preview = String.sub text 0 (min 200 (String.length text)) in
        Printf.printf "done\n  %s\n%!" preview
      end
    ) valid_tasks
  end;

  if satisfy_tasks <> [] then begin
    section "Satisfaction";
    let all_pass = ref true in
    List.iter (fun (task : Types.task) ->
      let (text, ok) = run task in
      if ok then begin
        let lines = String.split_on_char '\n' text |> List.filter (fun s -> String.trim s <> "") in
        let last_line = match List.rev lines with l :: _ -> l | [] -> "" in
        (try
          let rating = float_of_string (String.trim last_line) in
          let threshold = match task.phase with Satisfaction f -> f | _ -> 0.7 in
          if rating >= threshold then
            Printf.printf "PASS (%.1f >= %.1f)\n%!" rating threshold
          else begin
            Printf.printf "FAIL (%.1f < %.1f)\n%!" rating threshold;
            all_pass := false
          end
        with Failure _ ->
          let preview = String.sub text 0 (min 200 (String.length text)) in
          Printf.printf "done (no rating parsed)\n  %s\n%!" preview)
      end else
        all_pass := false
    ) satisfy_tasks;
    if not !all_pass then begin
      Printf.eprintf "\nSome satisfaction checks failed.\n";
      exit 1
    end
  end;

  section "Saving freeze";
  Snapshot.save_freeze ~project_path;
  Printf.printf "Sync complete.\n%!"
