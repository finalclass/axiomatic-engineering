let command_succeeds cmd = Sys.command cmd = 0

let render_markdown_with_glow text =
  if not (command_succeeds "command -v glow >/dev/null 2>&1")
  then false
  else
    let path = Filename.temp_file "axioms-sync-error-" ".md" in
    Out_channel.with_open_text path (fun oc -> output_string oc text) ;
    Fun.protect
      ~finally:(fun () -> if Sys.file_exists path then Sys.remove path)
      (fun () ->
        let cmd = Printf.sprintf "glow -s auto %s" (Filename.quote path) in
        command_succeeds cmd )

let report_failure msg =
  prerr_endline "" ;
  if not (render_markdown_with_glow msg) then prerr_endline msg

let () =
  try
    let config = Axioms_sync.Config.load () in
    Axioms_sync.run ~config
  with
  | Failure msg ->
      report_failure msg ;
      exit 1
