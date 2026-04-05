(** AI Access — provider abstraction, executors, and agent loop *)

(** Executor: how to run a model. *)
type executor =
  | Cli of string  (** command name, e.g. "claude", "kilo" *)
  | Http  (** use HTTP provider + internal agent loop *)

type message_role =
  | User
  | Assistant

type content =
  | Text of string
  | Tool_use of
      { id: string
      ; name: string
      ; input: Yojson.Safe.t }
  | Tool_result of
      { tool_use_id: string
      ; content: string
      ; is_error: bool }

type message =
  { role: message_role
  ; content: content list }

type tool_def =
  { name: string
  ; description: string
  ; input_schema: Yojson.Safe.t }

type response =
  { content: content list
  ; stop_reason: string  (** "end_turn" | "tool_use" *) }

(** e.g. "opus4.6", "sonnet4.6", "haiku4.5" *)
type model_alias = string

type provider =
  { name: string
  ; send:
         model:string
      -> system:string
      -> messages:message list
      -> tools:tool_def list
      -> max_tokens:int
      -> response * (int * int) }

(** Known model aliases -> (provider_name, full_model_id) *)
let resolve_alias (alias : model_alias) : (string * string) option =
  match alias with
  | "opus4.6" -> Some ("anthropic", "claude-opus-4-6")
  | "sonnet4.6" -> Some ("anthropic", "claude-sonnet-4-6")
  | "haiku4.5" -> Some ("anthropic", "claude-haiku-4-5-20251001")
  | "deepseek-v3.2" -> Some ("deepseek", "deepseek-v3.2")
  | _ -> None

(** How to execute a given model alias. Hardcoded routing. *)
let executor_for_alias (alias : model_alias) : executor =
  match alias with
  | "opus4.6"
   |"sonnet4.6"
   |"haiku4.5" ->
      Cli "claude"
  | "deepseek-v3.2" -> Http
  (* Future: | "glm5" -> Cli "kilo" *)
  | _ -> Http

(** Encode message role to string *)
let role_to_string = function
  | User -> "user"
  | Assistant -> "assistant"

