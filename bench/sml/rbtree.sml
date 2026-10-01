(* Red-black tree insertion, as Perceus's rbtree.kk and Main.idr here; the
   Counting Immutable Beans SML version (rbmap.sml) with Koka's balancing. *)

datatype color = Red | Black
datatype tree = Leaf | Node of color * tree * int * bool * tree

fun isRed (Node (Red, _, _, _, _)) = true
  | isRed _ = false

fun balanceLeft l k v r =
  case l of
      Node (_, Node (Red, lx, kx, vx, rx), ky, vy, ry) =>
        Node (Red, Node (Black, lx, kx, vx, rx), ky, vy, Node (Black, ry, k, v, r))
    | Node (_, ly, ky, vy, Node (Red, lx, kx, vx, rx)) =>
        Node (Red, Node (Black, ly, ky, vy, lx), kx, vx, Node (Black, rx, k, v, r))
    | Node (_, lx, kx, vx, rx) =>
        Node (Black, Node (Red, lx, kx, vx, rx), k, v, r)
    | Leaf => Leaf

fun balanceRight l k v r =
  case r of
      Node (_, Node (Red, lx, kx, vx, rx), ky, vy, ry) =>
        Node (Red, Node (Black, l, k, v, lx), kx, vx, Node (Black, rx, ky, vy, ry))
    | Node (_, lx, kx, vx, Node (Red, ly, ky, vy, ry)) =>
        Node (Red, Node (Black, l, k, v, lx), kx, vx, Node (Black, ly, ky, vy, ry))
    | Node (_, lx, kx, vx, rx) =>
        Node (Black, l, k, v, Node (Red, lx, kx, vx, rx))
    | Leaf => Leaf

fun ins t k v =
  case t of
      Node (Red, l, kx, vx, r) =>
        if k < kx then Node (Red, ins l k v, kx, vx, r)
        else if k > kx then Node (Red, l, kx, vx, ins r k v)
        else Node (Red, l, k, v, r)
    | Node (Black, l, kx, vx, r) =>
        if k < kx then
          (if isRed l then balanceLeft (ins l k v) kx vx r
           else Node (Black, ins l k v, kx, vx, r))
        else if k > kx then
          (if isRed r then balanceRight l kx vx (ins r k v)
           else Node (Black, l, kx, vx, ins r k v))
        else Node (Black, l, k, v, r)
    | Leaf => Node (Red, Leaf, k, v, Leaf)

fun setBlack (Node (_, l, k, v, r)) = Node (Black, l, k, v, r)
  | setBlack t = t

fun insert t k v = setBlack (ins t k v)

fun fold f (Node (_, l, k, v, r)) b = fold f r (f k v (fold f l b))
  | fold _ Leaf b = b

fun makeTree n t =
  if n <= 0 then t
  else let val n1 = n - 1 in makeTree n1 (insert t n1 (n1 mod 10 = 0)) end

val n = readInt ()
val t = makeTree n Leaf
val () = print (Int.toString (fold (fn _ => fn v => fn r => if v then r + 1 else r) t 0) ^ "\n")
