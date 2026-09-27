fun ack (0, n) = n + 1
  | ack (m, 0) = ack (m - 1, 1)
  | ack (m, n) = ack (m - 1, ack (m, n - 1))
val () = print (Int.toString (ack (3, readInt ())) ^ "\n")
