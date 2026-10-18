-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The growth check: whether a static argument of the program can grow
||| without bound, decided on the graph of its static positions, and
||| answered with a certificate either way.
|||
||| A graph grows when a cycle of finite arcs gains more than it loses each
||| round, or when it holds a Stuck arc (a type-level recursion nothing
||| bounds). Each cause is reported once: one cycle for each strongly
||| connected component that holds one, then each Stuck arc whose source no
||| growing component reaches, since a position a growing cycle reaches is
||| unbounded already. Otherwise every position is bounded, and the answer
||| is a potential that every arc satisfies.
|||
||| The components are settled callers first, so a component's floor is
||| final by the time it is settled. A component with an arc that loses can
||| hold a cycle that weighs nothing, so heaviest walks (`heaviestOver`)
||| decide it. In one with
||| no such arc, every cycle through an arc that gains grows, and a walk back
||| from that arc closes one; with no arc that gains either, every inner arc
||| weighs 0 and one value holds for the whole component. A settled
||| component raises the target of each arc out of it to the least value
||| that satisfies the arc.
|||
||| Each recursion ends by its structure:
||| - Tarjan's `visit` and `arcs` recurse on the count of positions not yet
|||   seen, which entering a position lowers, and `arcs` on the links it has
|||   left besides;
||| - `walkBack` recurses on its rounds, one for each member of the
|||   component, since a walk inside it has fewer arcs than members;
||| - a table's reads and writes recurse on its depth, and every other
|||   recursion on the list, table or count it reads.
module IdrisMLIR.Frontend.Growth.Check

import IdrisMLIR.Proof.Growth
import IdrisMLIR.Frontend.Growth.Potential

import Control.WellFounded
import Data.DPair
import Data.Fin
import Data.Fin.Properties
import Data.List
import Data.List1
import Data.Nat
import Data.Vect

%default total

||| Why a graph grows.
public export
data Cause : Graph -> Type where
  ||| A cycle of finite arcs whose gains exceed its losses: its arcs, each
  ||| leaving the position the one before entered.
  Cycle : (as : List (Fin (length g.arcs))) -> Positive g as -> Cause g
  ||| A Stuck arc no growing cycle reaches.
  Unbounded : (a : Fin (length g.arcs)) -> StuckArc g a -> Cause g

||| The check's answer, with its certificate.
public export
data Verdict : Graph -> Type where
  ||| At least one cause, by its type.
  Grows : List1 (Cause g) -> Verdict g
  ||| A potential every arc satisfies: a bound on every position.
  Bounded : (pot : Vect g.size Nat) -> Feasible g pot -> Verdict g

------------------------------------------------------------------------------
-- Tables
------------------------------------------------------------------------------

||| One value for each place below 2^d, a place read from its highest bit:
||| a part whose every place holds one value, or its two halves, the places
||| below 2^(d - 1) and those from it on. A table starts as one value and
||| splits only where it is written, so making one costs nothing, and
||| reading or writing a place costs its d bits; a `Vect` walks every
||| position before the one it reads, and the check reads a position for
||| each arc.
data Table : Nat -> Type -> Type where
  Every : a -> Table d a
  Halves : Table d a -> Table d a -> Table (S d) a

||| Where a table of depth d splits, from the top: at each level, the place
||| its upper half starts at.
data Halving : Nat -> Type where
  Whole : Halving Z
  Twice : (half : Nat) -> (0 _ : half = power 2 d) -> Halving d -> Halving (S d)

halving : (d : Nat) -> Halving d
halving Z = Whole
halving (S d) = Twice (power 2 d) Refl (halving d)

||| A graph's n positions as the places of tables of depth d: 2^d places
||| hold them, each position its own place, so that no two share one.
record Places (n, d : Nat) where
  constructor MkPlaces
  halving : Halving d
  0 hold : LTE n (power 2 d)

0 twice : (d : Nat) -> power 2 (S d) = power 2 d + power 2 d
twice d = cong (power 2 d +) (plusZeroRightNeutral (power 2 d))

0 atLeastOne : (d : Nat) -> LTE 1 (power 2 d)
atLeastOne Z = reflexive
atLeastOne (S d) = rewrite twice d in transitive (atLeastOne d) (lteAddRight (power 2 d))

0 minusBelow : (a, b : Nat) -> LTE (minus a b) a
minusBelow Z b = LTEZero
minusBelow (S a) Z = reflexive
minusBelow (S a) (S b) = lteSuccRight (minusBelow a b)

0 minusSucc : (h, k : Nat) -> LTE h k -> minus (S k) h = S (minus k h)
minusSucc Z k _ = rewrite minusZeroRight k in Refl
minusSucc (S h) (S k) (LTESucc le) = minusSucc h k le

||| A place of the lower half.
0 lower : {0 h, k : Nat} -> h = power 2 d -> So (k < h) -> LT k (power 2 d)
lower eq low = rewrite sym eq in ltSo low

