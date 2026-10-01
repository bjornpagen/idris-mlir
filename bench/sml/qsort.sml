(* Quicksort of arrays of 32-bit words, as Lean's qsort.lean and Main.idr
   here; the Counting Immutable Beans SML version (qsort.sml), with the
   checksum of the middle elements that every version here prints. *)

fun readInt () =
  let fun go acc =
        case TextIO.input1 TextIO.stdIn of
            SOME c => if Char.isDigit c then go (acc * 10 + (Char.ord c - 48)) else acc
          | NONE => acc
  in go 0 end

type elem = Word32.word

fun badRand (seed : elem) : elem = seed * 0w1664525 + 0w1013904223

fun mkRandomArray n (seed : elem) =
  let val s = ref seed
  in Array.tabulate (n, fn _ => let val x = !s in s := badRand x; x end) end

fun swap arr i j =
  let val x = Array.sub (arr, i)
      val y = Array.sub (arr, j)
  in Array.update (arr, i, y); Array.update (arr, j, x) end

fun partitionAux arr hi (pivot : elem) i j =
  if j < hi then
    (if Array.sub (arr, j) < pivot
     then (swap arr i j; partitionAux arr hi pivot (i + 1) (j + 1))
     else partitionAux arr hi pivot i (j + 1))
  else (swap arr i hi; i)

fun partition arr lo hi =
  let val mid = (lo + hi) div 2
  in
    if Array.sub (arr, mid) < Array.sub (arr, lo) then swap arr lo mid else ();
    if Array.sub (arr, hi) < Array.sub (arr, lo) then swap arr lo hi else ();
    if Array.sub (arr, mid) < Array.sub (arr, hi) then swap arr mid hi else ();
    partitionAux arr hi (Array.sub (arr, hi)) lo lo
  end

fun qsortAux arr low high =
  if low < high then
    let val mid = partition arr low high
    in qsortAux arr low mid; qsortAux arr (mid + 1) high end
  else ()

fun checkSorted arr n i =
  if i < n - 1 then
    (if Array.sub (arr, i) <= Array.sub (arr, i + 1) then checkSorted arr n (i + 1) else false)
  else true

fun sizes n i acc =
  if i >= n then acc
  else
    let val a = mkRandomArray i (Word32.fromInt i)
        val () = qsortAux a 0 (i - 1)
    in
      if not (checkSorted a i 0) then ~1
      else sizes n (i + 1)
             (acc + (if i > 0 then Word32.toInt (Array.sub (a, i div 2)) else 0))
    end

fun reps n k acc =
  if k >= n then acc
  else
    let val s = sizes n 0 0
    in if s < 0 then ~1 else reps n (k + 1) (acc + s) end

val n = readInt ()
val s = reps n 0 0
val () = if s < 0 then print "array is not sorted\n" else print (Int.toString s ^ "\n")
