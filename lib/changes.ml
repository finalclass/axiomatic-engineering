let compute_changes_exn
    ~(config : Types.config)
    ~project_path
    ~(system : Types.axiom_system) : (Types.axiom * Types.change) list =
  let project_path = Eio.Path.native_exn project_path in
  match config.mode with
  | `Full ->
      Printf.printf "Full sync mode — all axioms in scope.\n%!" ;
      Snapshot.create_snapshot ~project_path ;
      List.map (fun (a : Types.axiom) -> (a, Types.Added)) system.axioms
  | `Specific axiom_ids ->
      Fmt.pr "Syncing axioms: %s@." ([%show: string list] axiom_ids) ;
      let matched =
        List.filter_map
          (fun (a : Types.axiom) ->
            if List.mem a.id axiom_ids
            then Some (a, Types.Modified [])
            else None )
          system.axioms
      in
      let matched_ids =
        List.map (fun ((a : Types.axiom), _) -> a.id) matched
      in
      let missing =
        List.filter (fun id -> not (List.mem id matched_ids)) axiom_ids
      in
      List.iter (fun id -> Fmt.pr "Warning: axiom %s not found@." id) missing ;
      if matched = []
      then begin
        Printf.printf "No matching axioms found. Nothing to sync.\n%!" ;
        exit 0
      end ;
      Printf.printf "%d axiom(s) selected:\n%!" (List.length matched) ;
      List.iter
        (fun ((a : Types.axiom), _) -> Printf.printf "  %s\n%!" a.id)
        matched ;
      matched
  | `Diff -> (
      Snapshot.create_snapshot ~project_path ;
      match Snapshot.diff ~project_path with
      | None ->
          Printf.printf "No freeze found — full sync.\n%!" ;
          []
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
          let filtered =
            List.filter_map
              (fun (a : Types.axiom) ->
                match List.assoc_opt a.id changes with
                | None -> None
                | Some change -> Some (a, change) )
              system.axioms
          in
          filtered )
