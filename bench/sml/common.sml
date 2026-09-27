(* Reads a non-negative decimal number from stdin. *)
fun readInt () =
  let fun go acc =
        case TextIO.input1 TextIO.stdIn of
            SOME c => if Char.isDigit c then go (acc * 10 + (Char.ord c - 48)) else acc
          | NONE => acc
  in go 0 end
