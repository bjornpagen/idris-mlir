(* All solutions of the n-queens problem, as Perceus's nqueens.kk and
   Main.idr here. *)

fun safe queen diag (q :: qs) =
      queen <> q andalso queen <> q + diag andalso queen <> q - diag
      andalso safe queen (diag + 1) qs
  | safe _ _ [] = true

fun appendSafe queen xs xss =
  if queen <= 0 then xss
  else if safe queen 1 xs then appendSafe (queen - 1) xs ((queen :: xs) :: xss)
  else appendSafe (queen - 1) xs xss

fun extend queen acc (xs :: rest) = extend queen (appendSafe queen xs acc) rest
  | extend _ acc [] = acc

fun findSolutions n queen =
  if queen = 0 then [[]] else extend n [] (findSolutions n (queen - 1))

fun len (_ :: xs) r = len xs (r + 1)
  | len [] r = r

val n = readInt ()
val () = print (Int.toString (len (findSolutions n n) 0) ^ "\n")
