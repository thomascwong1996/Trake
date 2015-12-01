type color = int * int * int

type t = {
  id: int;
  label: string;
  color: color;
  mutable alive: bool;
  mutable direction: Util.direction;
  mutable tail_length: int;
  mutable position: int * int;
  mutable tail: (int * int) list;
  human: bool
}

let create_human id tl clr lbl =
  {
    id = id;
    label = lbl;
    color = clr;
    alive = true;
    direction = Util.Down;
    tail_length = tl;
    position = (1, 1);
    tail = [];
    human = true;
  }

let create_ai id tl clr lbl =
  {
    id = id;
    label = lbl;
    color = clr;
    alive = true;
    direction = Util.Down;
    tail_length = tl;
    position = (1,1);
    tail = [];
    human = false;
  }

let id p =
  p.id

let is_human p =
  p.human

let is_ai p =
  not (p.human)

let direction p =
  p.direction

let update_direction p d =
  p.direction <- d

let update_position p c =
  p.position <- c

let is_alive p =
  p.alive

let kill p =
  p.tail <- [];
  p.alive <- false

let label p =
  p.label

let color p =
  p.color

let to_json p =
  failwith "Unimplemented"

let tail_length p =
  p.tail_length

let eat_food p =
  p.tail_length <- (tail_length p) + 1

let position p =
  p.position

let tail p =
  p.tail

let occupies_cell p c =
  (position p) = c ||
    List.mem c (tail p)

let advance p =
  (* Get new position *)
  let delta = Util.vector_of_direction (direction p) in
  let pos = position p in
  let new_pos = Util.add_cells pos delta in

  (* Add old position to tail list *)
  let new_tail = pos::(tail p) in

  (* Remove extra pieces from tail list *)
  let rec helper tl l accum =
    if l <= 0 then
      accum
    else
      match tl with
      | h::t -> helper t (l - 1) (h::accum)
      | [] -> []
  in
  if tail p = [] then
    p.tail <- (helper new_tail (tail_length p) [])
  else
    p.tail <- (helper new_tail ((List.length new_tail) - (tail_length p)) []);
  p.position <- new_pos
