open Websocket_lwt
open Lwt
open Conduit_lwt_unix

type msg = Initial | Update | Join of string | Turn of Util.direction | End | Confirm of bool | Unknown

type rules = {
  trail_length: int;
  ticks_per_second: float;
  food_probability: float;
  time_between_games: float;
  game_over_handler: int -> int -> bool;
}

type t = {
  rules: rules;
  mutable grid: Grid.t;
  mutable callbacks: (int * (Frame.t -> unit Lwt.t)) list;
  host: string;
  port: int;
  mutable started: bool;
}

let create a p g r =
  {
    rules = r;
    host = a;
    port = p;
    grid = g;
    callbacks = [];
    started = false;
  }

let create_from_json a p j r =
  {
    rules = r;
    host = a;
    port = p;
    grid = Grid.from_json_file j;
    callbacks = [];
    started = false;
  }

(* TCP port this game is running on *)
let port s =
  s.port

(* Web address to access this game *)
let host s =
  s.host

let grid s =
  s.grid

let rules s =
  s.rules

let add_handler s id handler =
  s.callbacks <- (id, handler)::s.callbacks

let pong s id =
  let handler = List.assoc id s.callbacks in
  handler (Frame.create ~opcode:Frame.Opcode.Pong ())

let send s id content =
  try
    let handler = List.assoc id s.callbacks in
    handler (Frame.create ~opcode:Frame.Opcode.Text ~content ())
  with
  | _ -> return ()


(* Turns json into msg *)
let parse msg =
  let open Yojson.Basic.Util in
  try
    (match msg with
    | `Assoc _ -> (
      let t = msg |> member "type" in
      match t with
      | `String "turn" -> Turn (Util.direction_of_string (msg |> member "direction" |> to_string))
      | `String "join" -> Join (msg |> member "player_name" |> to_string)
      | _ -> Unknown
      )
    | _ -> Unknown)
  with
  | _ -> Unknown

(* Serializes and sends a msg tuple to the client with id *)
let message s id msg =
  let json = match msg with
  | Initial
  | Update ->
    (
      let (f, t) = if msg = Initial then
        (Grid.to_json_initial, "initial")
      else
        (Grid.to_json_update, "update")
      in

      (match f s.grid with
      | `Assoc x -> `Assoc (("type", `String t)::x)
      | x -> x)
      )
  | End -> `Assoc [("type", `String "end")]
  | Confirm a -> `Assoc [("type", `String "confirm"); ("accepted", `Bool a); ("id", `Int id)]
  | _ -> failwith "Invalid Message to send"
  in
  Yojson.Basic.to_string json

let rec tick s () =
  Lwt_unix.sleep (1. /. (rules s).ticks_per_second) >>= fun () ->

  let rls = rules s in
  let g = grid s in

  (* Move AI players *)
  List.iter (fun p -> if (Player.is_ai p) then Ai.new_direction p s.grid) (Grid.players s.grid);

  (* Move all players in their direction *)
  Grid.act g;

  (* Spawn food based on a random number *)
  (if Random.float 1. <= rls.food_probability then
    Grid.spawn_food g
  );

  (* Evaluate dead people *)
  let (hum, ai) = List.fold_left
    (fun (hum, ai) p ->
      if (Player.is_human p) && (Player.is_alive p) then
        (hum + 1, ai)
      else if (Player.is_ai p) && (Player.is_alive p) then
        (hum, ai + 1)
      else
        (hum, ai)
      )
    (0,0) (Grid.players s.grid) in

  if (rules s).game_over_handler hum ai then
    let () = send_all_players s End in
    s.grid <- Grid.reset s.grid;
    s.started <- false;

    return () >>= (start_ticking s)

  else
    (* Send players new board *)
    let () = send_all_players s Update in
    (* Tick again *)
    return () >>= (tick s)

and start_ticking s () =
  List.iter Player.reanimate (Grid.players s.grid);

  (* create phantom AI players *)
  (while List.length (Grid.players s.grid) < 4 do
    s.grid <- Grid.add_player s.grid (Player.create_ai (rules s).trail_length (255,0,0));
  done);

  let () = send_all_players s Initial in
  s.started <- true;

  return () >>=
    fun () -> Lwt_unix.sleep ((rules s).time_between_games /. (rules s).ticks_per_second)
    >>= tick s

(* Handles incoming communication from clients *)
and receive_frame s id content =
    print_endline (Yojson.Basic.to_string content);

    let open Yojson.Basic.Util in
    match content with
    | `Assoc _ -> (
      let input = parse content in
      match input with
      | Turn d ->
        let p = Grid.player_with_id (grid s) id in
        (match p with
        | Some x ->
          let success = Player.update_direction x d in
          send s id (message s id (Confirm (s.started && success)))
        | _ -> send s id (message s id (Confirm false)))

      | Join name ->
        let p = Player.create_human id (rules s).trail_length (0,0,0) name in
        s.grid <- Grid.add_player (grid s) p;
        let rtn = send s id (message s id (Confirm s.started)) in
        let () = (
          (* start game in 10 seconds after first player joins *)
          if List.length (Grid.players s.grid) = 1 then
            let _ = start_ticking s () in
            ()
          else
            let _ = send s id (message s id Initial) in
            ()
          ) in
        rtn
      | _ -> send s id "{ \"type\": \"error\", \"message\": \"Invalid message\" }"
      )
    | _ -> send s id "{ \"type\": \"error\", \"message\": \"Invalid message\" }"

(* Sends JSON of game board to all humans and the Grid.t instance to AI users *)
and send_all_players s msg =
  try
    let js = message s (-1) msg in
    List.iter (fun x -> let _ = send s (Player.id x) js in ()) (Grid.players s.grid)
  with
  | _ -> print_endline "failed to create grid json"


(* starts this server *)
let start s =
  (* Creates a server instance with the given handler *)
  let serve uri handler =
    Resolver_lwt.resolve_uri ~uri Resolver_lwt_unix.system >>= fun endp ->
    Conduit_lwt_unix.(endp_to_server ~ctx:default_ctx endp >>= fun server ->
    establish_server ~ctx:default_ctx ~mode:server handler)
  in

  (* Handles communication between client/server *)
  let handler id req recv send =
    let open Frame in
    (* keep a reference to the send function for this player *)
    let () = add_handler s id send in

    let rec response () =
      recv () >>= fun frame ->

      match frame.opcode with
      | Opcode.Ping -> send (Frame.create ~opcode:Opcode.Pong ()) >>= response
      | Opcode.Text -> receive_frame s id (Yojson.Basic.from_string frame.content) >>= response
      | Opcode.Close ->
        s.grid <- (Grid.remove_player s.grid id);
        send (Frame.close 1000)
      | _ -> send (Frame.close 1002)
    in
    response ()
  in

  (* start our server locally on port 3110 *)
  let uri = Uri.make ~scheme:"http" ~host:(host s) ~port:(port s) ~path:"websocket" () in
  serve uri handler
