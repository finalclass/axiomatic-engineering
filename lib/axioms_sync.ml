module Config = Config

let section title =
  Fmt.pr
    "────────────────────────────────────────────────────────────────────────────────────────────────────\n\
     %s\n\
     ────────────────────────────────────────────────────────────────────────────────────────────────────\n"
    title

let run ~(config : Types.config) =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun _sw ->
  let fs = Eio.Stdenv.fs env in
  let project_path = Eio.Path.(fs / config.project_path) in
  let axioms_dir = Eio.Path.(project_path / "axioms") in
  let code_dir = Eio.Path.(project_path / "code") in
  let system = Loader.load_exn axioms_dir in

  section "Initial request validation" ;
  Consistency.check_exn system ;
  let changes = Changes.compute_changes_exn ~config ~project_path ~system in
  Markers.validate_exn code_dir system ;

  section "Planning tasks" ;

  let _impl_tasks = Planner.implementation_tasks system changes in

  Fmt.pr "IMPL TASKS: %s@." ([%show: Types.task list] _impl_tasks) ;

  ()

(* section "Planning tasks" ; *)
(* let impl_tasks = Planner.implementation_tasks system change_list in *)
(* let valid_tasks = Planner.validation_tasks system change_list in *)
(* let satisfy_tasks = Planner.satisfaction_tasks system change_list in *)
(* Printf.printf "Implementation: %d tasks\n%!" (List.length impl_tasks) ; *)
(* Printf.printf "Validation:     %d tasks\n%!" (List.length valid_tasks) ; *)
(* Printf.printf "Satisfaction:   %d tasks\n%!" (List.length satisfy_tasks) ; *)

(* failwith "DONE" |> ignore ; *)

(* if impl_tasks = [] && valid_tasks = [] && satisfy_tasks = [] *)
(* then begin *)
(*   Printf.printf "\nNo tasks to execute.\n%!" ; *)
(*   Snapshot.save_freeze ~project_path ; *)
(*   exit 0 *)
(* end ; *)

(* let all_tasks = impl_tasks @ valid_tasks @ satisfy_tasks in *)
(* let provider = setup_http_provider ~config ~tasks:all_tasks in *)

(* let total_cost = ref 0.0 in *)

(* run_semantic_check *)
(*   ~config *)
(*   ~changes *)
(*   ~system *)
(*   ~project_path *)
(*   ~total_cost *)
(*   ~provider ; *)

(* let outcomes, record_outcome = create_outcome_recorder () in *)

(* run_implementation_phase *)
(*   ~config *)
(*   ~code_dir *)
(*   ~quiet *)
(*   ~total_cost *)
(*   ~provider *)
(*   ~record_outcome *)
(*   ~impl_tasks ; *)

(* run_validation_phase *)
(*   ~config *)
(*   ~code_dir *)
(*   ~quiet *)
(*   ~total_cost *)
(*   ~provider *)
(*   ~record_outcome *)
(*   ~outcomes *)
(*   ~valid_tasks ; *)

(* run_satisfaction_phase *)
(*   ~config *)
(*   ~code_dir *)
(*   ~quiet *)
(*   ~total_cost *)
(*   ~provider *)
(*   ~satisfy_tasks ; *)

(* run_fix_cycle *)
(*   ~config *)
(*   ~code_dir *)
(*   ~quiet *)
(*   ~total_cost *)
(*   ~provider *)
(*   ~record_outcome *)
(*   ~outcomes *)
(*   ~impl_tasks *)
(*   ~valid_tasks *)
(*   ~satisfy_tasks ; *)

(* save_results *)
(*   ~project_path *)
(*   ~total_cost:!total_cost *)
(*   ~outcomes:(List.rev !outcomes) *)
(*   ~mode:config.mode *)
