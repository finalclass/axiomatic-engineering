(** Anthropic API provider for ai_access *)

open Ai_access

let api_url = "https://api.anthropic.com/v1/messages"

(** Read API key from ANTHROPIC_API_KEY env var *)
let api_key () : string =
  match Sys.getenv_opt "ANTHROPIC_API_KEY" with
  | Some key -> key
  | None -> failwith "ANTHROPIC_API_KEY environment variable not set"

(** Build the request JSON body *)
let build_request ~model ~system ~messages ~tools ~max_tokens : Yojson.Safe.t =
  let msgs_json = List.map message_to_json messages in
  let tools_json = List.map tool_def_to_json tools in
  `Assoc ([
    ("model", `String model);
    ("max_tokens", `Int max_tokens);
    ("system", `String system);
    ("messages", `List msgs_json);
  ] @ (if tools <> [] then [("tools", `List tools_json)] else []))

(** HTTP POST using raw EIO sockets + TLS.
    send_request is injected from main to avoid coupling to EIO env. *)
let send_request_ref : (url:string -> headers:(string * string) list -> body:string -> (int * string)) ref =
  ref (fun ~url:_ ~headers:_ ~body:_ -> failwith "Anthropic.send_request_ref not wired")

(** Create an Anthropic provider. Wire send_request_ref before calling. *)
let provider () : provider =
  {
    name = "anthropic";
    send = (fun ~model ~system ~messages ~tools ~max_tokens ->
      let key = api_key () in
      let body = build_request ~model ~system ~messages ~tools ~max_tokens
        |> Yojson.Safe.to_string in
      let headers = [
        ("Content-Type", "application/json");
        ("x-api-key", key);
        ("anthropic-version", "2023-06-01");
      ] in
      let (status, resp_body) = !send_request_ref ~url:api_url ~headers ~body in
      if status >= 400 then
        failwith (Printf.sprintf "Anthropic API error %d: %s" status resp_body);
      let json = Yojson.Safe.from_string resp_body in
      response_of_json json
    );
  }
