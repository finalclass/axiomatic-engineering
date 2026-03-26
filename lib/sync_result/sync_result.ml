(** Sync result — renders sync-result.md with YAML frontmatter + task table *)

type task_outcome = {
  axiom_id: string;
  label: string;
  phase: string;
  status: string;
  output: string;
}

type sync_summary = {
  total_cost: float;
  outcomes: task_outcome list;
  mode: string;
}

let render (summary : sync_summary) : string =
  let buf = Buffer.create 1024 in
  Buffer.add_string buf "---\n";
  Buffer.add_string buf (Printf.sprintf "mode: %s\n" summary.mode);
  Buffer.add_string buf (Printf.sprintf "total_cost_usd: %.4f\n" summary.total_cost);
  Buffer.add_string buf (Printf.sprintf "tasks: %d\n" (List.length summary.outcomes));
  let ok_count = List.length (List.filter (fun o -> o.status = "ok") summary.outcomes) in
  let err_count = List.length summary.outcomes - ok_count in
  Buffer.add_string buf (Printf.sprintf "passed: %d\n" ok_count);
  Buffer.add_string buf (Printf.sprintf "failed: %d\n" err_count);
  Buffer.add_string buf "---\n\n";
  Buffer.add_string buf "# Sync Result\n\n";
  Buffer.add_string buf "| Axiom | Label | Phase | Status |\n";
  Buffer.add_string buf "|-------|-------|-------|--------|\n";
  List.iter (fun (o : task_outcome) ->
    Buffer.add_string buf (Printf.sprintf "| %s | %s | %s | %s |\n"
      o.axiom_id o.label o.phase o.status)
  ) summary.outcomes;
  if summary.total_cost > 0.0 then
    Buffer.add_string buf (Printf.sprintf "\nTotal cost: $%.4f\n" summary.total_cost);
  Buffer.contents buf

let write ~(project_path : string) (summary : sync_summary) : unit =
  let axioms_dir = Filename.concat project_path ".axioms" in
  if not (Sys.file_exists axioms_dir) then
    Unix.mkdir axioms_dir 0o755;
  let path = Filename.concat axioms_dir "sync-result.md" in
  let oc = Out_channel.open_text path in
  Out_channel.output_string oc (render summary);
  Out_channel.close oc
