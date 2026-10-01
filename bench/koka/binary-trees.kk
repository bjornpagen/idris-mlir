// Binary trees on one core, as Main.idr here (Lean's binarytrees.st.lean).
// Perceus's binarytrees.kk is the same benchmark spread over tasks and
// checked by an FBIP visitor; this version keeps to one core and checks
// with a borrowing traversal, as the other versions here do.
import std/os/readline

type tree
  Node( left : tree, right : tree )
  Tip

fun make-seed( n : int, d : int ) : div tree
  if d == 0 then Node(Tip, Tip)
  else Node(make-seed(n, d - 1), make-seed(n + 1, d - 1))

fun make( d : int ) : div tree
  make-seed(d, d)

fun check( ^t : tree ) : div int
  match t
    Node(l, r) -> 1 + check(l) + check(r)
    Tip        -> 0

// Builds and checks i trees of depth d, adding their checks to t.
fun sum-t( d : int, i : int, t : int ) : div int
  if i == 0 then t else sum-t(d, i - 1, t + check(make-seed(i, d)))

fun out( s : string, depth : int, c : int ) : console ()
  println(s ++ " of depth " ++ depth.show ++ "\t check: " ++ c.show)

fun depths( min-n : int, max-n : int, d : int ) : <div,console> ()
  if d <= max-n then
    val n = pow(2, max-n - d + min-n)
    out(n.show ++ "\t trees", d, sum-t(d, n, 0))
    depths(min-n, max-n, d + 2)

pub fun main()
  val n = readline().parse-int.default(21)
  val min-n = 4
  val max-n = max(min-n + 2, n)
  val stretch-n = max-n + 1
  out("stretch tree", stretch-n, check(make(stretch-n)))
  val long = make(max-n)
  depths(min-n, max-n, min-n)
  out("long lived tree", max-n, check(long))