||| A place of the upper half, less where it starts, is a place of a half.
0 upper : {h, k : Nat} -> h = power 2 d -> So (not (k < h)) -> LT k (power 2 (S d)) -> LT (minus k h) (power 2 d)
upper eq high lt =
  let le = notLTImpliesGTE (notLtSo high)
      below = the (LT k (h + h)) (rewrite eq in rewrite sym (twice d) in lt) in
  rewrite sym eq in rewrite sym (minusSucc h k le) in
  replace {p = \x => LTE (minus (S k) h) x} (minusPlus h) (minusLteMonotone {p = h} below)

||| A table of depth S d as its two halves.
split : Table (S d) a -> (Table d a, Table d a)
split (Every x) = (Every x, Every x)
split (Halves l r) = (l, r)

||| The value at place k.
atPlace : Halving d -> Table d a -> (k : Nat) -> (0 _ : LT k (power 2 d)) -> a
atPlace _ (Every x) _ _ = x
atPlace (Twice half eq hs) (Halves l r) k lt = case choose (k < half) of
  Left low => atPlace hs l k (lower eq low)
  Right high => atPlace hs r (minus k half) (upper eq high lt)

||| The table with the value at place k changed.
updatePlace : Halving d -> (k : Nat) -> (0 _ : LT k (power 2 d)) -> (a -> a) -> Table d a -> Table d a
updatePlace Whole k _ f (Every x) = Every (f x)
updatePlace (Twice half eq hs) k lt f t =
  let (l, r) = split t in
  case choose (k < half) of
    Left low => Halves (updatePlace hs k (lower eq low) f l) r
    Right high => Halves l (updatePlace hs (minus k half) (upper eq high lt) f r)

||| A position's place is below 2^d.
0 placed : Places n d -> (p : Fin n) -> LT (finToNat p) (power 2 d)
placed pl p = transitive (elemSmallerThanBound p) pl.hold

||| The value at a position.
at : Places n d -> Table d a -> Fin n -> a
at pl t p = atPlace pl.halving t (finToNat p) (placed pl p)

||| The table with the value at a position changed.
update : Places n d -> Fin n -> (a -> a) -> Table d a -> Table d a
update pl p f t = updatePlace pl.halving (finToNat p) (placed pl p) f t

put : Places n d -> Fin n -> a -> Table d a -> Table d a
put pl p x = update pl p (const x)

0 decrease : (n, p, q : Nat) -> LT p n -> LTE 1 q -> LT (minus n (p + q)) (minus n p)
decrease Z p q lt _ = absurd lt
decrease (S n) Z Z _ one = absurd one
decrease (S n) Z (S q) _ _ = LTESucc (minusBelow n q)
decrease (S n) (S p) q (LTESucc lt) one = decrease n p q lt one

||| The places of n positions: the first power of two no less than n, with
||| the proof that it is. Each doubling leaves less of n above the places.
placesFor : (n : Nat) -> (d ** Places n d)
placesFor n = go 0 1 Refl (sizeAccessible (minus n 1))
  where
    go : (d, p : Nat) -> (0 _ : p = power 2 d) -> (0 _ : SizeAccessible (minus n p)) -> (d ** Places n d)
    go d p eq (Access rec) = case choose (n <= p) of
      Left fits => (d ** MkPlaces (halving d) (rewrite sym eq in lteSo fits))
      Right more =>
        go (S d) (p + p) (rewrite eq in sym (twice d))
           (rec (minus n (p + p)) (decrease n p p (notLTEImpliesGT (notLteSo more)) (rewrite eq in atLeastOne d)))

||| Every position from i on, in order, in one pass: `natToFinLT` is the
||| identity at run time, where a vector built by mapping `FS` over the one
||| below it costs the square of its length.
positionsFrom : (i, rest : Nat) -> (0 _ : i + rest = n) -> Vect rest (Fin n)
positionsFrom i Z _ = []
positionsFrom i (S r) prf = natToFinLT i {prf = runBelow i prf} :: positionsFrom (S i) r (trans (plusSuccRightSucc i r) prf)

0 positionAt : (i, rest : Nat) -> (prf : i + rest = n) -> (j : Fin rest) ->
               finToNat (index j (positionsFrom i rest prf)) = i + finToNat j
positionAt i (S r) prf FZ = rewrite plusZeroRightNeutral i in finToNatLT i
positionAt i (S r) prf (FS j) =
  rewrite sym (plusSuccRightSucc i (finToNat j)) in positionAt (S i) r (trans (plusSuccRightSucc i r) prf) j

0 indexMap : (f : a -> b) -> (xs : Vect k a) -> (j : Fin k) -> index j (map f xs) = f (index j xs)
indexMap f (x :: _) FZ = Refl
indexMap f (_ :: xs) (FS j) = indexMap f xs j

