(** AI Access — provider abstraction, executors, and agent loop *)

(** Executor: how to run a model. *)
type executor =
  | Cli of string   (** command name, e.g. "claude", "kilo" *)
  | Http            (** use HTTP provider + internal agent loop *)

type message_role = User | Assistant

type content =
  | Text of string
  | Tool_use of { id: string; name: string; input: Yojson.Safe.t }
  | Tool_result of { tool_use_id: string; content: string; is_error: bool }

type message = {
  role: message_role;
  content: content list;
}

type tool_def = {
  name: string;
  description: string;
  input_schema: Yojson.Safe.t;
}

type response = {
  content: content list;
  stop_reason: string; (** "end_turn" | "tool_use" *)
}

type model_alias = string (** e.g. "opus4.6", "sonnet4.6", "haiku4.5" *)

type provider = {
  name: string;
  send:
    model:string ->
    system:string ->
    messages:message list ->
    tools:tool_def list ->
    max_tokens:int ->
    response;
}

(** Known model aliases -> (provider_name, full_model_id) *)
let resolve_alias (alias : model_alias) : (string * string) option =
  match alias with
  | "opus4.6" -> Some ("anthropic", "claude-opus-4-6")
  | "sonnet4.6" -> Some ("anthropic", "claude-sonnet-4-6")
  | "haiku4.5" -> Some ("anthropic", "claude-haiku-4-5-20251001")
  | _ -> None

(** How to execute a given model alias. Hardcoded routing. *)
let executor_for_alias (alias : model_alias) : executor =
  match alias with
  | "opus4.6" | "sonnet4.6" | "haiku4.5" -> Cli "claude"
  (* Future: | "glm5" -> Cli "kilo" *)
  | _ -> Http

(** Encode message role to string *)
let role_to_string = function
  | User -> "user"
  | Assistant -> "assistant"

