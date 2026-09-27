fun tak (x, y, z) = if y < x then tak (tak (x - 1, y, z), tak (y - 1, z, x), tak (z - 1, x, y)) else z
fun repeat (0, n, acc) = acc
  | repeat (k, n, acc) = repeat (k - 1, n, acc + tak (n + k mod 2, (2 * n) div 3, n div 3))
val () = print (Int.toString (repeat (1000, readInt (), 0)) ^ "\n")
