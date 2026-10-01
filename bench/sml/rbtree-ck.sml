(* Red-black tree insertion with checkpoints, as Perceus's rbtree-ck.kk and
   Main.idr here; the Counting Immutable Beans SML version
   (rbmap_checkpoint.sml). Keys run from n down to 1, as in rbtree-ck.kk. *)

datatype color = Red | Black
datatype tree = Leaf | Node of color * tree * int * bool * tree

fun balance1 kv vv t n =
  case n of
      Node (_, Node (Red, l, kx, vx, r1), ky, vy, r2) =>
        Node (Red, Node (Black, l, kx, vx, r1), ky, vy, Node (Black, r2, kv, vv, t))
    | Node (_, l1, ky, vy, Node (Red, l2, kx, vx, r)) =>
        Node (Red, Node (Black, l1, ky, vy, l2), kx, vx, Node (Black, r, kv, vv, t))
    | Node (_, l, ky, vy, r) =>
        Node (Black, Node (Red, l, ky, vy, r), kv, vv, t)
    | Leaf => Leaf

fun balance2 t kv vv n =
  case n of
      Node (_, Node (Red, l, kx1, vx1, r1), ky, vy, r2) =>
        Node (Red, Node (Black, t, kv, vv, l), kx1, vx1, Node (Black, r1, ky, vy, r2))
    | Node (_, l1, ky, vy, Node (Red, l2, kx2, vx2, r2)) =>
        Node (Red, Node (Black, t, kv, vv, l1), ky, vy, Node (Black, l2, kx2, vx2, r2))
    | Node (_, l, ky, vy, r) =>
        Node (Black, t, kv, vv, Node (Red, l, ky, vy, r))
    | Leaf => Leaf

fun isRed (Node (Red, _, _, _, _)) = true
  | isRed _ = false

fun ins t kx vx =
  case t of
      Leaf => Node (Red, Leaf, kx, vx, Leaf)
    | Node (Red, a, ky, vy, b) =>
        if kx < ky then Node (Red, ins a kx vx, ky, vy, b)
        else if kx = ky then Node (Red, a, kx, vx, b)
        else Node (Red, a, ky, vy, ins b kx vx)
    | Node (Black, a, ky, vy, b) =>
        if kx < ky then
          (if isRed a then balance1 ky vy b (ins a kx vx)
           else Node (Black, ins a kx vx, ky, vy, b))
        else if kx = ky then Node (Black, a, kx, vx, b)
        else if isRed b then balance2 a ky vy (ins b kx vx)
        else Node (Black, a, ky, vy, ins b kx vx)

fun setBlack (Node (_, l, k, v, r)) = Node (Black, l, k, v, r)
  | setBlack t = t

fun insert t k v = if isRed t then setBlack (ins t k v) else ins t k v

fun fold f (Node (_, l, k, v, r)) b = fold f r (f k v (fold f l b))
  | fold _ Leaf b = b

fun makeTreeAux freq n t acc =
  if n <= 0 then t :: acc
  else
    let val t' = insert t n (n mod 10 = 0)
    in makeTreeAux freq (n - 1) t' (if n mod freq = 0 then t' :: acc else acc) end

fun myLen (Node _ :: xs) r = myLen xs (r + 1)
  | myLen (_ :: xs) r = myLen xs r
  | myLen [] r = r

val n = readInt ()
val trees = makeTreeAux 5 n Leaf []
val v = case trees of
            t :: _ => fold (fn _ => fn v => fn r => if v then r + 1 else r) t 0
          | [] => 0
val () = print (Int.toString (myLen trees 0) ^ " " ^ Int.toString v ^ "\n")