(** Encode content block to JSON *)
let content_to_json = function
  | Text s -> `Assoc [("type", `String "text"); ("text", `String s)]
  | Tool_use { id; name; input } ->
    `Assoc [
      ("type", `String "tool_use");
      ("id", `String id);
      ("name", `String name);
      ("input", input);
    ]
  | Tool_result { tool_use_id; content; is_error } ->
    `Assoc ([
      ("type", `String "tool_result");
      ("tool_use_id", `String tool_use_id);
      ("content", `String content);
    ] @ (if is_error then [("is_error", `Bool true)] else []))

(** Encode message to JSON *)
let message_to_json (msg : message) : Yojson.Safe.t =
  `Assoc [
    ("role", `String (role_to_string msg.role));
    ("content", `List (List.map content_to_json msg.content));
  ]

(** Encode tool_def to JSON *)
let tool_def_to_json (td : tool_def) : Yojson.Safe.t =
  `Assoc [
    ("name", `String td.name);
    ("description", `String td.description);
    ("input_schema", td.input_schema);
  ]

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
    Some (Tool_use { id; name; input })
  | _ -> None

(** Parse response from JSON *)
let response_of_json (json : Yojson.Safe.t) : response =
  let open Yojson.Safe.Util in
  let content_list = json |> member "content" |> to_list in
  let content = List.filter_map content_of_json content_list in
  let stop_reason = json |> member "stop_reason" |> to_string_option
    |> Option.value ~default:"end_turn" in
  { content; stop_reason }

(** Extract all text content from a response *)
let response_text (resp : response) : string =
  resp.content
  |> List.filter_map (fun c -> match c with Text s -> Some s | _ -> None)
  |> String.concat "\n"

(** Extract tool_use blocks from response content *)
let extract_tool_uses (content : content list) : (string * string * Yojson.Safe.t) list =
  List.filter_map (fun c ->
    match c with
    | Tool_use { id; name; input } -> Some (id, name, input)
    | _ -> None
  ) content

(** Run an agent loop: send prompt, execute tool calls, repeat until end_turn *)
let run_agent
    ~(provider : provider)
    ~(model : string)
    ~(system : string)
    ~(prompt : string)
    ~(tools : tool_def list)
    ~(execute_tool : string -> Yojson.Safe.t -> string)
    ~(max_iterations : int)
  : (string, string) result =
  let messages = ref [{ role = User; content = [Text prompt] }] in
  let iteration = ref 0 in
  let finished = ref false in
  let final_text = ref "" in

  while not !finished && !iteration < max_iterations do
    incr iteration;
    let resp = provider.send
      ~model ~system ~messages:!messages ~tools ~max_tokens:8192 in

    if resp.stop_reason = "tool_use" then begin
      (* Add assistant message with tool_use blocks *)
      messages := !messages @ [{ role = Assistant; content = resp.content }];
      (* Execute each tool_use and collect results *)
      let tool_uses = extract_tool_uses resp.content in
      let results = List.map (fun (id, name, input) ->
        let result_str =
          try execute_tool name input
          with exn -> Printf.sprintf "Error: %s" (Printexc.to_string exn)
        in
        Tool_result { tool_use_id = id; content = result_str; is_error = false }
      ) tool_uses in
      messages := !messages @ [{ role = User; content = results }]
    end else begin
      (* end_turn or other stop reason *)
      final_text := response_text resp;
      finished := true
    end
  done;

  if !finished then Ok !final_text
  else Error (Printf.sprintf "Agent exceeded max iterations (%d)" max_iterations)

(** Format a stream-json event for display.
    Returns (text_to_print, is_result, result_text). *)
let format_stream_event (json : Yojson.Safe.t) : string option * string option =
  let open Yojson.Safe.Util in
  let typ = json |> member "type" |> to_string_option in
  match typ with
  | Some "system" ->
    let session = json |> member "session_id" |> to_string_option |> Option.value ~default:"?" in
    let model = json |> member "model" |> to_string_option |> Option.value ~default:"?" in
    (Some (Printf.sprintf "    session=%s model=%s\n" session model), None)
  | Some "assistant" ->
    let msg = json |> member "message" in
    let content_list = msg |> member "content" |> to_list in
    let texts = List.filter_map (fun c ->
      let ct = c |> member "type" |> to_string_option in
      match ct with
      | Some "text" ->
        let text = c |> member "text" |> to_string in
        Some (Printf.sprintf "    %s\n" text)
      | Some "tool_use" ->
        let name = c |> member "name" |> to_string_option |> Option.value ~default:"?" in
        Some (Printf.sprintf "    → tool: %s\n" name)
      | _ -> None
    ) content_list in
    if texts <> [] then (Some (String.concat "" texts), None)
    else (None, None)
  | Some "result" ->
    let result = json |> member "result" |> to_string_option |> Option.value ~default:"" in
    let cost = json |> member "total_cost_usd" |> to_float_option in
    let duration = json |> member "duration_ms" |> to_int_option in
    let summary = Printf.sprintf "    done (%s%s)\n"
      (match duration with Some d -> Printf.sprintf "%dms" d | None -> "")
      (match cost with Some c -> Printf.sprintf ", $%.4f" c | None -> "") in
    (Some summary, Some result)
  | _ -> (None, None)

(** Run a task via CLI executor (e.g. claude -p) with stream-json output.
    The CLI manages its own agent loop and tools. *)
let run_cli
    ~(command : string)
    ~(model : string)
    ~(system : string)
    ~(prompt : string)
    ~(cwd : string)
    ~(quiet : bool)
  : (string, string) result =
  let sys_file = Filename.temp_file "axiom-sys" ".txt" in
  let prompt_file = Filename.temp_file "axiom-prompt" ".txt" in
  let oc = Out_channel.open_text sys_file in
  Out_channel.output_string oc system;
  Out_channel.close oc;
  let oc = Out_channel.open_text prompt_file in
  Out_channel.output_string oc prompt;
  Out_channel.close oc;
  let cmd = Printf.sprintf "cd %s && unset CLAUDECODE && %s -p \"$(cat %s)\" --system-prompt \"$(cat %s)\" --model %s --output-format stream-json --verbose 2>&1"
    (Filename.quote cwd) command (Filename.quote prompt_file) (Filename.quote sys_file) (Filename.quote model) in
  let ic = Unix.open_process_in cmd in
  let result_text = ref "" in
  let raw_output = Buffer.create 4096 in
  (try while true do
    let line = input_line ic in
    Buffer.add_string raw_output line;
    Buffer.add_char raw_output '\n';
    (* Try to parse as JSON and display *)
    (try
      let json = Yojson.Safe.from_string line in
      let (display, result) = format_stream_event json in
      if not quiet then
        (match display with Some s -> print_string s; flush stdout | None -> ());
      (match result with Some r -> result_text := r | None -> ())
    with Yojson.Json_error _ ->
      (* Not JSON — raw output from claude *)
      if not quiet then begin
        Printf.printf "    %s\n%!" line
      end)
  done with End_of_file -> ());
  let status = Unix.close_process_in ic in
  Sys.remove sys_file;
  Sys.remove prompt_file;
  match status with
  | Unix.WEXITED 0 ->
    if !result_text <> "" then Ok !result_text
    else Ok (Buffer.contents raw_output)
  | Unix.WEXITED code -> Error (Printf.sprintf "CLI exited with code %d:\n%s" code (Buffer.contents raw_output))
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
    ()
  : (string, string) result =
  match executor with
  | Cli command ->
    run_cli ~command ~model ~system ~prompt ~cwd ~quiet
  | Http ->
    match provider with
    | None -> Error "Http executor requires a provider"
    | Some provider ->
      run_agent ~provider ~model ~system ~prompt ~tools ~execute_tool ~max_iterations