||| The values at the n positions, in order.
listed : {n : Nat} -> Places n d -> Table d a -> Vect n a
listed pl t = map (at pl t) (positionsFrom 0 n Refl)

||| A position of the listed values is its value in the table.
0 indexListed : {n : Nat} -> (pl : Places n d) -> (t : Table d a) -> (j : Fin n) -> index j (listed pl t) = at pl t j
indexListed pl t j =
  rewrite indexMap (at pl t) (positionsFrom 0 n Refl) j in
  rewrite injective {f = finToNat} {x = index j (positionsFrom 0 n Refl)} {y = j} (positionAt 0 n Refl j) in Refl

||| A vector's values, each at its position, over a table.
tabled : {n : Nat} -> Places n d -> Vect n a -> Table d a -> Table d a
tabled pl xs t = foldl (\t', (p, x) => put pl p x t') t (zip (positionsFrom 0 n Refl) xs)

------------------------------------------------------------------------------
-- Components (Tarjan)
------------------------------------------------------------------------------

||| Where the search stands with a position: not met yet, met and still on
||| the stack with the index it was met at, or in a component found. Only a
||| position on the stack has an index, so one on the stack without an
||| index cannot be written.
data Mark = Unseen | Open Nat | Done

||| How many places the search has yet to meet: its measure.
unseen : {d : Nat} -> Table d Mark -> Nat
unseen {d} (Every Unseen) = power 2 d
unseen (Every (Open _)) = 0
unseen (Every Done) = 0
unseen (Halves l r) = unseen l + unseen r

||| A part of one mark leaves as many unseen as its two halves.
0 halvesOf : {d : Nat} -> (m : Mark) -> unseen {d = S d} (Every m) = unseen {d} (Every m) + unseen {d} (Every m)
halvesOf Unseen = twice d
halvesOf (Open _) = Refl
halvesOf Done = Refl

||| A table of depth S d as its two halves, which leave as many unseen.
record Halved {0 d : Nat} (t : Table (S d) Mark) where
  constructor MkHalved
  left : Table d Mark
  right : Table d Mark
  0 same : unseen t = unseen left + unseen right

halves : {0 d : Nat} -> (t : Table (S d) Mark) -> Halved t
halves (Every m) = MkHalved (Every m) (Every m) (halvesOf m)
halves (Halves l r) = MkHalved l r Refl

||| A position as the search finds it: met now, with the marks after and the
||| proof that fewer positions are left to meet; on the stack, with its
||| index; or already in a component. These are the three cases Tarjan's
||| search has.
data Look : {d : Nat} -> Table d Mark -> Type where
  Fresh : {0 t : Table d Mark} -> (t' : Table d Mark) -> (0 _ : LT (unseen t') (unseen t)) -> Look t
  OnStack : {0 t : Table d Mark} -> Nat -> Look t
  Finished : {0 t : Table d Mark} -> Look t

0 lessLeft : (c : Nat) -> LT a b -> LT (a + c) (b + c)
lessLeft c lt = plusLteMonotoneRight c (S a) b lt

0 lessRight : (c : Nat) -> LT a b -> LT (c + a) (c + b)
lessRight c lt = rewrite plusSuccRightSucc c a in plusLteMonotoneLeft c (S a) b lt

||| Looks place k up, opening it at index i if it is unseen.
lookPlace : {0 d : Nat} -> Halving d -> (k : Nat) -> (0 _ : LT k (power 2 d)) -> (i : Nat) -> (t : Table d Mark) -> Look t
lookPlace Whole k _ i (Every Unseen) = Fresh (Every (Open i)) (LTESucc LTEZero)
lookPlace _ k _ i (Every (Open j)) = OnStack j
lookPlace _ k _ i (Every Done) = Finished
lookPlace (Twice half eq hs) k lt i t = let MkHalved l r same = halves t in
  case choose (k < half) of
    Left low => case lookPlace hs k (lower eq low) i l of
      Fresh l' less => Fresh (Halves l' r) (rewrite same in lessLeft (unseen r) less)
      OnStack j => OnStack j
      Finished => Finished
    Right high => case lookPlace hs (minus k half) (upper eq high lt) i r of
      Fresh r' less => Fresh (Halves l r') (rewrite same in lessRight (unseen l) less)
      OnStack j => OnStack j
      Finished => Finished

||| Looks a position up, opening it at index i if it is unseen.
look : Places n d -> Fin n -> (i : Nat) -> (t : Table d Mark) -> Look t
look pl p i t = lookPlace pl.halving (finToNat p) (placed pl p) i t

||| The table with place k done: none becomes unseen.
donePlace : {0 d : Nat} -> Halving d -> (k : Nat) -> (0 _ : LT k (power 2 d)) -> (t : Table d Mark) ->
            Subset (Table d Mark) (\t' => LTE (unseen t') (unseen t))
