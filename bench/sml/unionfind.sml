(* Union-find with path compression and union by rank, as Lean's
   unionfind.lean and Main.idr here. The array holds records; every update
   stores a newly built one. *)

type node = {find : int, rank : int}

exception Fail of string

fun findEntryAux (s : node array) cap fuel n =
  if fuel = 0 then raise Fail "out of fuel"
  else if n < 0 orelse n >= cap then raise Fail "invalid Node"
  else
    let val e = Array.sub (s, n)
    in
      if #find e = n then e
      else
        let val e1 = findEntryAux s cap (fuel - 1) (#find e)
        in Array.update (s, n, e1); e1 end
    end

fun findEntry s cap n = findEntryAux s cap cap n

fun union s cap n1 n2 =
  let val r1 = findEntry s cap n1
      val r2 = findEntry s cap n2
  in
    if #find r1 = #find r2 then ()
    else if #rank r1 < #rank r2 then Array.update (s, #find r1, {find = #find r2, rank = 0})
    else if #rank r1 = #rank r2 then
      (Array.update (s, #find r1, {find = #find r2, rank = 0});
       Array.update (s, #find r2, {find = #find r2, rank = #rank r2 + 1}))
    else Array.update (s, #find r2, {find = #find r1, rank = 0})
  end

fun mkNodes s cap n =
  if n < cap then (Array.update (s, n, {find = n, rank = 1}); mkNodes s cap (n + 1)) else ()

fun mergePackAux s cap fuel n d =
  if fuel = 0 then ()
  else if n + d < cap then (union s cap n (n + d); mergePackAux s cap (fuel - 1) (n + 1) d)
  else ()

fun mergePack s cap d = mergePackAux s cap cap 0 d

fun numEqsAux s cap fuel n r =
  if fuel = 0 then r
  else if n < cap then
    let val e = findEntry s cap n
    in numEqsAux s cap (fuel - 1) (n + 1) (if n = #find e then r else r + 1) end
  else r

fun test n =
  if n < 2 then raise Fail "input must be greater than 1"
  else
    let val s = Array.array (n, {find = 0, rank = 0})
    in
      mkNodes s n 0;
      mergePack s n 50000;
      mergePack s n 10000;
      mergePack s n 5000;
      mergePack s n 1000;
      numEqsAux s n n 0 0
    end

val n = readInt ()
val () = print ("ok " ^ Int.toString (test n) ^ "\n")
  handle Fail e => (print ("Error : " ^ e ^ "\n"); OS.Process.exit OS.Process.failure)
