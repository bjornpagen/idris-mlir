// Quicksort of arrays of 32-bit words, as Main.idr here (Lean's
// qsort.lean). The Perceus suite has no qsort: Koka has no mutable array
// type, so this follows Lean's pure version, updating a vector held in a
// local variable, in place while it is unshared. Words are ints reduced
// modulo 2^32.
import std/os/readline

fun bad-rand( seed : int ) : int
  (seed * 1664525 + 1013904223) % 4294967296

fun mk-random-array( n : int, seed : int ) : vector<int>
  var s := seed
  vector-init(n) fn(_)
    val x = s
    s := bad-rand(x)
    x

fun partition( v : vector<int>, lo : int, hi : int ) : <exn,div> (int, vector<int>)
  var a := v
  fun swap( i : int, j : int )
    val x = a[i]
    a[i] := a[j]
    a[j] := x
  val mid = (lo + hi) / 2
  if a[mid] < a[lo] then swap(lo, mid)
  if a[hi] < a[lo] then swap(lo, hi)
  if a[mid] < a[hi] then swap(mid, hi)
  val pivot = a[hi]
  var i := lo
  var j := lo
  while { j < hi }
    if a[j] < pivot then
      swap(i, j)
      i := i + 1
    j := j + 1
  swap(i, hi)
  (i, a)

fun qsort-aux( v : vector<int>, low : int, high : int ) : <exn,div> vector<int>
  if low < high then
    val (mid, a) = partition(v, low, high)
    val a1 = qsort-aux(a, low, mid)
    qsort-aux(a1, mid + 1, high)
  else v

fun check-sorted( ^a : vector<int>, n : int, i : int ) : <exn,div> bool
  if i < n - 1 then (if a[i] <= a[i + 1] then check-sorted(a, n, i + 1) else False)
  else True

// Sorts arrays of every size i < n; returns the sum of their middle
// elements, or -1 if one is not sorted.
fun sizes( n : int, i : int, acc : int ) : <exn,div> int
  if i >= n then acc
  else
    val a = qsort-aux(mk-random-array(i, i), 0, i - 1)
    if !check-sorted(a, i, 0) then -1
    else sizes(n, i + 1, acc + (if i > 0 then a[i / 2] else 0))

fun reps( n : int, k : int, acc : int ) : <exn,div> int
  if k >= n then acc
  else
    val s = sizes(n, 0, 0)
    if s < 0 then -1 else reps(n, k + 1, acc + s)

pub fun main()
  val n = readline().parse-int.default(400)
  val s = reps(n, 0, 0)
  if s < 0 then println("array is not sorted") else println(s.show)