donePlace Whole k _ (Every m) = Element (Every Done) LTEZero
donePlace (Twice half eq hs) k lt t = let MkHalved l r same = halves t in
  case choose (k < half) of
    Left low => let Element l' p = donePlace hs k (lower eq low) l in
                Element (Halves l' r) (rewrite same in plusLteMonotoneRight (unseen r) _ _ p)
    Right high => let Element r' p = donePlace hs (minus k half) (upper eq high lt) r in
                  Element (Halves l r') (rewrite same in plusLteMonotoneLeft (unseen l) _ _ p)

||| The search: the next index, every position's mark, the stack of open
||| positions, and the components found, the last found first.
record Search (d : Nat) (n : Nat) where
  constructor MkSearch
  next : Nat
  marks : Table d Mark
  stack : List (Fin n)
  found : List (List (Fin n))

{d : Nat} -> Sized (Search d n) where
  size s = unseen s.marks

||| A search with no more positions left to meet than another.
0 NoMore : {d : Nat} -> Search d n -> Search d n -> Type
NoMore s' s = LTE (size s') (size s)

||| Marks a component's members done; none becomes unseen again.
finish : Places n d -> List (Fin n) -> (ms : Table d Mark) -> Subset (Table d Mark) (\ms' => LTE (unseen ms') (unseen ms))
finish pl [] ms = Element ms reflexive
finish pl (w :: ws) ms = let Element ms1 p1 = finish pl ws ms
                             Element ms2 p2 = donePlace pl.halving (finToNat w) (placed pl w) ms1 in
                         Element ms2 (transitive p2 p1)

||| Pops the component whose root is v off the stack: v and every position
||| opened after it. The record is built whole, since an update of a
||| variable's field does not reduce `.marks` in the measure's type.
close : Places n d -> (v : Fin n) -> (s : Search d n) -> Subset (Search d n) (\s' => NoMore s' s)
close pl v s =
  let (above, rest) = break (== v) s.stack
      members = v :: above
      Element ms p = finish pl members s.marks in
  Element (MkSearch s.next ms (drop 1 rest) (members :: s.found)) p

||| The search once it has opened v, with the marks `look` returned.
entered : (s : Search d n) -> (v : Fin n) -> (ms : Table d Mark) -> Search d n
entered s v ms = MkSearch (S s.next) ms (v :: s.stack) s.found

mutual
  ||| Visits v, just opened at index i: follows its links, then closes its
  ||| component if v is the root, the one whose low link is its own index.
  ||| Returns v's low link.
  visit : Places n d -> Table d (List (Fin n)) -> (v : Fin n) -> (i : Nat) -> (s : Search d n) -> (0 _ : SizeAccessible s) ->
          (Nat, Subset (Search d n) (\s' => NoMore s' s))
  visit pl adj v i s acc = case arcs pl adj i (at pl adj v) s acc s reflexive of
    (low, Element s1 p1) =>
      if low == i
        then case close pl v s1 of Element s2 p2 => (low, Element s2 (transitive p2 p1))
        else (low, Element s1 p1)

  ||| Follows a position's links in order: an unseen target is visited on a
  ||| search with fewer positions left to meet than `s0`, which `s0`'s
  ||| accessibility covers; one on the stack lowers the low link; one in a
  ||| component found is passed.
  arcs : Places n d -> Table d (List (Fin n)) -> (low : Nat) -> List (Fin n) ->
         (s0 : Search d n) -> (0 _ : SizeAccessible s0) -> (s : Search d n) -> (0 _ : NoMore s s0) ->
         (Nat, Subset (Search d n) (\s' => NoMore s' s))
  arcs pl adj low [] s0 acc s p = (low, Element s reflexive)
  arcs pl adj low (w :: ws) s0 acc@(Access rec) s p = case look pl w s.next s.marks of
    Fresh ms lt =>
      case visit pl adj w s.next (entered s w ms) (rec (entered s w ms) (transitive lt p)) of
        (wlow, Element s2 p2) =>
          case arcs pl adj (min low wlow) ws s0 acc s2 (transitive p2 (transitive (lteSuccLeft lt) p)) of
            (low', Element s3 p3) => (low', Element s3 (transitive p3 (transitive p2 (lteSuccLeft lt))))
    OnStack j => arcs pl adj (min low j) ws s0 acc s p
    Finished => arcs pl adj low ws s0 acc s p

||| Starts a visit at each position not met yet. One met already is in a
||| component found: each root's visit closes every position it opened.
roots : Places n d -> Table d (List (Fin n)) -> Vect k (Fin n) -> Search d n -> Search d n
roots pl adj [] s = s
roots pl adj (v :: vs) s = case look pl v s.next s.marks of
  Fresh ms _ => case visit pl adj v s.next (entered s v ms) (sizeAccessible (entered s v ms)) of
    (_, Element s2 _) => roots pl adj vs s2
  _ => roots pl adj vs s

