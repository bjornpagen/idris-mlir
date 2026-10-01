// Union-find with path compression and union by rank, as Main.idr here
// (Lean's unionfind.lean). The Perceus suite has no unionfind: Koka has no
// mutable array type, so the array is a vector in a local variable of
// `test`, updated in place while unshared, and the operations are local
// functions over it (Lean threads it through a state monad).
import std/os/readline

struct node-data(find : int, rank : int)

fun test( n : int ) : <div,exn> int
  if n < 2 then throw("input must be greater than 1")
  var s := vector(n, Node-data(0, 0))
  val cap = n
  fun find-entry-aux( fuel : int, x : int ) : <local<_h>,div,exn> node-data
    if fuel == 0 then throw("out of fuel")
    if x < 0 || x >= cap then throw("invalid Node")
    val e = s[x]
    if e.find == x then e
    else
      val e1 = find-entry-aux(fuel - 1, e.find)
      s[x] := e1
      e1
  fun find-entry( x : int ) : <local<_h>,div,exn> node-data
    find-entry-aux(cap, x)
  fun union( n1 : int, n2 : int ) : <local<_h>,div,exn> ()
    val r1 = find-entry(n1)
    val r2 = find-entry(n2)
    if r1.find == r2.find then ()
    elif r1.rank < r2.rank then s[r1.find] := Node-data(r2.find, 0)
    elif r1.rank == r2.rank then
      s[r1.find] := Node-data(r2.find, 0)
      s[r2.find] := Node-data(r2.find, r2.rank + 1)
    else s[r2.find] := Node-data(r1.find, 0)
  fun merge-pack-aux( fuel : int, x : int, d : int ) : <local<_h>,div,exn> ()
    if fuel != 0 && x + d < cap then
      union(x, x + d)
      merge-pack-aux(fuel - 1, x + 1, d)
  fun num-eqs-aux( fuel : int, x : int, r : int ) : <local<_h>,div,exn> int
    if fuel != 0 && x < cap then
      val e = find-entry(x)
      num-eqs-aux(fuel - 1, x + 1, if x == e.find then r else r + 1)
    else r
  for(0, n - 1) fn(i) { s[i] := Node-data(i, 1) }
  merge-pack-aux(cap, 0, 50000)
  merge-pack-aux(cap, 0, 10000)
  merge-pack-aux(cap, 0, 5000)
  merge-pack-aux(cap, 0, 1000)
  num-eqs-aux(cap, 0, 0)

pub fun main()
  val n = readline().parse-int.default(3000000)
  val r = try { test(n) }
  match r
    Ok(v) -> println("ok " ++ v.show)
    Error(e) -> println("Error : " ++ e.message)
