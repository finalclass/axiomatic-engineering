(** AI Access — OpenRouter API *)

let net : Obj.t option ref = ref None

let set_net (n : 'a) : unit = net := Some (Obj.repr n)

open struct
[@@@warning "-32"]

let get_net () : _ Eio.Net.t =
  match !net with
  | Some n -> (Obj.obj n : _ Eio.Net.t)
  | None -> failwith "Ai_access.set_net was not called — call it from within Eio_main.run"

let send_openrouter ~api_key ~model ~system ~prompt ~tools ~execute_tool ~max_iterations =
  let net = get_net () in
  let build_messages () =
    let msg_to_json (role, content_blocks) =
      `Assoc
        [ ("role", `String role)
        ; ( "content"
          , `List
              (List.map
                 (function
                   | `Text s ->
                       `Assoc [ ("type", `String "text"); ("text", `String s) ]
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
                         @ if is_error then [ ("is_error", `Bool true) ]
                           else [] ) )
                 content_blocks)) ]
    in
    List.map msg_to_json
  in

  let tool_to_json (name, description, input_schema) =
    `Assoc
      [ ("name", `String name)
      ; ("description", `String description)
      ; ("input_schema", input_schema) ]
  in

  let parse_response json_str =
    let json = Yojson.Safe.from_string json_str in
    let open Yojson.Safe.Util in
    let content_list = json |> member "content" |> to_list in
    let parse_content c =
      match c |> member "type" |> to_string_option with
      | Some "text" ->
          Some (`Text (c |> member "text" |> to_string))
      | Some "tool_use" ->
          Some
            (`Tool_use
               ( c |> member "id" |> to_string
               , c |> member "name" |> to_string
               , c |> member "input" ))
      | _ -> None
    in
    let content = List.filter_map parse_content content_list in
    let stop_reason =
      json
      |> member "stop_reason"
      |> to_string_option
      |> Option.value ~default:"end_turn"
    in
    let usage = json |> member "usage" in
    let input_tokens =
      usage |> member "input_tokens" |> to_int_option |> Option.value ~default:0
    in
    let output_tokens =
      usage
      |> member "output_tokens"
      |> to_int_option
      |> Option.value ~default:0
    in
    (content, stop_reason, input_tokens, output_tokens)
  in

  let extract_text content =
    List.filter_map (function `Text s -> Some s | _ -> None) content
    |> String.concat "\n"
  in

  let extract_tool_uses content =
    List.filter_map
      (function `Tool_use (id, name, input) -> Some (id, name, input) | _ -> None)
      content
  in

  let estimate_cost model inp outp =
    let ipm, opm =
      match model with
      | m
        when String.length m >= 11 && String.sub m 0 11 = "claude-opus" ->
          (15.0, 75.0)
      | m
        when String.length m >= 13 && String.sub m 0 13 = "claude-sonnet" ->
          (3.0, 15.0)
      | m
        when String.length m >= 12 && String.sub m 0 12 = "claude-haiku" ->
          (0.25, 1.25)
      | _ -> (3.0, 15.0)
    in
    (float_of_int inp *. ipm /. 1_000_000.0)
    +. (float_of_int outp *. opm /. 1_000_000.0)
  in

  let rec loop messages iteration total_inp total_outp =
    if iteration >= max_iterations
    then
      Error
        (Printf.sprintf "Agent exceeded max iterations (%d)" max_iterations)
    else
      let body =
        `Assoc
          [ ("model", `String model)
          ; ("system", `String system)
          ; ("messages", `List (build_messages () messages))
          ; ("tools", `List (List.map tool_to_json tools))
          ; ("max_tokens", `Int 8192) ]
      in
      let body_str = Yojson.Safe.to_string body in
      let resp =
        Well.fetch_with_net ~net
          ~headers:
            [ ("Authorization", "Bearer " ^ api_key)
            ; ("Content-Type", "application/json") ]
          ~body:body_str
          "https://openrouter.ai/api/v1/chat/completions"
      in
      let content, stop_reason, inp, outp =
        parse_response resp.Well.body
      in
      let total_inp = total_inp + inp in
      let total_outp = total_outp + outp in
      match stop_reason with
      | "tool_use" ->
          let assistant_msg =
            ("assistant", content)
          in
          let messages_with_assistant = messages @ [ assistant_msg ] in
          let tool_uses = extract_tool_uses content in
          let results =
            List.map
              (fun (id, name, input) ->
                let result_str =
                  try execute_tool name input with
                  | exn ->
                      Printf.sprintf "Error: %s" (Printexc.to_string exn)
                in
                `Tool_result (id, result_str, false))
              tool_uses
          in
          let messages_with_results =
            messages_with_assistant @ [ ("user", results) ]
          in
          loop messages_with_results (iteration + 1) total_inp total_outp
      | _ ->
          let text = extract_text content in
          let cost = estimate_cost model total_inp total_outp in
          Ok
            ( text
            , Some
                { Types.cost_usd= cost
                ; input_tokens= total_inp
                ; output_tokens= total_outp } )
  in

  loop [ ("user", [ `Text prompt ]) ] 0 0 0

end

let prompt
    ~(system_prompt : string)
    ~(user_prompt : string)
    ~(model : string) : string =
  let api_key =
    match Sys.getenv_opt "OPENROUTER_API_KEY" with
    | Some k -> k
    | None -> failwith "OPENROUTER_API_KEY environment variable not set"
  in
  match
    send_openrouter
      ~api_key
      ~model
      ~system:system_prompt
      ~prompt:user_prompt
      ~tools:[]
      ~execute_tool:(fun _ _ -> "No tools available")
      ~max_iterations:1
  with
  | Ok (text, _) -> text
  | Error msg -> failwith msg
