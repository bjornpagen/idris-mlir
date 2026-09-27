fun steps (1, acc) = acc
  | steps (m, acc) = steps (if m mod 2 = 0 then m div 2 else 3 * m + 1, acc + 1)
fun longest (n, i, best, at) =
  if i >= n then at
  else let val s = steps (i, 0) in
         if s > best then longest (n, i + 1, s, i) else longest (n, i + 1, best, at)
       end
val () = print (Int.toString (longest (readInt (), 1, 0, 1)) ^ "\n")