(** Encode content block to JSON *)
let content_to_json = function
  | Text s -> `Assoc [("type", `String "text"); ("text", `String s)]
  | Tool_use {id; name; input} ->
      `Assoc
        [ ("type", `String "tool_use")
        ; ("id", `String id)
        ; ("name", `String name)
        ; ("input", input) ]
  | Tool_result {tool_use_id; content; is_error} ->
      `Assoc
        ( [ ("type", `String "tool_result")
          ; ("tool_use_id", `String tool_use_id)
          ; ("content", `String content) ]
        @ if is_error then [("is_error", `Bool true)] else [] )

(** Encode message to JSON *)
let message_to_json (msg : message) : Yojson.Safe.t =
  `Assoc
    [ ("role", `String (role_to_string msg.role))
    ; ("content", `List (List.map content_to_json msg.content)) ]

(** Encode tool_def to JSON *)
let tool_def_to_json (td : tool_def) : Yojson.Safe.t =
  `Assoc
    [ ("name", `String td.name)
    ; ("description", `String td.description)
    ; ("input_schema", td.input_schema) ]

(** Parse content block from JSON *)
let content_of_json (json : Yojson.Safe.t) : content option =
  let open Yojson.Safe.Util in
  let typ = json |> member "type" |> to_string_option in
  match typ with
  | Some "text" ->
      let text = json |> member "text" |> to_string in
      Some (Text text)
  | Some "tool_use" ->
      let id = json |> member "id" |> to_string in
      let name = json |> member "name" |> to_string in
      let input = json |> member "input" in
      Some (Tool_use {id; name; input})
  | _ -> None

(** Parse usage from API response JSON *)
let usage_of_json (json : Yojson.Safe.t) : int * int =
  let open Yojson.Safe.Util in
  let usage = json |> member "usage" in
  let input_tokens =
    usage |> member "input_tokens" |> to_int_option |> Option.value ~default:0
  in
  let output_tokens =
    usage |> member "output_tokens" |> to_int_option |> Option.value ~default:0
  in
  (input_tokens, output_tokens)

(** Parse response from JSON *)
let response_of_json (json : Yojson.Safe.t) : response * (int * int) =
  let open Yojson.Safe.Util in
  let content_list = json |> member "content" |> to_list in
  let content = List.filter_map content_of_json content_list in
  let stop_reason =
    json
    |> member "stop_reason"
    |> to_string_option
    |> Option.value ~default:"end_turn"
  in
  let usage = usage_of_json json in
  ({content; stop_reason}, usage)

(** Extract all text content from a response *)
let response_text (resp : response) : string =
  resp.content
  |> List.filter_map (fun c ->
      match c with
      | Text s -> Some s
      | _ -> None )
  |> String.concat "\n"

(** Extract tool_use blocks from response content *)
let extract_tool_uses (content : content list) :
    (string * string * Yojson.Safe.t) list =
  List.filter_map
    (fun c ->
      match c with
      | Tool_use {id; name; input} -> Some (id, name, input)
      | _ -> None )
    content

(** Estimate cost from token counts. Rough pricing per model. *)
let estimate_cost_usd
    ~(model : string)
    ~(input_tokens : int)
    ~(output_tokens : int) : float =
  let inp_per_m, out_per_m =
    match model with
    | m when String.length m >= 11 && String.sub m 0 11 = "claude-opus" ->
        (15.0, 75.0)
    | m when String.length m >= 13 && String.sub m 0 13 = "claude-sonnet" ->
        (3.0, 15.0)
    | m when String.length m >= 12 && String.sub m 0 12 = "claude-haiku" ->
        (0.25, 1.25)
    | _ -> (3.0, 15.0)
    (* default to sonnet pricing *)
  in
  (float_of_int input_tokens *. inp_per_m /. 1_000_000.0)
  +. (float_of_int output_tokens *. out_per_m /. 1_000_000.0)

(** Run an agent loop: send prompt, execute tool calls, repeat until end_turn *)
let run_agent
    ~(provider : provider)
    ~(model : string)
    ~(system : string)
    ~(prompt : string)
    ~(tools : tool_def list)
    ~(execute_tool : string -> Yojson.Safe.t -> string)
    ~(max_iterations : int) : (string * Types.cost_info option, string) result =
  let messages = ref [{role= User; content= [Text prompt]}] in
  let iteration = ref 0 in
  let finished = ref false in
  let final_text = ref "" in
  let total_input = ref 0 in
  let total_output = ref 0 in

  while (not !finished) && !iteration < max_iterations do
    incr iteration ;
    let resp, (inp, outp) =
      provider.send ~model ~system ~messages:!messages ~tools ~max_tokens:8192
    in
    total_input := !total_input + inp ;
    total_output := !total_output + outp ;

    if resp.stop_reason = "tool_use"
    then begin
      (* Add assistant message with tool_use blocks *)
      messages := !messages @ [{role= Assistant; content= resp.content}] ;
      (* Execute each tool_use and collect results *)
      let tool_uses = extract_tool_uses resp.content in
      let results =
        List.map
          (fun (id, name, input) ->
            let result_str =
              try execute_tool name input with
              | exn -> Printf.sprintf "Error: %s" (Printexc.to_string exn)
            in
            Tool_result {tool_use_id= id; content= result_str; is_error= false} )
          tool_uses
      in
      messages := !messages @ [{role= User; content= results}]
    end
    else begin
      (* end_turn or other stop reason *)
      final_text := response_text resp ;
      finished := true
    end
  done ;

  if !finished
  then begin
    let cost =
      estimate_cost_usd
        ~model
        ~input_tokens:!total_input
        ~output_tokens:!total_output
    in
    let cost_info : Types.cost_info =
      {cost_usd= cost; input_tokens= !total_input; output_tokens= !total_output}
    in
    Ok (!final_text, Some cost_info)
  end
  else
    Error (Printf.sprintf "Agent exceeded max iterations (%d)" max_iterations)

(** Format a stream-json event for display.
    Returns (text_to_print, result_text, cost_info). *)
let format_stream_event (json : Yojson.Safe.t) :
    string option * string option * Types.cost_info option =
  let open Yojson.Safe.Util in
  let typ = json |> member "type" |> to_string_option in
  match typ with
  | Some "system" ->
      let session =
        json
        |> member "session_id"
        |> to_string_option
        |> Option.value ~default:"?"
      in
      let model =
        json |> member "model" |> to_string_option |> Option.value ~default:"?"
      in
      ( Some (Printf.sprintf "    session=%s model=%s\n" session model)
      , None
      , None )
  | Some "assistant" ->
      let msg = json |> member "message" in
      let content_list = msg |> member "content" |> to_list in
      let texts =
        List.filter_map
          (fun c ->
            let ct = c |> member "type" |> to_string_option in
            match ct with
            | Some "text" ->
                let text = c |> member "text" |> to_string in
                Some (Printf.sprintf "    %s\n" text)
            | Some "tool_use" ->
                let name =
                  c
                  |> member "name"
                  |> to_string_option
                  |> Option.value ~default:"?"
                in
                let hint =
                  match name with
                  | "Bash"
                   |"bash" -> (
                    try
                      let cmd =
                        c |> member "input" |> member "command" |> to_string
                      in
                      let first_line =
                        match String.index_opt cmd '\n' with
                        | Some i -> String.sub cmd 0 i
                        | None -> cmd
                      in
                      let max_len = 80 in
                      let truncated =
                        if String.length first_line > max_len
                        then String.sub first_line 0 max_len ^ "…"
                        else first_line
                      in
                      Printf.sprintf " → %s" truncated
                    with
                    | _ -> "" )
                  | "Glob"
                   |"glob" -> (
                    try
                      let pattern =
                        c |> member "input" |> member "pattern" |> to_string
                      in
                      Printf.sprintf " → %s" pattern
                    with
                    | _ -> "" )
                  | "Grep"
                   |"grep" -> (
                    try
                      let pattern =
                        c |> member "input" |> member "pattern" |> to_string
                      in
                      Printf.sprintf " → %s" pattern
                    with
                    | _ -> "" )
                  | "Read"
                   |"read" -> (
                    try
                      let path =
                        c |> member "input" |> member "file_path" |> to_string
                      in
                      Printf.sprintf " → %s" (Filename.basename path)
                    with
                    | _ -> "" )
                  | "Edit"
                   |"edit" -> (
                    try
                      let path =
                        c |> member "input" |> member "file_path" |> to_string
                      in
                      Printf.sprintf " → %s" (Filename.basename path)
                    with
                    | _ -> "" )
                  | "Write"
                   |"write" -> (
                    try
                      let path =
                        c |> member "input" |> member "file_path" |> to_string
                      in
                      Printf.sprintf " → %s" (Filename.basename path)
                    with
                    | _ -> "" )
                  | "Skill"
                   |"skill" -> (
                    try
                      let skill =
                        c |> member "input" |> member "skill" |> to_string
                      in
                      Printf.sprintf " → %s" skill
                    with
                    | _ -> "" )
                  | _ -> ""
                in
                Some (Printf.sprintf "    → tool: %s%s\n" name hint)
            | _ -> None )
          content_list
      in
      if texts <> []
      then (Some (String.concat "" texts), None, None)
      else (None, None, None)
  | Some "result" ->
      let result =
        json |> member "result" |> to_string_option |> Option.value ~default:""
      in
      let cost = json |> member "total_cost_usd" |> to_float_option in
      let duration = json |> member "duration_ms" |> to_int_option in
      let usage = json |> member "usage" in
      let input_tokens =
        match usage with
        | `Null -> 0
        | _ ->
            usage
            |> member "input_tokens"
            |> to_int_option
            |> Option.value ~default:0
      in
      let output_tokens =
        match usage with
        | `Null -> 0
        | _ ->
            usage
            |> member "output_tokens"
            |> to_int_option
            |> Option.value ~default:0
      in
      let cost_info : Types.cost_info option =
        match cost with
        | Some c -> Some {cost_usd= c; input_tokens; output_tokens}
        | None -> None
      in
      let summary =
        Printf.sprintf
          "    done (%s%s)\n"
          ( match duration with
          | Some d -> Printf.sprintf "%dms" d
          | None -> "" )
          ( match cost with
          | Some c -> Printf.sprintf ", $%.4f" c
          | None -> "" )
      in
      (Some summary, Some result, cost_info)
  | _ -> (None, None, None)

(** Run a task via CLI executor (e.g. claude -p) with stream-json output.
    The CLI manages its own agent loop and tools. *)
let run_cli
    ~(command : string)
    ~(model : string)
    ~(system : string)
    ~(prompt : string)
    ~(cwd : string)
    ~(quiet : bool) : (string * Types.cost_info option, string) result =
  let sys_file = Filename.temp_file "axiom-sys" ".txt" in
  let prompt_file = Filename.temp_file "axiom-prompt" ".txt" in
  let oc = Out_channel.open_text sys_file in
  Out_channel.output_string oc system ;
  Out_channel.close oc ;
  let oc = Out_channel.open_text prompt_file in
  Out_channel.output_string oc prompt ;
  Out_channel.close oc ;
  let cmd =
    Printf.sprintf
      "cd %s && unset CLAUDECODE && %s -p \"$(cat %s)\" --system-prompt \
       \"$(cat %s)\" --model %s --dangerously-skip-permissions --output-format \
       stream-json --verbose 2>&1"
      (Filename.quote cwd)
      command
      (Filename.quote prompt_file)
      (Filename.quote sys_file)
      (Filename.quote model)
  in
  let ic = Unix.open_process_in cmd in
  let result_text = ref "" in
  let cost_ref = ref None in
  let raw_output = Buffer.create 4096 in
  ( try
      while true do
        let line = input_line ic in
        Buffer.add_string raw_output line ;
        Buffer.add_char raw_output '\n' ;
        (* Try to parse as JSON and display *)
        try
          let json = Yojson.Safe.from_string line in
          let display, result, cost = format_stream_event json in
          ( if not quiet
            then
              match display with
              | Some s ->
                  print_string s ;
                  flush stdout
              | None -> () ) ;
          ( match result with
          | Some r -> result_text := r
          | None -> () ) ;
          match cost with
          | Some _ -> cost_ref := cost
          | None -> ()
        with
        | Yojson.Json_error _ ->
            (* Not JSON — raw output from claude *)
            if not quiet
            then begin
              Printf.printf "    %s\n%!" line
            end
      done
    with
  | End_of_file -> () ) ;
  let status = Unix.close_process_in ic in
  Sys.remove sys_file ;
  Sys.remove prompt_file ;
  match status with
  | Unix.WEXITED 0 ->
      if !result_text <> ""
      then Ok (!result_text, !cost_ref)
      else Ok (Buffer.contents raw_output, !cost_ref)
  | Unix.WEXITED code ->
      Error
        (Printf.sprintf
           "CLI exited with code %d:\n%s"
           code
           (Buffer.contents raw_output) )
  | Unix.WSIGNALED s -> Error (Printf.sprintf "CLI killed by signal %d" s)
  | Unix.WSTOPPED s -> Error (Printf.sprintf "CLI stopped by signal %d" s)

(** Dispatch a task to the right executor.
    Cli: shells out to command (e.g. claude -p), which runs its own agent loop.
    Http: uses our run_agent with the given provider. *)
let dispatch
    ~(executor : executor)
    ~(model : string)
    ~(system : string)
    ~(prompt : string)
    ~(cwd : string)
    ?(quiet = false)
    ?provider
    ?(tools = [])
    ?(execute_tool = fun _ _ -> "")
    ?(max_iterations = 25)
    () : (string * Types.cost_info option, string) result =
  match executor with
  | Cli command -> run_cli ~command ~model ~system ~prompt ~cwd ~quiet
  | Http -> (
    match provider with
    | None -> Error "Http executor requires a provider"
    | Some provider ->
        run_agent
          ~provider
          ~model
          ~system
          ~prompt
          ~tools
          ~execute_tool
          ~max_iterations )
