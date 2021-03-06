(* ai is in charge of abstracting all the decision making of the ai
 * into a seperate file. The Ai will be given a Player and Grid and calculate
 * the best direction to go in response to the givens.
 *)

(* Grab max of a list *)
val max_val: 'a list -> 'a

(* Grab list of indexes which contain the max value *)
val index_list_of_maxes : int list -> int -> int -> int list

(* Grab directions given the indexes *)
val direction_list : int list -> 'a list -> 'a list

(* Generate a list of distances to see how far the dangers are from the AI
   in the order of Up | Down | Left | Right *)
val distance_list : Player.t -> Grid.t -> int list

(* Determine Manhattan distance between two points *)
val manhattan_distance : int * int -> int * int -> int

(* Generate a list of distances to see how far the AI is from the food in the
   order of best distances from the previous computation *)
val shortest_food_finder : Player.t -> Grid.t -> int list

(* Sum two lists together with same number of elements *)
val sum_equal_lists : int list -> int list -> int list

(* Print helper *)
val print_int_list : int list -> unit

(* Check if food exists *)
val food_exists: Grid.t -> bool

(* Implement shortest distance to food if food exists *)
val do_djikstras_if_food_exists : int list -> Player.t -> Grid.t -> int list

(* returns a direction that the AI should move based on various computations *)
val new_direction: Player.t -> Grid.t -> unit
