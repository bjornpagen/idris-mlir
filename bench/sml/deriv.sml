(* Symbolic differentiation, as Perceus's deriv.kk and Main.idr here; the
   Counting Immutable Beans SML version (deriv.sml), reading the number of
   derivatives from stdin. *)

datatype expr =
    Val of int
  | Var of string
  | Add of expr * expr
  | Mul of expr * expr
  | Pow of expr * expr
  | Ln of expr

fun pown a n =
  if n = 0 then 1
  else if n = 1 then a
  else let val b = pown a (n div 2) in b * b * (if n mod 2 = 0 then 1 else a) end

fun add n m =
  case (n, m) of
      (Val n, Val m) => Val (n + m)
    | (Val 0, f) => f
    | (f, Val 0) => f
    | (f, Val n) => add (Val n) f
    | (Val n, Add (Val m, f)) => add (Val (n + m)) f
    | (f, Add (Val n, g)) => add (Val n) (add f g)
    | (Add (f, g), h) => add f (add g h)
    | (f, g) => Add (f, g)

fun mul n m =
  case (n, m) of
      (Val n, Val m) => Val (n * m)
    | (Val 0, _) => Val 0
    | (_, Val 0) => Val 0
    | (Val 1, f) => f
    | (f, Val 1) => f
    | (f, Val n) => mul (Val n) f
    | (Val n, Mul (Val m, f)) => mul (Val (n * m)) f
    | (f, Mul (Val n, g)) => mul (Val n) (mul f g)
    | (Mul (f, g), h) => mul f (mul g h)
    | (f, g) => Mul (f, g)

fun powr m n =
  case (m, n) of
      (Val m, Val n) => Val (pown m n)
    | (_, Val 0) => Val 1
    | (f, Val 1) => f
    | (Val 0, _) => Val 0
    | (f, g) => Pow (f, g)

fun ln n =
  case n of
      Val 1 => Val 0
    | f => Ln f

fun d x f =
  case f of
      Val _ => Val 0
    | Var y => if x = y then Val 1 else Val 0
    | Add (f, g) => add (d x f) (d x g)
    | Mul (f, g) => add (mul f (d x g)) (mul g (d x f))
    | Pow (f, g) =>
        mul (powr f g) (add (mul (mul g (d x f)) (powr f (Val ~1))) (mul (ln f) (d x g)))
    | Ln f => mul (d x f) (powr f (Val ~1))

fun count f =
  case f of
      Val _ => 1
    | Var _ => 1
    | Add (f, g) => count f + count g
    | Mul (f, g) => count f + count g
    | Pow (f, g) => count f + count g
    | Ln f => count f

fun deriv i f =
  let val f' = d "x" f
      val () = print (Int.toString (i + 1) ^ " count: " ^ Int.toString (count f') ^ "\n")
  in f' end

fun nestAux s n x = if n = 0 then x else nestAux s (n - 1) (deriv (s - n) x)

val n = readInt ()
val x = Var "x"
val _ = nestAux n n (powr x x)
