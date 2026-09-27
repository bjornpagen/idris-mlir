(* Binary trees on one core, as Main.idr here: Lean's binarytrees.st.lean;
   the Counting Immutable Beans SML version is binarytrees.st.sml. *)

fun readInt () =
  let fun go acc =
        case TextIO.input1 TextIO.stdIn of
            SOME c => if Char.isDigit c then go (acc * 10 + (Char.ord c - 48)) else acc
          | NONE => acc
  in go 0 end

datatype tree = Tip | Node of tree * tree

fun make' n d =
  if d = 0 then Node (Tip, Tip)
  else Node (make' n (d - 1), make' (n + 1) (d - 1))

fun make d = make' d d

fun check Tip = 0
  | check (Node (l, r)) = 1 + check l + check r

fun sumT d i t = if i = 0 then t else sumT d (i - 1) (t + check (make' i d))

fun pow2 k = if k = 0 then 1 else 2 * pow2 (k - 1)

fun out s depth c =
  print (s ^ " of depth " ^ Int.toString depth ^ "\t check: " ^ Int.toString c ^ "\n")

fun depths minN maxN d =
  if d > maxN then ()
  else
    let val n = pow2 (maxN - d + minN)
    in out (Int.toString n ^ "\t trees") d (sumT d n 0);
       depths minN maxN (d + 2)
    end

val n = readInt ()
val minN = 4
val maxN = Int.max (minN + 2, n)
val stretchN = maxN + 1
val () = out "stretch tree" stretchN (check (make stretchN))
val long = make maxN
val () = depths minN maxN minN
val () = out "long lived tree" maxN (check long)