||| The strongly connected components, callers first: a component is closed
||| only after every component it links to, and each is put in front of
||| those closed before it, so for a link between two components its
||| source's comes first.
components : {n : Nat} -> Places n d -> Table d (List (Fin n)) -> List (List (Fin n))
components pl adj = (roots pl adj (positionsFrom 0 n Refl) (MkSearch 0 (Every Unseen) [] [])).found

------------------------------------------------------------------------------
-- Reading the arcs, once
------------------------------------------------------------------------------

||| A Finite arc between positions, read once: its index, its ends and its
||| weight, with the arc the index names, which carries each over to `arc g
||| at`. The index is `at`, since a field named `arc` would shadow `arc`
||| inside the record.
record Edge (g : Graph) where
  constructor MkEdge
  at : Fin (length g.arcs)
  from : Fin g.size
  to : Fin g.size
  gain : Nat
  loss : Nat
  0 is : arc g at = MkArc from to (Measured gain loss)

0 labelIs : (e : Edge g) -> (arc g e.at).label = Measured e.gain e.loss
labelIs e = cong (.label) e.is

0 finiteEdge : (e : Edge g) -> IsFinite (arc g e.at).label
finiteEdge e = replace {p = IsFinite} (sym (labelIs e)) ItIsFinite

||| Edges as heaviest walks read them.
entries : (es : List (Edge g)) -> Looked g (map (.at) es)
entries [] = []
entries (e :: es) = MkEntry e.from e.to e.gain e.loss e.is :: entries es

||| The Unmeasured arcs of a list of arcs: none, and so every arc is
||| Measured, or some, each with its source and its cause, in the arcs'
||| order.
data Stucks : (g : Graph) -> List (Fin (length g.arcs)) -> Type where
  None : (0 _ : All IsFinite (labels g as)) -> Stucks g as
  Some : List1 (Fin g.size, Cause g) -> Stucks g as

||| The arcs as the check reads them: each position's Measured edges out and
||| its links (the targets of every arc out of it, Measured or not, which
||| the components and the reach follow), and the Unmeasured arcs.
record Sorted (g : Graph) (d : Nat) (as : List (Fin (length g.arcs))) where
  constructor MkSorted
  out : Table d (List (Edge g))
  links : Table d (List (Fin g.size))
  stucks : Stucks g as

||| Reads each arc once, in one pass over the arcs (`lookUp`): each comes
||| with its equality to `arc g a`, which carries what it is over to `arc g
||| a`. Looking each up by its index would walk the arcs before it, the
||| square of their number in all. Each position's arcs are in the arcs'
||| order.
sortArcs : (g : Graph) -> Places g.size d -> (as : List (Fin (length g.arcs))) -> At g as -> Sorted g d as
sortArcs g pl [] [] = MkSorted (Every []) (Every []) (None [])
sortArcs g pl (a :: as) ((::) x eq xs) = place x eq (sortArcs g pl as xs)
  where
    finiteToo : (0 _ : IsFinite (arc g a).label) -> Stucks g as -> Stucks g (a :: as)
    finiteToo f (None fs) = None (f :: fs)
    finiteToo f (Some ss) = Some ss

    stuckList : Stucks g as -> List (Fin g.size, Cause g)
    stuckList (None _) = []
    stuckList (Some ss) = forget ss

    -- An arc by what it is: a Measured arc is an edge out of its source
    -- and a link; an Unmeasured one is a link, and a cause of its own.
    place : (x : Arc g.size) -> (0 _ : x = arc g a) -> Sorted g d as -> Sorted g d (a :: as)
    place (MkArc q p (Measured gain loss)) eq (MkSorted out links stucks) =
      MkSorted (update pl q (MkEdge a q p gain loss (sym eq) ::) out) (update pl q (p ::) links)
               (finiteToo (replace {p = \y => IsFinite y.label} eq ItIsFinite) stucks)
    place (MkArc q p Unmeasured) eq (MkSorted out links stucks) =
      MkSorted out (update pl q (p ::) links)
               (Some ((q, Unbounded a (ItIsStuck (cong (.label) (sym eq)))) ::: stuckList stucks))

------------------------------------------------------------------------------
-- One component
------------------------------------------------------------------------------

||| An inner edge of a component no arc of which loses more than it gains.
record Steady (g : Graph) where
  constructor MkSteady
  edge : Edge g
  0 holds : LTE edge.loss edge.gain

||| An inner edge that gains, in such a component: every cycle through it
||| grows.
record Gaining (g : Graph) where
  constructor MkGaining
  edge : Edge g
  0 rises : LT edge.loss edge.gain

