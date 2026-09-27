fun series (i, n, h, a) =
  if i > n then (h, a)
  else let val x = 1.0 / Real.fromInt i
       in series (i + 1, n, h + x, if i mod 2 = 0 then a - x else a + x) end
val (h, a) = series (1, readInt (), 0.0, 0.0)
val () = print (Real.fmt (StringCvt.GEN (SOME 17)) h ^ "\n" ^ Real.fmt (StringCvt.GEN (SOME 17)) a ^ "\n")
