// The linear red-black tree of Main.idr here (docs/plan.md 4.4, experiment
// 4), in Koka: the same program, with Koka's reuse deciding at runtime
// whether a matched cell is unique. linrb-shared.kk differs at one call
// site.
import std/os/readline

type color
  Red
  Black

type tree
  Leaf
  Node(color : color, lchild : tree, key : int, value : bool, rchild : tree)

fun balance1(kv : int, vv : bool, t : tree, n : tree) : tree
  match n
    Node(_, Node(Red, l, kx, vx, r1), ky, vy, r2)
      -> Node(Red, Node(Black, l, kx, vx, r1), ky, vy, Node(Black, r2, kv, vv, t))
    Node(_, l1, ky, vy, Node(Red, l2, kx, vx, r))
      -> Node(Red, Node(Black, l1, ky, vy, l2), kx, vx, Node(Black, r, kv, vv, t))
    Node(_, l, ky, vy, r)
      -> Node(Black, Node(Red, l, ky, vy, r), kv, vv, t)
    Leaf -> Node(Black, Leaf, kv, vv, t)

fun balance2(t : tree, kv : int, vv : bool, n : tree) : tree
  match n
    Node(_, Node(Red, l, kx1, vx1, r1), ky, vy, r2)
      -> Node(Red, Node(Black, t, kv, vv, l), kx1, vx1, Node(Black, r1, ky, vy, r2))
    Node(_, l1, ky, vy, Node(Red, l2, kx2, vx2, r2))
      -> Node(Red, Node(Black, t, kv, vv, l1), ky, vy, Node(Black, l2, kx2, vx2, r2))
    Node(_, l, ky, vy, r)
      -> Node(Black, t, kv, vv, Node(Red, l, ky, vy, r))
    Leaf -> Node(Black, t, kv, vv, Leaf)

// The isRed tests of Lean's ins are matches on the child, which rebuild
// the node they matched: free for a unique cell.
fun ins(kx : int, vx : bool, t : tree) : div tree
  match t
    Leaf -> Node(Red, Leaf, kx, vx, Leaf)
    Node(Red, a, ky, vy, b)
      -> if kx < ky then Node(Red, ins(kx, vx, a), ky, vy, b)
         elif kx == ky then Node(Red, a, kx, vx, b)
         else Node(Red, a, ky, vy, ins(kx, vx, b))
    Node(Black, a, ky, vy, b) ->
      if kx < ky then
        match a
          Node(Red, l, k, v, r) -> balance1(ky, vy, b, ins(kx, vx, Node(Red, l, k, v, r)))
          _ -> Node(Black, ins(kx, vx, a), ky, vy, b)
      elif kx == ky then Node(Black, a, kx, vx, b)
      else
        match b
          Node(Red, l, k, v, r) -> balance2(a, ky, vy, ins(kx, vx, Node(Red, l, k, v, r)))
          _ -> Node(Black, a, ky, vy, ins(kx, vx, b))

fun set-black(t : tree) : tree
  match t
    Node(_, l, k, v, r) -> Node(Black, l, k, v, r)
    Leaf -> Leaf

fun insert(k : int, v : bool, t : tree) : div tree
  set-black(ins(k, v, t))

// Counts the True values, consuming the tree.
fun count(t : tree, acc : int) : int
  match t
    Leaf -> acc
    Node(_, l, _, v, r) ->
      val c = count(l, acc)
      count(r, if v then c + 1 else c)

fun mk-map(n : int, t : tree) : div tree
  if n <= 0 then t
  else
    val n1 = n - 1
    mk-map(n1, insert(n1, (n1 % 10) == 0, t))

pub fun main()
  val n = readline().parse-int.default(4200000)
  println(count(mk-map(n, Leaf), 0).show)