||| The inner edges, each steady, unless one loses more than it gains.
steadily : List (Edge g) -> Maybe (List (Steady g))
steadily [] = Just []
steadily (e :: es) = case choose (e.loss <= e.gain) of
  Left le => (MkSteady e (lteSo le) ::) <$> steadily es
  Right _ => Nothing

||| The steady edges that gain.
gaining : List (Steady g) -> List (Gaining g)
gaining [] = []
gaining (s :: ss) = case choose (s.edge.loss < s.edge.gain) of
  Left lt => MkGaining s.edge (ltSo lt) :: gaining ss
  Right _ => gaining ss

||| A walk: its steady edges, in order.
Walk : Graph -> Type
Walk g = List (Steady g)

||| Extends the known walks back along one edge: its source, if it has no
||| walk yet, takes the walk of its target. A position keeps the first walk
||| it gets, so each position is on a walk once.
step : Places g.size d -> Table d (Maybe (Walk g)) -> Steady g -> Table d (Maybe (Walk g))
step pl ws s = case (at pl ws s.edge.from, at pl ws s.edge.to) of
  (Nothing, Just w) => put pl s.edge.from (Just (s :: w)) ws
  _ => ws

||| The walk from `start` to the position whose entry the walks began with,
||| along inner edges. Each round extends every known walk by at least one
||| edge back, so a start the component reaches has its walk within one
||| round per member. A start may have none: the component is held together
||| by every link, Stuck ones included, and a walk takes only Finite edges.
walkBack : Places g.size d -> (rounds : Nat) -> List (Steady g) -> (start : Fin g.size) -> Table d (Maybe (Walk g)) -> Maybe (Walk g)
walkBack pl Z _ start ws = at pl ws start
walkBack pl (S r) inner start ws = case at pl ws start of
  Just w => Just w
  Nothing => walkBack pl r inner start (foldl (step pl) ws inner)

||| Whether a walk after `e` chains around to `first`: each edge leaves the
||| position the one before entered, and the last enters `first`. A walk is
||| built by putting an edge before the walk at its target, but the table
||| does not tie an entry to its place, so the chain is compared here, once.
ring : (first : Fin g.size) -> (e : Edge g) -> (w : Walk g) ->
       Decision (Ring g first e.from (e.at :: map (\s => s.edge.at) w))
ring first e [] = case samePosition e.to first of
  Holds t => Holds (Last (cong (.from) e.is) (trans (cong (.to) e.is) t))
  Fails nt => Fails (\(Last _ t) => nt (trans (sym (cong (.to) e.is)) t))
ring first e (s :: w) = case samePosition e.to s.edge.from of
  Fails nt => Fails (\(Next _ t r) => nt (trans (sym (cong (.to) e.is)) (trans t (startsAt s r))))
  Holds t => case ring first s.edge w of
    Holds r => Holds (Next (cong (.from) e.is) (trans (cong (.to) e.is) t) r)
    Fails nr => Fails (\(Next _ _ r) => nr (replace {p = \x => Ring g first x (s.edge.at :: map (\s' => s'.edge.at) w)}
                                                   (startsAt s r) r))
  where
    -- A ring whose first arc is a steady edge starts at the edge's source.
    0 startsAt : (s : Steady g) -> Ring g first here (s.edge.at :: as) -> here = s.edge.from
    startsAt s r = trans (sym (ringStart r)) (cong (.from) s.edge.is)

0 finiteAll : (e : Edge g) -> (w : Walk g) -> All IsFinite (labels g (e.at :: map (\s => s.edge.at) w))
finiteAll e [] = [finiteEdge e]
finiteAll e (s :: w) = finiteEdge e :: finiteAll s.edge w

-- What steady edges sum to: no more lost than gained.
0 steadySum : (w : Walk g) -> LTE (losses (labels g (map (\s => s.edge.at) w))) (gains (labels g (map (\s => s.edge.at) w)))
steadySum [] = LTEZero
steadySum (s :: w) =
  replace {p = \x => LTE (lossOf x + losses (labels g (map (\s => s.edge.at) w))) (gainOf x + gains (labels g (map (\s => s.edge.at) w)))}
          (sym (labelIs s.edge)) (plusLteMonotone s.holds (steadySum w))

-- A gaining edge and steady ones gain more than they lose.
0 rises : (e : Gaining g) -> (w : Walk g) ->
          LT (losses (labels g (e.edge.at :: map (\s => s.edge.at) w))) (gains (labels g (e.edge.at :: map (\s => s.edge.at) w)))
rises e w =
  replace {p = \x => LT (lossOf x + losses (labels g (map (\s => s.edge.at) w))) (gainOf x + gains (labels g (map (\s => s.edge.at) w)))}
          (sym (labelIs e.edge)) (plusLteMonotone e.rises (steadySum w))

