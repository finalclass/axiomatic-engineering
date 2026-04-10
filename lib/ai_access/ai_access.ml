(** AI Access — OpenRouter API with SSE streaming *)

let net : Obj.t option ref = ref None

let set_net (n : 'a) : unit = net := Some (Obj.repr n)

type toolset =
  | No_tools
  | All_tools

type content_block =
  [ `Text of string
  | `Tool_use of string * string * Yojson.Safe.t
  | `Tool_result of string * string * bool ]

type message = string * content_block list

let sessions : (string, message list) Hashtbl.t = Hashtbl.create 16

open struct
  [@@@warning "-32"]

  let use_color () =
    Sys.getenv_opt "NO_COLOR" = None
    &&
    match Sys.getenv_opt "TERM" with
    | Some "dumb" -> false
    | Some _ -> true
    | None -> false

  let ansi code text =
    if use_color () then Printf.sprintf "\027[%sm%s\027[0m" code text else text

  let blue text = ansi "34" text
  let cyan text = ansi "36" text
  let yellow text = ansi "33" text
  let green text = ansi "32" text
  let red text = ansi "31" text
  let magenta text = ansi "35" text
  let dim text = ansi "2" text

let get_net () : _ Eio.Net.t =
    match !net with
    | Some n -> (Obj.obj n : _ Eio.Net.t)
    | None -> failwith "Ai_access.set_net was not called"

let format_tool_use_hint name input =
    match name with
    | "bash" -> (
      try
        let cmd = Yojson.Safe.Util.(input |> member "command" |> to_string) in
        let first_line =
          match String.index_opt cmd '\n' with
          | Some i -> String.sub cmd 0 i
          | None -> cmd
        in
        let max_len = 70 in
        if String.length first_line > max_len
        then String.sub first_line 0 max_len ^ "…"
        else first_line
      with
      | _ -> "" )
    | "read_file" -> (
      try
        Yojson.Safe.Util.(input |> member "path" |> to_string)
        |> Filename.basename
      with
      | _ -> "" )
    | "write_file"
     |"edit_file" -> (
      try
        Yojson.Safe.Util.(input |> member "path" |> to_string)
        |> Filename.basename
      with
      | _ -> "" )
    | "glob_search" -> (
      try Yojson.Safe.Util.(input |> member "pattern" |> to_string) with
      | _ -> "" )
    | "grep_search" -> (
      try Yojson.Safe.Util.(input |> member "pattern" |> to_string) with
      | _ -> "" )
  | "TodoWrite" -> "(updating todos)"
  | _ -> ""

let summarize_tool_result name result =
  let trimmed = String.trim result in
  match name with
  | "read_file" ->
      let lines =
        if trimmed = "" then 0 else List.length (String.split_on_char '\n' trimmed)
      in
      Printf.sprintf "(read %d chars, %d lines)" (String.length trimmed) lines
  | "glob_search" ->
      let count =
        if trimmed = "" then 0 else List.length (String.split_on_char '\n' trimmed)
      in
      Printf.sprintf "(found %d paths)" count
  | "grep_search" ->
      let count =
        if trimmed = "" then 0 else List.length (String.split_on_char '\n' trimmed)
      in
      Printf.sprintf "(found %d matches)" count
  | "TodoWrite" -> trimmed
  | _ ->
      if String.length trimmed > 240 then String.sub trimmed 0 240 ^ "..." else trimmed

let colorize_tool_result name result =
  if String.starts_with ~prefix:"Error:" result
  then red result
  else
    match name with
    | "TodoWrite" -> yellow result
    | "write_file" | "edit_file" -> green result
    | "read_file" | "glob_search" | "grep_search" | "bash" -> dim result
    | _ -> result

  let build_messages () =
    let msg_to_json (role, content_blocks) =
      `Assoc
        [ ("role", `String role)
        ; ( "content"
          , `List
              (List.map
                 (function
                   | `Text s ->
                       `Assoc [("type", `String "text"); ("text", `String s)]
                   | `Tool_use (id, name, input) ->
                       `Assoc
                         [ ("type", `String "tool_use")
                         ; ("id", `String id)
                         ; ("name", `String name)
                         ; ("input", input) ]
                   | `Tool_result (tool_use_id, content, is_error) ->
                       `Assoc
                         ( [ ("type", `String "tool_result")
                           ; ("tool_use_id", `String tool_use_id)
                           ; ("content", `String content) ]
                         @ if is_error then [("is_error", `Bool true)] else []
                         ) )
                 content_blocks ) ) ]
    in
    List.map msg_to_json

  let tool_to_json (name, description, input_schema) =
    `Assoc
      [ ("type", `String "function")
      ; ( "function"
        , `Assoc
            [ ("name", `String name)
            ; ("description", `String description)
            ; ("parameters", input_schema) ] ) ]

  let estimate_cost model inp outp =
    let ipm, opm =
      match model with
      | m when String.length m >= 11 && String.sub m 0 11 = "claude-opus" ->
          (15.0, 75.0)
      | m when String.length m >= 13 && String.sub m 0 13 = "claude-sonnet" ->
          (3.0, 15.0)
      | m when String.length m >= 12 && String.sub m 0 12 = "claude-haiku" ->
          (0.25, 1.25)
      | _ -> (3.0, 15.0)
    in
    (float_of_int inp *. ipm /. 1_000_000.0)
    +. (float_of_int outp *. opm /. 1_000_000.0)

  let print_thinking_banner () =
    Printf.printf "%s\n%!" (magenta "[thinking]")

  (** Parse complete SSE events from a running buffer.
    Returns (complete event payloads, unconsumed tail). *)
  let extract_sse_events buffer =
    let len = String.length buffer in
    let is_event_sep i =
      (i + 1 < len && buffer.[i] = '\n' && buffer.[i + 1] = '\n')
      || i + 3 < len
         && buffer.[i] = '\r'
         && buffer.[i + 1] = '\n'
         && buffer.[i + 2] = '\r'
         && buffer.[i + 3] = '\n'
    in
    let rec split_events start i acc =
      if i >= len
      then (List.rev acc, String.sub buffer start (len - start))
      else if is_event_sep i
      then
        let event = String.sub buffer start (i - start) in
        let next = if buffer.[i] = '\n' then i + 2 else i + 4 in
        split_events next next (event :: acc)
      else split_events start (i + 1) acc
    in
    let raw_events, tail = split_events 0 0 [] in
    let parse_event event =
      let data_lines = ref [] in
      event
      |> String.split_on_char '\n'
      |> List.iter (fun line ->
          let line =
            if String.length line > 0 && line.[String.length line - 1] = '\r'
            then String.sub line 0 (String.length line - 1)
            else line
          in
          if String.starts_with ~prefix:"data:" line
          then
            let payload =
              if String.length line >= 6 && line.[5] = ' '
              then String.sub line 6 (String.length line - 6)
              else String.sub line 5 (String.length line - 5)
            in
            data_lines := payload :: !data_lines ) ;
      if !data_lines = []
      then None
      else Some (String.concat "\n" (List.rev !data_lines))
    in
    (List.filter_map parse_event raw_events, tail)

  (** Parse a single SSE event JSON.
    Returns
    (text_deltas, reasoning_deltas, tool_uses, is_done, finish_reason, error). *)
  let rec text_fragments_of_json = function
    | `String s -> [s]
    | `List items -> List.concat_map text_fragments_of_json items
    | `Assoc fields -> (
      match List.assoc_opt "text" fields with
      | Some json -> text_fragments_of_json json
      | None -> [] )
    | _ -> []

  let error_message_of_json json =
    let open Yojson.Safe.Util in
    match json |> member "error" with
    | `Null -> None
    | `String s -> Some s
    | `Assoc _ as err -> (
      match err |> member "message" |> to_string_option with
      | Some msg -> Some msg
      | None -> Some (Yojson.Safe.to_string err) )
    | other -> Some (Yojson.Safe.to_string other)

  let parse_sse_event data =
    if data = "[DONE]"
    then ([], [], [], true, Some "[DONE]", None)
    else
      try
        let json = Yojson.Safe.from_string data in
        let open Yojson.Safe.Util in
        let error = error_message_of_json json in
        (* OpenRouter SSE format: choices[0].delta.content / tool_calls *)
        let delta =
          match json |> member "choices" |> to_list with
          | c :: _ -> c |> member "delta"
          | [] -> `Null
        in
        let text =
          delta
          |> member "content"
          |> text_fragments_of_json
          |> String.concat ""
        in
        let reasoning =
          delta
          |> member "reasoning"
          |> text_fragments_of_json
          |> String.concat ""
        in
        let tool_uses =
          match delta |> member "tool_calls" with
          | `List tl ->
              List.map
                (fun t ->
                  let id = t |> member "index" |> to_int in
                  let func = t |> member "function" in
                  let name =
                    match func |> member "name" |> to_string_option with
                    | Some s when s <> "" -> s
                    | _ -> ""
                  in
                  let args_str =
                    match func |> member "arguments" with
                    | `String s -> s
                    | `Null -> ""
                    | json -> Yojson.Safe.to_string json
                  in
                  (id, name, args_str) )
                tl
          | _ -> []
        in
        let finish_reason =
          match json |> member "choices" |> to_list with
          | c :: _ -> c |> member "finish_reason" |> to_string_option
          | [] -> None
        in
        ( (if text = "" then [] else [text])
        , (if reasoning = "" then [] else [reasoning])
        , tool_uses
        , ( match finish_reason with
          | Some "stop"
           |Some "tool_calls"
           |Some "error"
           |Some "length" ->
              true
          | _ -> false )
        , finish_reason
        , error )
      with
      | _ -> ([], [], [], false, None, None)

  let send_openrouter
      ~api_key
      ~model
      ~system
      ~(messages : message list)
      ~stream_output
      ~reasoning_effort
      ~max_tokens
      ~tools
      ~execute_tool
      ~max_iterations =
    let rec loop messages iteration total_inp total_outp =
      if iteration >= max_iterations
      then
        Error
          (Printf.sprintf "Agent exceeded max iterations (%d)" max_iterations)
      else
        let body =
          `Assoc
            ( [ ("model", `String model)
              ; ("system", `String system)
              ; ("messages", `List (build_messages () messages))
              ; ("tools", `List (List.map tool_to_json tools))
              ; ("max_tokens", `Int max_tokens)
              ; ("stream", `Bool true) ]
            @
            match reasoning_effort with
            | None -> []
            | Some effort -> [("reasoning", `Assoc [("effort", `String effort)])]
            )
        in
        let body_str = Yojson.Safe.to_string body in

        let accumulated_text = Buffer.create 1024 in
        let raw_response = Buffer.create 1024 in
        let pending_sse = ref "" in
        let tool_use_map = Hashtbl.create 10 in
        let stream_done = ref false in
        let final_usage = ref (0, 0) in
        let reasoning_started = ref false in
        let reasoning_line_start = ref true in
        let thinking_banner_shown = ref false in
        let parsed_event_count = ref 0 in
        let saw_done_marker = ref false in
        let saw_reasoning = ref false in
        let saw_finish_reason = ref None in
        let saw_parse_failure = ref false in

        let ensure_thinking_banner () =
          if not !thinking_banner_shown
          then (
            if stream_output then print_thinking_banner () ;
            thinking_banner_shown := true )
        in

        let print_reasoning text =
          String.iter
            (fun c ->
              if !reasoning_line_start
              then (
                print_string "│ " ;
                reasoning_line_start := false ) ;
              print_char c ;
              if c = '\n' then reasoning_line_start := true )
            text
        in

        let on_data chunk =
          Buffer.add_string raw_response chunk ;
          pending_sse := !pending_sse ^ chunk ;
          let events, tail = extract_sse_events !pending_sse in
          pending_sse := tail ;
          List.iter
            (fun data ->
              if !stream_done
              then ()
              else
                let ( text_deltas
                    , reasoning_deltas
                    , tool_calls
                    , is_done
                    , finish_reason
                    , error ) =
                  parse_sse_event data
                in
                if data = "[DONE]" then saw_done_marker := true ;
                if
                  text_deltas = []
                  && reasoning_deltas = []
                  && tool_calls = []
                  && error = None
                  && data <> "[DONE]"
                then saw_parse_failure := true
                else parsed_event_count := !parsed_event_count + 1 ;
                Option.iter
                  (fun message ->
                    failwith
                      (Printf.sprintf
                         "OpenRouter streaming error for model `%s`: %s"
                         model
                         message ) )
                  error ;
                Option.iter
                  (fun reason -> saw_finish_reason := Some reason)
                  finish_reason ;
                if is_done then stream_done := true ;
                List.iter
                  (fun r ->
                    if r <> ""
                    then (
	                      saw_reasoning := true ;
	                      if not !reasoning_started
	                      then (
	                        ensure_thinking_banner () ;
	                        reasoning_line_start := true ;
	                        reasoning_started := true ) ;
	                      if stream_output
	                      then (
	                        print_reasoning r ;
	                        flush stdout ) ) )
	                  reasoning_deltas ;
	                (* Accumulate text *)
	                List.iter
	                  (fun t ->
	                    if t <> ""
	                    then (
	                      if !reasoning_started
	                      then (
	                        if stream_output then print_newline () ;
	                        reasoning_started := false ) ;
	                      Buffer.add_string accumulated_text t ;
	                      if stream_output
	                      then (
	                        print_string t ;
	                        flush stdout ) ) )
	                  text_deltas ;
                (* Accumulate tool_calls (streamed incrementally) *)
                List.iter
                  (fun (idx, name, args_str) ->
                    let existing_name, existing_args =
                      if Hashtbl.mem tool_use_map idx
                      then Hashtbl.find tool_use_map idx
                      else ("", "")
                    in
                    let merged_name =
                      if name <> "" then name else existing_name
                    in
                    let merged_args = existing_args ^ args_str in
                    Hashtbl.replace tool_use_map idx (merged_name, merged_args) )
                  tool_calls ;
                (* Try to extract usage from event *)
                try
                  let json = Yojson.Safe.from_string data in
                  let open Yojson.Safe.Util in
                  let usage = json |> member "usage" in
                  let inp =
                    usage
                    |> member "input_tokens"
                    |> to_int_option
                    |> Option.value ~default:0
                  in
                  let outp =
                    usage
                    |> member "output_tokens"
                    |> to_int_option
                    |> Option.value ~default:0
                  in
                  if inp > 0 || outp > 0 then final_usage := (inp, outp)
                with
                | _ -> () )
            events
        in

        ensure_thinking_banner () ;
	        let status, _headers =
          Well.fetch_stream_with_net
            ~net:(get_net ())
            ~headers:
              [ ("Authorization", "Bearer " ^ api_key)
              ; ("Content-Type", "application/json") ]
            ~body:body_str
            ~on_data
	            "https://openrouter.ai/api/v1/chat/completions"
	        in
	        if stream_output
	        then (
	          print_newline () ;
	          flush stdout ) ;

        if status <> 200
        then
          let body = Buffer.contents raw_response |> String.trim in
          let body =
            if String.length body > 800
            then String.sub body 0 800 ^ "..."
            else body
          in
          Error
            (Printf.sprintf
               "OpenRouter returned HTTP %d for model `%s`.%s"
               status
               model
               (if body = "" then "" else " Response: " ^ body) )
        else
          let remaining = String.trim !pending_sse in
          let raw_response = Buffer.contents raw_response |> String.trim in
          let text_content = Buffer.contents accumulated_text in

          (* Collect tool uses from the map *)
          let tool_uses =
            Hashtbl.fold
              (fun idx (name, args_str) acc ->
                let input =
                  try Yojson.Safe.from_string args_str with
                  | _ ->
                      let trimmed = String.trim args_str in
                      if trimmed = "" then `Assoc [] else `String trimmed
                in
                (string_of_int idx, name, input) :: acc )
              tool_use_map
              []
          in

          if text_content = "" && tool_uses = [] && remaining <> ""
          then
            let shortened_remaining =
              if String.length remaining > 800
              then String.sub remaining 0 800 ^ "..."
              else remaining
            in
            try
              let json = Yojson.Safe.from_string remaining in
              match error_message_of_json json with
              | Some message ->
                  Error
                    (Printf.sprintf
                       "OpenRouter returned an unparsed error for model `%s`: \
                        %s"
                       model
                       message )
              | None ->
                  Error
                    (Printf.sprintf
                       "OpenRouter returned an unparsed response for model \
                        `%s`: %s"
                       model
                       shortened_remaining )
            with
            | _ ->
                Error
                  (Printf.sprintf
                     "OpenRouter returned an unparsed response for model `%s`: \
                      %s"
                     model
                     shortened_remaining )
          else if text_content = "" && tool_uses = []
          then
            let stream_summary =
              [ ("parsed_events", string_of_int !parsed_event_count)
              ; ("saw_done", string_of_bool !saw_done_marker)
              ; ("saw_reasoning", string_of_bool !saw_reasoning)
              ; ( "finish_reason"
                , Option.value !saw_finish_reason ~default:"<none>" )
              ; ("parse_failure", string_of_bool !saw_parse_failure) ]
              |> List.map (fun (k, v) -> Printf.sprintf "%s=%s" k v)
              |> String.concat ", "
            in
            let raw_hint =
              if raw_response = ""
              then ""
              else
                let shortened =
                  if String.length raw_response > 300
                  then String.sub raw_response 0 300 ^ "..."
                  else raw_response
                in
                " Raw stream prefix: " ^ shortened
            in
            if !saw_reasoning
            then
              Error
                (Printf.sprintf
                   "OpenRouter stream for model `%s` ended after reasoning \
                    without final answer text (%s).%s"
                   model
                   stream_summary
                   raw_hint )
            else
              Error
                (Printf.sprintf
                   "OpenRouter stream for model `%s` ended without answer text \
                    or tool calls (%s).%s"
                   model
                   stream_summary
                   raw_hint )
          else
            let inp, outp = !final_usage in
            let total_inp = total_inp + inp in
            let total_outp = total_outp + outp in

            if !saw_finish_reason = Some "length"
            then
              let stream_summary =
                [ ("parsed_events", string_of_int !parsed_event_count)
                ; ("saw_done", string_of_bool !saw_done_marker)
                ; ("saw_reasoning", string_of_bool !saw_reasoning)
                ; ("finish_reason", "length")
                ; ("output_chars", string_of_int (String.length text_content))
                ]
                |> List.map (fun (k, v) -> Printf.sprintf "%s=%s" k v)
                |> String.concat ", "
              in
              let excerpt =
                let trimmed = String.trim text_content in
                if trimmed = ""
                then ""
                else if String.length trimmed > 240
                then String.sub trimmed 0 240 ^ "..."
                else trimmed
              in
              Error
                (Printf.sprintf
                   "OpenRouter response for model `%s` was truncated because \
                    it hit the max token limit (%s).%s"
                   model
                   stream_summary
                   (if excerpt = "" then "" else " Partial response: " ^ excerpt) )
            else if tool_uses <> []
            then begin
	              (* Print tool call info *)
	              List.iter
	                  (fun (_id, name, input) ->
	                    let hint = format_tool_use_hint name input in
	                    if hint <> ""
	                  then if stream_output
	                  then
	                    Printf.printf
	                      "    %s %s %s\n%!"
	                      (blue "→")
	                      (cyan name)
	                      (dim hint)
	                  else if stream_output
	                  then Printf.printf "    %s %s\n%!" (blue "→") (cyan name) )
	                tool_uses ;

              let assistant_content =
                if text_content <> ""
                then
                  `Text text_content
                  :: List.map
                       (fun (id, name, input) -> `Tool_use (id, name, input))
                       tool_uses
                else
                  List.map
                    (fun (id, name, input) -> `Tool_use (id, name, input))
                    tool_uses
              in
              let messages_with_assistant =
                messages @ [("assistant", assistant_content)]
              in
              let results =
                List.map
                  (fun (id, name, input) ->
                    let result_str =
	                      try execute_tool name input with
	                      | exn ->
	                          Printf.sprintf "Error: %s" (Printexc.to_string exn)
	                    in
	                    if stream_output
	                    then
	                      Printf.printf
	                        "    %s %s\n%!"
	                        (green "←")
	                        (colorize_tool_result
	                           name
	                           (summarize_tool_result name result_str) ) ;
	                    (id, name, result_str) )
	                  tool_uses
              in
              let tool_results_text =
                results
                |> List.map (fun (_id, name, result_str) ->
                       Printf.sprintf
                         "Tool `%s` returned:\n%s"
                         name
                         result_str )
                |> String.concat "\n\n"
              in
              let messages_with_results =
                messages_with_assistant
                @
                [ ( "user"
                  , [ `Text
                        ("Continue the task using these tool results:\n\n"
                       ^ tool_results_text) ] ) ]
              in
              loop messages_with_results (iteration + 1) total_inp total_outp
            end
            else
              let cost = estimate_cost model total_inp total_outp in
              let final_messages =
                if text_content <> ""
                then messages @ [("assistant", [`Text text_content])]
                else messages
              in
              Ok
                ( text_content
                , final_messages
                , Some
                    { Types.cost_usd= cost
                    ; input_tokens= total_inp
                    ; output_tokens= total_outp } )
    in

    loop messages 0 0 0
end

let prompt
    ~(system_prompt : string)
    ~(user_prompt : string)
    ~(model : string)
    ?api_key
    ?session_id
    ?(stream_output : bool = true)
    ?(toolset : toolset = All_tools)
    ?(tool_base_dir : string = Sys.getcwd ())
    ?tools
    ?execute_tool
    ?reasoning_effort
    ?(max_tokens : int = 8192)
    ?(max_iterations : int = 25)
    () : Types.ai_response =
  let tools, execute_tool =
    match (tools, execute_tool) with
    | Some tools, Some execute_tool -> (tools, execute_tool)
    | Some tools, None -> (tools, fun _ _ -> "")
    | None, Some execute_tool -> ([], execute_tool)
    | None, None -> (
      match toolset with
      | No_tools -> ([], fun _ _ -> "")
      | All_tools ->
          ( Tools.to_ai_tools Tools.all_tool_defs
          , Tools.execute ~base_dir:tool_base_dir ) )
  in
  let messages =
    match session_id with
    | None -> [("user", [`Text user_prompt])]
    | Some session_id ->
        let previous_messages =
          match Hashtbl.find_opt sessions session_id with
          | Some messages -> messages
          | None -> []
        in
        previous_messages @ [("user", [`Text user_prompt])]
  in
  let api_key =
    match api_key with
    | Some k -> k
    | None -> (
      match Sys.getenv_opt "OPENROUTER_API_KEY" with
      | Some k -> k
      | None ->
          failwith
            "OpenRouter API key not set. Configure `api_key` in \
             ~/.config/axioms-sync.toml or set AS_API_KEY / OPENROUTER_API_KEY"
      )
  in
  match
    send_openrouter
      ~api_key
      ~model
      ~system:system_prompt
      ~messages
      ~stream_output
      ~reasoning_effort
      ~max_tokens
      ~tools
      ~execute_tool
      ~max_iterations
  with
  | Ok (text, final_messages, cost_info) ->
      Option.iter
        (fun session_id -> Hashtbl.replace sessions session_id final_messages)
        session_id ;
      { Types.result= text
      ; cost=
          ( match cost_info with
          | Some cost_info -> cost_info.cost_usd
          | None -> 0.0 ) }
  | Error msg -> failwith msg
