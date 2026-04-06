module Config = Config

let section title =
  Fmt.pr
    "────────────────────────────────────────────────────────────────────────────────────────────────────\n\
     %s\n\
     ────────────────────────────────────────────────────────────────────────────────────────────────────\n"
    title

let ensure_sth_to_implement ~impl_tasks f =
  match impl_tasks with
  | [] ->
      Fmt.pr "\nNo tasks to execute.\n%!@." ;
      ()
  | _ -> f ()

let run ~(config : Types.config) =
  Mirage_crypto_rng_unix.use_default () ;
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun _sw ->
  Ai_access.set_net (Eio.Stdenv.net env) ;
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

  let impl_tasks = Planner.implementation_tasks system changes in
  let _valid_tasks = Planner.validation_tasks system changes in
  let _satisfy_tasks = Planner.satisfaction_tasks system changes in

  ensure_sth_to_implement ~impl_tasks @@ fun () ->
  section "Semantic check" ;
  Consistency.check_semantic_exn ~system ;

  section "Implementation phase" ;

  ()

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