||| The first gaining edge of `es` whose walk back from its target to its
||| source closes a cycle: it grows, the other edges being steady.
cycleThrough : (g : Graph) -> Places g.size d -> (rounds : Nat) -> List (Steady g) -> List (Gaining g) -> Maybe (Cause g)
cycleThrough g pl rounds inner [] = Nothing
cycleThrough g pl rounds inner (e :: es) =
  case walkBack pl rounds inner e.edge.to (put pl e.edge.from (Just []) (Every Nothing)) of
    Just w => case ring e.edge.from e.edge w of
      Holds r => Just (Cycle (e.edge.at :: map (\s => s.edge.at) w) (Sums r (finiteAll e.edge w) (rises e w)))
      -- A walk that does not chain is no cycle the check can name. If no
      -- candidate's does, the component is settled as bounded, the
      -- potential fails `feasibleIn`, and `heaviest` over every arc still
      -- finds the cycle, so no verdict rests on this.
      Fails _ => cycleThrough g pl rounds inner es
    Nothing => cycleThrough g pl rounds inner es

||| What the components settled so far leave: the potential, final on them
||| and a lower bound on the rest; the positions a growing component
||| reaches; and the cycles found, the last found first.
record State (g : Graph) (d : Nat) where
  constructor MkState
  pot : Table d Nat
  reached : Table d Bool
  cycles : List (Cause g)

||| Settles one component, the k-th callers first, whose callers are all
||| settled: its cycle, or its potential and what it asks of the components
||| it links to; and what it reaches.
settle : (g : Graph) -> Places g.size d -> {0 as : List (Fin (length g.arcs))} -> Sorted g d as -> (comp : Table d Nat) ->
         State g d -> (Nat, List (Fin g.size)) -> State g d
settle g pl arcs comp st (k, members) =
  let outs = members >>= \q => at pl arcs.out q
      (inner, leaving) = partition (\e => at pl comp e.to == k) outs in
  case judge inner of
    Left c => MkState st.pot (marked st.reached) (c :: st.cycles)
    -- A component that does not grow passes on a reach from its callers,
    -- or none.
    Right pot => MkState (foldl raise pot leaving)
                         (if any (\q => at pl st.reached q) members then marked st.reached else st.reached)
                         st.cycles
  where
    ||| The members' greatest value, held by each member: the least
    ||| potential when every inner arc weighs 0, since around a cycle of
    ||| such arcs no value can be lower than the one before.
    level : Table d Nat
    level = let top = foldl (\b, q => max b (at pl st.pot q)) 0 members in
            foldl (\p, q => put pl q top p) st.pot members

    ||| The component's cycle, or its potential: one, never both. The
    ||| heaviest walks start from, and give, a potential of every position.
    judge : List (Edge g) -> Either (Cause g) (Table d Nat)
    judge inner = case steadily inner of
      -- An arc that loses can make a cycle through an arc that gains weigh
      -- nothing, so only heaviest walks decide such a component, over the
      -- edges as read.
      Nothing => case heaviestOver (entries inner) (listed pl st.pot) of
        Left (as ** pf) => Left (Cycle as pf)
        Right fitted => Right (tabled pl fitted.pot st.pot)
      -- With no such arc, every cycle through an arc that gains grows, and
      -- the walk back finds one at the cost of the component's own arcs.
      Just steady =>
        maybe (Right level) Left
          (cycleThrough g pl (length members) steady
            (sortBy (\x, y => compare (finToNat x.edge.at) (finToNat y.edge.at)) (gaining steady)))

    ||| Raises an arc's target to the least value that satisfies the arc.
    raise : Table d Nat -> Edge g -> Table d Nat
    raise pot e = update pl e.to (max (minus (at pl pot e.from + e.gain) e.loss)) pot

    ||| Marks the members, and every position they link to, as reached.
    marked : Table d Bool -> Table d Bool
    marked r = foldl (\r', q => foldl (\r'', p => put pl p True r'') (put pl q True r') (at pl arcs.links q)) r members

||| An Unmeasured arc is a cause of its own unless a growing component
||| reaches its source.
cause : Places g.size d -> Table d Bool -> (Fin g.size, Cause g) -> Maybe (Cause g)
cause pl marks (q, c) = if at pl marks q then Nothing else Just c

||| The least potential the caps ask: each capped position's floor
||| (`floorOf`), where the potential starts.
floors : (g : Graph) -> Vect g.size Nat
floors g = map (floorOf g.constant) g.caps

||| The arcs, read once, and the components settled callers first, from the
||| caps' floors: the one fold that both `check` and `dagPotential` read,
||| over tables whose places hold the graph's positions.
settled : (g : Graph) -> Places g.size d -> (Sorted g d (everyArc g), State g d)
settled g pl =
  let arcs = sortArcs g pl (everyArc g) (lookUp g (everyArc g))
      cs = counted 0 (components pl arcs.links)
      -- 0 is no position's number in the end: `roots` visits every
      -- position, so every position is in a component.
      comp = foldl (\v, (k, ms) => foldl (\v', p => put pl p k v') v ms) (the (Table d Nat) (Every 0)) cs in
  (arcs, foldl (settle g pl arcs comp) (MkState (tabled pl (floors g) (Every 0)) (Every False) []) cs)
  where
    counted : Nat -> List a -> List (Nat, a)
    counted k [] = []
    counted k (x :: xs) = (k, x) :: counted (S k) xs

