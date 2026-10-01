(* Constant folding, as Perceus's cfold.kk and Main.idr here; the Counting
   Immutable Beans SML version (const_fold.sml), reading the depth from
   stdin. *)

datatype expr =
    Var of int
  | Val of int
  | Add of expr * expr
  | Mul of expr * expr

fun mkExpr n v =
  if n = 0 then (if v = 0 then Var 1 else Val v)
  else Add (mkExpr (n - 1) (v + 1), mkExpr (n - 1) (Int.max (v - 1, 0)))

fun appendAdd (Add (e1, e2)) e3 = Add (e1, appendAdd e2 e3)
  | appendAdd e0 e3 = Add (e0, e3)

fun appendMul (Mul (e1, e2)) e3 = Mul (e1, appendMul e2 e3)
  | appendMul e0 e3 = Mul (e0, e3)

fun reassoc (Add (e1, e2)) = appendAdd (reassoc e1) (reassoc e2)
  | reassoc (Mul (e1, e2)) = appendMul (reassoc e1) (reassoc e2)
  | reassoc e = e

fun cfold (Add (e1, e2)) =
      let val e1' = cfold e1
          val e2' = cfold e2
      in case (e1', e2') of
             (Val a, Val b) => Val (a + b)
           | (Val a, Add (f, Val b)) => Add (Val (a + b), f)
           | (Val a, Add (Val b, f)) => Add (Val (a + b), f)
           | _ => Add (e1', e2')
      end
  | cfold (Mul (e1, e2)) =
      let val e1' = cfold e1
          val e2' = cfold e2
      in case (e1', e2') of
             (Val a, Val b) => Val (a * b)
           | (Val a, Mul (f, Val b)) => Mul (Val (a * b), f)
           | (Val a, Mul (Val b, f)) => Mul (Val (a * b), f)
           | _ => Mul (e1', e2')
      end
  | cfold e = e

fun eval (Var _) = 0
  | eval (Val v) = v
  | eval (Add (l, r)) = eval l + eval r
  | eval (Mul (l, r)) = eval l * eval r

val n = readInt ()
val e = mkExpr n 1
val v1 = eval e
val v2 = eval (cfold (reassoc e))
val () = print (Int.toString v1 ^ " " ^ Int.toString v2 ^ "\n")
