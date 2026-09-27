fun escapes (cr : real, ci : real) =
  let fun go (zr, zi, i) =
        if i >= 50 then false
        else let val zr2 = zr * zr val zi2 = zi * zi in
               if zr2 + zi2 > 4.0 then true
               else go (zr2 - zi2 + cr, 2.0 * zr * zi + ci, i + 1)
             end
  in go (0.0, 0.0, 0) end
fun row (n, ci, x, acc) =
  if x >= n then acc
  else let val cr = 2.0 * real x / real n - 1.5 in
         row (n, ci, x + 1, if escapes (cr, ci) then acc else acc + 1)
       end
fun grid (n, y, acc) =
  if y >= n then acc
  else grid (n, y + 1, row (n, 2.0 * real y / real n - 1.0, 0, acc))
val () = let val n = readInt () in print (Int.toString (grid (n, 0, 0)) ^ "\n") end