------------------------------------------------------------------------------
-- The potential, checked where the table holds it
------------------------------------------------------------------------------

||| A potential raised to at least another, position by position.
raised : (pot, lo : Vect n Nat) -> Subset (Vect n Nat) (Below lo)
raised [] [] = Element [] []
raised (v :: vs) (l :: ls) =
  let Element rest below = raised vs ls in
  case choose (l <= v) of
    Left le => Element (v :: rest) (lteSo le :: below)
    Right _ => Element (l :: rest) (reflexive :: below)

||| Whether one arc fits the potential a table holds, read at its ends:
||| `index` into the listed potential would walk the positions before each
||| end, for every arc.
satisfiesIn : {n : Nat} -> (pl : Places n d) -> (t : Table d Nat) -> (a : Arc n) -> Decision (Satisfies (listed pl t) a)
-- No potential bounds an Unmeasured arc. `check` asks only of a graph
-- whose arcs are all Measured, but reads them here as the graph holds them.
satisfiesIn pl t (MkArc q p Unmeasured) = Fails (\case _ impossible)
satisfiesIn pl t (MkArc q p (Measured gain loss)) = case choose (at pl t q + gain <= at pl t p + loss) of
  Left le => Holds (MkSatisfies (rewrite indexListed pl t q in rewrite indexListed pl t p in lteSo le))
  Right nle => Fails (\(MkSatisfies le) => notLteSo nle (the (LTE (at pl t q + gain) (at pl t p + loss))
                                                            (rewrite sym (indexListed pl t q) in
                                                             rewrite sym (indexListed pl t p) in le)))

satisfyAllIn : {n : Nat} -> (pl : Places n d) -> (t : Table d Nat) -> (as : List (Arc n)) -> Decision (All (Satisfies (listed pl t)) as)
satisfyAllIn pl t [] = Holds []
satisfyAllIn pl t (a :: as) = case satisfiesIn pl t a of
  Fails nf => Fails (\(f :: _) => nf f)
  Holds f => case satisfyAllIn pl t as of
    Fails nfs => Fails (\(_ :: fs) => nfs fs)
    Holds fs => Holds (f :: fs)

||| Whether a table's potential is feasible: every arc of the graph, its
||| ends read in the table, and every cap.
feasibleIn : (g : Graph) -> (pl : Places g.size d) -> (t : Table d Nat) -> Decision (Feasible g (listed pl t))
feasibleIn g pl t = case satisfyAllIn pl t g.arcs of
  Fails nfs => Fails (\(MkFeasible fs _) => nfs fs)
  Holds fs => case capsHold g.constant g.caps (listed pl t) of
    Fails ncs => Fails (\(MkFeasible _ cs) => ncs cs)
    Holds cs => Holds (MkFeasible fs cs)

||| The potential over the components, before `check` rechecks it.
export
dagPotential : (g : Graph) -> Vect g.size Nat
dagPotential g = let (d ** pl) = placesFor g.size in listed pl (snd (settled g pl)).pot

||| The verdict, with its certificate. Cycles come callers first, then the
||| Stuck arcs in the arcs' order.
export
check : (g : Graph) -> Verdict g
check g =
  let (d ** pl) = placesFor g.size
      (arcs, st) = settled g pl in
  case (reverse st.cycles, arcs.stucks) of
    (c :: rest, None _) => Grows (c ::: rest)
    (c :: rest, Some ss) => Grows (c ::: rest ++ mapMaybe (cause pl st.reached) (forget ss))
    -- With no growing component nothing is reached, so every Stuck arc is
    -- a cause.
    ([], Some ss) => Grows (map snd ss)
    ([], None fin) => case feasibleIn g pl st.pot of
      Holds f => Bounded (listed pl st.pot) f
      -- The potential over the components is the least one when they are
      -- right, so a failure here is this module's own bug, which the
      -- exhaustive box shows. `heaviest` over every arc still answers with
      -- a certificate, from a start no lower than the caps' floors, which
      -- it only raises.
      Fails _ =>
        let start = raised (listed pl st.pot) (floors g) in
        case heaviest g (everyArc g) fin start.fst of
          Left (as ** pf) => Grows (Cycle as pf ::: [])
          Right fitted =>
            Bounded fitted.pot (everyFits fitted.fits
                                 (capsAbove (capsAbove (floorsHold g.constant g.caps) start.snd) fitted.above))
