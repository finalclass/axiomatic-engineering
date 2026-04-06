(** Transform — CLI args and env vars to TOML representations *)

let cli_key_to_toml (key : string) : string =
  let key =
    if String.length key >= 2 && key.[0] = '-' && key.[1] = '-'
    then String.sub key 2 (String.length key - 2)
    else key
  in
  String.map (fun c -> if c = '-' then '_' else c) key

let env_key_to_toml (key : string) : string =
  let key =
    if String.length key >= 3 && String.sub key 0 3 = "AS_"
    then String.sub key 3 (String.length key - 3)
    else key
  in
  let key = String.map (fun c -> if c = '_' then '-' else c) key in
  String.map (fun c -> if c = '-' then '_' else c) key

let parse_value (s : string) =
  if s = "true"
  then `Bool true
  else if s = "false"
  then `Bool false
  else
    try `Int (int_of_string s) with
    | Failure _ -> (
      try `Float (float_of_string s) with
      | Failure _ -> `String s )
