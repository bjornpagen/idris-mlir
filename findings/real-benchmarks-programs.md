# Real benchmarks: the new programs, quoted in full

Companion to real-benchmarks.md. The eight suite programs are not repeated:
they are `bench/gate/suite/<name>/` (Idris, SML, C, Koka, Lean), used
unchanged. These are the programs this stream wrote, each short enough to
rerun. Scratch copies are under
`scratchpad/research/real-benchmarks/`.

## Two reproducers of one bug: a linear scrutinee used whole after a match

Both typecheck and run on Chez. (Update: at `061b98d` `lincase` compiled and
printed 65 while `lincase2`, `linrb` and `linrb-shared` still failed; at the
02:38 build of `bd274ba` all four compile and print Chez's output.) At the
time of the first run, through `tools/compile.sh` both failed with
`internal error: idris-mlir-cc failed with status 1: ... 'idr.match' op uses
a linear value that is already used on the same path`. This is the same
error `bench/gate/linear/linrb` hits (at its `balance1` and at its
`case a of ... a' =>`), so the gate's experiment 4 program cannot be
compiled at all today. AGENTS.md asks for an `unsupported` rejection or a
compilation; an internal error is neither.

`lincase` (a catch-all that names the scrutinee; Chez prints 65):

```idris
module Main
import Prelude

data T : Type where
  L : T
  N : (1 l : T) -> Int -> T

data C = MkC Int

sz : (1 t : T) -> Int -> C
sz L acc = MkC acc
sz (N l k) acc = sz l (acc + k)

-- a case on a linear binder with a catch-all that names the scrutinee
f : (1 t : T) -> T
f t = case t of
        N l k => N (f l) (k + 1)
        t' => t'

build : Int -> T
build n = if n <= 0 then L else N (build (n - 1)) n

main : IO ()
main = do
  n <- pure 10
  let MkC c = sz (f (build n)) 0
  printLn c
```

`lincase2` (a nested pattern; the second clause binds `l`, which the first
clause's match already consumed; Chez prints 55):

```idris
module Main
import Prelude

data T : Type where
  L : T
  N : (1 l : T) -> Int -> T

data C = MkC Int

sz : (1 t : T) -> Int -> C
sz L acc = MkC acc
sz (N l k) acc = sz l (acc + k)

-- nested patterns on a linear binder: the second clause names l after the first matched it
g : (1 t : T) -> T
g (N (N l k) j) = N l (k + j)
g (N l j) = N l j
g L = L

build : Int -> T
build n = if n <= 0 then L else N (build (n - 1)) n

main : IO ()
main = do
  n <- pure 10
  let MkC c = sz (g (build n)) 0
  printLn c
```

Conjecture on the mechanism: Idris's case tree for overlapping or nested
patterns re-uses the *variable* of an already-matched scrutinee in a later
branch (`l1` in `g (N l j) = N l j` is the variable the inner match
scrutinized). For an unrestricted binder that is fine; for a `!idr.lin`
one the verifier's "used once on every path" rule fires. The
representation fix is in real-benchmarks.md §4.2: after a match on a
linear value, the whole value is its constructor rebuilt from the fields
(`idr.con` of the bound fields), which idr-rc then turns into the same
cell for free.

## fbip-rb: FP²'s fully in-place red-black tree

A port of Koka's `samples/basic/rbtree-fbip.kk` (in the pinned Koka 3.2.9
release, `.toolchain/koka/share/koka/v3.2.9/lib/samples/basic/`), same
workload as `rbtree`: n inserts of `(k, k mod 10 == 0)`, then count the
`True`s. Every constructor built has the size of a cell just taken apart,
so with unique cells an insert allocates only the new leaf's node.

```idris
module Main

-- FP2's fully in-place red-black tree (Koka's samples/basic/rbtree-fbip.kk,
-- after Lorenzen and Leijen): insertion walks down building a zipper out of
-- the cells it takes apart, and walks back up rebuilding the tree in them.
-- Every constructor rebuilt has the size of one just matched: with unique
-- cells nothing is allocated but the new leaf's node.

import Prelude

data Color = Red | Black

data Tree = Node Color Tree Int Bool Tree | Leaf

data Zipper = NodeR Color Tree Int Bool Zipper
            | NodeL Color Zipper Int Bool Tree
            | Done

moveUp : Zipper -> Tree -> Tree
moveUp (NodeR c l k v z1) t = moveUp z1 (Node c l k v t)
moveUp (NodeL c z1 k v r) t = moveUp z1 (Node c t k v r)
moveUp Done t = t

balanceRed : Zipper -> Tree -> Int -> Bool -> Tree -> Tree
balanceRed (NodeR Black l1 k1 v1 z1) l k v r = moveUp z1 (Node Black l1 k1 v1 (Node Red l k v r))
balanceRed (NodeL Black z1 k1 v1 r1) l k v r = moveUp z1 (Node Black (Node Red l k v r) k1 v1 r1)
balanceRed (NodeR Red l1 k1 v1 (NodeR _ l2 k2 v2 z2)) l k v r = balanceRed z2 (Node Black l2 k2 v2 l1) k1 v1 (Node Black l k v r)
balanceRed (NodeR Red l1 k1 v1 (NodeL _ z2 k2 v2 r2)) l k v r = balanceRed z2 (Node Black l1 k1 v1 l) k v (Node Black r k2 v2 r2)
balanceRed (NodeR Red l1 k1 v1 Done) l k v r = Node Black l1 k1 v1 (Node Red l k v r)
balanceRed (NodeL Red z1 k1 v1 r1) l k v r = balanceRedL z1 k1 v1 r1 l k v r
  where
    balanceRedL : Zipper -> Int -> Bool -> Tree -> Tree -> Int -> Bool -> Tree -> Tree
    balanceRedL (NodeR _ l2 k2 v2 z2) k1 v1 r1 l k v r = balanceRed z2 (Node Black l2 k2 v2 l) k v (Node Black r k1 v1 r1)
    balanceRedL (NodeL _ z2 k2 v2 r2) k1 v1 r1 l k v r = balanceRed z2 (Node Black l k v r) k1 v1 (Node Black r1 k2 v2 r2)
    balanceRedL Done k1 v1 r1 l k v r = Node Black (Node Red l k v r) k1 v1 r1
balanceRed Done l k v r = Node Black l k v r

ins : Tree -> Int -> Bool -> Zipper -> Tree
ins (Node c l kx vx r) k v z =
  if k < kx then ins l k v (NodeL c z kx vx r)
  else if k > kx then ins r k v (NodeR c l kx vx z)
  else moveUp z (Node c l kx vx r)
ins Leaf k v z = balanceRed z Leaf k v Leaf

insert : Tree -> Int -> Bool -> Tree
insert t k v = ins t k v Done

fold : Tree -> Int -> Int
fold (Node _ l _ v r) acc = fold r (let a = fold l acc in if v then a + 1 else a)
fold Leaf acc = acc

makeTree : Int -> Tree -> Tree
makeTree n t = if n <= 0 then t else let n1 = n - 1 in makeTree n1 (insert t n1 (n1 `mod` 10 == 0))

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

main : IO ()
main = do
  n <- readInt
  printLn (fold (makeTree n Leaf) 0)
```

## rbidx: the red-black tree with its invariants in its type

The colour is the constructor, the black height is an erased index, and a
red node has black children by its type. `balL`/`balR` have no `Leaf`
case and no mixed-height cases: the checker rejects them ("Mismatch
between: 0 and S ?n") when written, so they are not just unreachable but
unwritable. idris-mlir compiles it today: `RB` is a box of three
constructors (`E`, `TR`, `TB`) with no colour field, the index fields are
`!idr.erased`, and the existential wrappers `AnyRB`, `Almost` and `Root` are
`idr.data` (registers), never cells.

```idris
module Main

-- A red-black tree whose invariants are in its type: the colour is the
-- constructor, the black height is an erased index, a red node has black
-- children. Insertion is Okasaki's, and the checker proves every result is a
-- red-black tree. The runtime needs no colour field and no Leaf case in a
-- balance: the types rule them out.

import Prelude

data Color = R | B

data RB : Color -> Nat -> Type where
  E  : RB B Z
  TR : RB B n -> Int -> Bool -> RB B n -> RB R n
  TB : RB c1 n -> Int -> Bool -> RB c2 n -> RB B (S n)

-- Some tree of height n, colour erased.
data AnyRB : Nat -> Type where
  MkAny : {0 c : Color} -> RB c n -> AnyRB n

-- The result of inserting into a red node: a red root whose children may be
-- red (one infraction), or a valid tree.
data Almost : Nat -> Type where
  Ok : {0 c : Color} -> RB c n -> Almost n
  Infr : {0 c1, c2 : Color} -> RB c1 n -> Int -> Bool -> RB c2 n -> Almost n

balL : Almost n -> Int -> Bool -> RB c n -> AnyRB (S n)
balL (Infr (TR a x vx b) y vy c) z vz d = MkAny (TR (TB a x vx b) y vy (TB c z vz d))
balL (Infr a x vx (TR b y vy c)) z vz d = MkAny (TR (TB a x vx b) y vy (TB c z vz d))
balL (Infr E x vx E) z vz d = MkAny (TB (TR E x vx E) z vz d)
balL (Infr (TB a1 w vw a2) x vx (TB b1 y vy b2)) z vz d = MkAny (TB (TR (TB a1 w vw a2) x vx (TB b1 y vy b2)) z vz d)
balL (Ok t) z vz d = MkAny (TB t z vz d)

balR : RB c n -> Int -> Bool -> Almost n -> AnyRB (S n)
balR a x vx (Infr (TR b y vy c) z vz d) = MkAny (TR (TB a x vx b) y vy (TB c z vz d))
balR a x vx (Infr b y vy (TR c z vz d)) = MkAny (TR (TB a x vx b) y vy (TB c z vz d))
balR a x vx (Infr E y vy E) = MkAny (TB a x vx (TR E y vy E))
balR a x vx (Infr (TB b1 w vw b2) y vy (TB c1 z vz c2)) = MkAny (TB a x vx (TR (TB b1 w vw b2) y vy (TB c1 z vz c2)))
balR a x vx (Ok t) = MkAny (TB a x vx t)

mutual
  -- Inserting into a black-rooted tree gives a valid tree of the same height.
  insB : RB B n -> Int -> Bool -> AnyRB n
  insB E k v = MkAny (TR E k v E)
  insB (TB l x vx r) k v =
    if k < x then balL (insAny l k v) x vx r
    else if k > x then balR l x vx (insAny r k v)
    else MkAny (TB l k v r)

  -- Inserting into any tree gives an almost tree.
  insAny : RB c n -> Int -> Bool -> Almost n
  insAny E k v = unAny (insB E k v)
  insAny (TB l x vx r) k v = unAny (insB (TB l x vx r) k v)
  insAny (TR l x vx r) k v =
    if k < x then (case insB l k v of MkAny l' => Infr l' x vx r)
    else if k > x then (case insB r k v of MkAny r' => Infr l x vx r')
    else Infr l k v r

  unAny : AnyRB n -> Almost n
  unAny (MkAny t) = Ok t

-- A whole tree: black root, height erased.
data Root : Type where
  MkRoot : {0 n : Nat} -> RB B n -> Root

insert : Root -> Int -> Bool -> Root
insert (MkRoot t) k v = case insB t k v of
  MkAny (TR l x vx r) => MkRoot (TB l x vx r)
  MkAny E => MkRoot E
  MkAny (TB l x vx r) => MkRoot (TB l x vx r)

fold : RB c n -> Int -> Int
fold E acc = acc
fold (TR l _ v r) acc = fold r (let a = fold l acc in if v then a + 1 else a)
fold (TB l _ v r) acc = fold r (let a = fold l acc in if v then a + 1 else a)

makeTree : Int -> Root -> Root
makeTree n t = if n <= 0 then t else let n1 = n - 1 in makeTree n1 (insert t n1 (n1 `mod` 10 == 0))

count : Root -> Int
count (MkRoot t) = fold t 0

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

main : IO ()
main = do
  n <- readInt
  printLn (count (makeTree n (MkRoot E)))
```

## tmap-fip and tmap-std: FP² §3's tree map

100 maps of `(+1)` over a balanced tree of n leaves, then a sum (n = 100 000
prints 5010050000). tmap-fip is FP²'s zipper walk; tmap-std is the ordinary
recursive map, identical below its `tmap`. The suite's claim (real-benchmarks.md §5,
program 5) is that the compiler turns tmap-std into tmap-fip.

```idris
module Main

-- FP2's tmap (section 3), fully in-place: a zipper walk down the left spines
-- and back up, each Bin matched paired with a BinL, each BinL with a BinR,
-- each BinR with a Bin. On a unique tree nothing is allocated and the stack
-- stays flat. 100 maps over a tree of n leaves, then a sum.

import Prelude

data Tree = Tip Int | Bin Tree Tree

data Zip = Top | BinL Zip Tree | BinR Tree Zip

mutual
  down : Tree -> Zip -> Tree
  down (Bin l r) z = down l (BinL z r)
  down (Tip x) z = app (Tip (x + 1)) z

  app : Tree -> Zip -> Tree
  app t Top = t
  app t (BinR l up) = app (Bin l t) up
  app t (BinL up r) = down r (BinR t up)

tmap : Tree -> Tree
tmap t = down t Top

build : Int -> Int -> Tree
build lo hi = if lo >= hi then Tip lo else let mid = (lo + hi) `div` 2 in Bin (build lo mid) (build (mid + 1) hi)

total' : Tree -> Int -> Int
total' (Tip x) acc = acc + x
total' (Bin l r) acc = total' r (total' l acc)

iter : Int -> Tree -> Tree
iter k t = if k <= 0 then t else iter (k - 1) (tmap t)

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

main : IO ()
main = do
  n <- readInt
  printLn (total' (iter 100 (build 1 n)) 0)
```

tmap-std differs only in its header and `tmap`:

```idris
module Main

-- FP2's tmap (section 3), the standard recursive map: in place on a unique
-- tree with reuse, but the stack grows with the depth. 100 maps over a tree
-- of n leaves, then a sum.

import Prelude

data Tree = Tip Int | Bin Tree Tree

tmap : Tree -> Tree
tmap (Tip x) = Tip (x + 1)
tmap (Bin l r) = Bin (tmap l) (tmap r)
```

The Koka versions (`src/kk/tmapfip.kk`; tmapstd.kk has the recursive `tmap`
instead of `down`/`app`) share the same `build`, `total`, `iter` and `main`:

```koka
import std/os/readline
type tree
  Tip(x : int)
  Bin(l : tree, r : tree)
type tzipper
  Top
  BinL(up : tzipper, right : tree)
  BinR(left : tree, up : tzipper)
fip fun down( t : tree, z : tzipper ) : div tree
  match t
    Bin(l, r) -> down(l, BinL(z, r))
    Tip(x) -> app(Tip(x + 1), z)
fip fun app( t : tree, z : tzipper ) : div tree
  match z
    Top -> t
    BinR(l, up) -> app(Bin(l, t), up)
    BinL(up, r) -> down(r, BinR(t, up))
fun tmap( t : tree ) : div tree
  down(t, Top)
fun build( lo : int, hi : int ) : div tree
  if lo >= hi then Tip(lo) else
    val mid = (lo + hi) / 2
    Bin(build(lo, mid), build(mid + 1, hi))

fun total( t : tree, acc : int ) : div int
  match t
    Tip(x) -> acc + x
    Bin(l, r) -> total(r, total(l, acc))

fun iter( k : int, t : tree ) : div tree
  if k <= 0 then t else iter(k - 1, tmap(t))

pub fun main()
  val n = trim(readline()).parse-int.default(100000)
  println(total(iter(100, build(1, n)), 0))
```
