-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| A definition's place in the context, resolved once; what a walk over the
||| context's definitions has entered, each at most once, and why the walk
||| ends; and the probes, the names of the frontend's own that no
||| definition has.
|||
||| Every definition has its place in the context, a non-negative `Int`
||| (`Placement`), read with the definition where the program is read.
||| A walk records the places it has entered in a binary tree over the bits
||| of a place, and entering a place it has not entered leaves fewer free:
||| that count is the measure a walk recurses on, so a walk that enters a
||| definition before it walks what the definition refers to ends however
||| the definitions refer to one another.
module IdrisMLIR.Frontend.Walk

import Core.Context

import public IdrisMLIR.Proof.Requests

import Control.WellFounded
import Data.DPair
import Data.List1
import Data.Nat
import Data.String
import Data.Vect

%default total

------------------------------------------------------------------------------
-- Places
------------------------------------------------------------------------------

||| A definition's place in the context: its index, and the index's bits,
||| the lowest first, which a walk's tree is entered by. Only `placementAt`
||| and `placementOf` make one, each of an index known not to be negative,
||| so every placement is of a non-negative index, and its path is that
||| index's.
export
record Placement where
  constructor MkPlacement
  index : Int
  path : Vect 63 Bool

-- The lowest `d` bits of a number, the lowest first, as many as the
-- type asks for.
bitsOf : {d : Nat} -> Int -> Vect d Bool
bitsOf {d = Z} _ = []
bitsOf {d = S k} i = (mod i 2 == 1) :: bitsOf (div i 2)

||| The placement of a context index known not to be negative: an `Int` is
||| 64 bits, so a non-negative one is its 63 lowest bits, and two indices
||| have two paths. A reader that holds the entry a name resolved to, with
||| the evidence that it is not negative, places it with no second lookup.
export
placementAt : (i : Int) -> (0 _ : (i < 0) = False) -> Placement
placementAt i _ = MkPlacement i (bitsOf i)

||| The placement of a context index (`placementAt`). A negative index is
||| no place: Idris's terms carry a bare `Int` (`Resolved`, a nested name's
||| parent), which the type does not keep from being negative, so that
||| case is the problem's, not this type's.
export
placementOf : Int -> Maybe Placement
placementOf i = if i < 0 then Nothing else Just (MkPlacement i (bitsOf i))

||| The placement of a name the context holds; nothing for one it does not.
export
placementIn : Context -> Name -> Maybe Placement
placementIn ctx n = getNameID n ctx >>= placementOf

-- A non-negative index is placed, at itself.
0 placedAt : (i : Int) -> (i < 0) = False -> placementOf i = Just (MkPlacement i (bitsOf i))
placedAt i nonNegative =
  replace {p = \lt => (if lt then Nothing else Just (MkPlacement i (bitsOf i))) = Just (MkPlacement i (bitsOf i))}
          (sym nonNegative) Refl

||| A name the context resolves to an entry that is not negative has a
||| placement: what the host knows of the entries it reads, from entry 0
||| up, carried to a place.
export
0 placedWhereResolved : {0 ctx : Context} -> {0 n : Name} -> {0 i : Int} ->
                        getNameID n ctx = Just i -> (i < 0) = False ->
                        (p : Placement ** placementIn ctx n = Just p)
placedWhereResolved {i} resolved nonNegative =
  (MkPlacement i (bitsOf i) ** trans (cong (\found => found >>= placementOf) resolved) (placedAt i nonNegative))

||| The `k` bytes of a number, the low byte first.
export
bytes : (k : Nat) -> Integer -> Vect k (Fin 256)
bytes Z _ = []
bytes (S k) v = lowBits 8 v :: bytes k (v `div` 256)

||| A definition's identity, as the request links compare it: its index's
||| eight bytes, the low byte first.
export
addressOf : Placement -> Address
addressOf p = bytes 8 (cast p.index)

------------------------------------------------------------------------------
-- Walks
------------------------------------------------------------------------------

||| The places entered below a node of `d` levels: none, the one place a
||| leaf stands for, or those of each half.
data Seen : Nat -> Type where
  None : Seen d
  Leaf : Seen Z
  Split : Seen d -> Seen d -> Seen (S d)

||| The places below a node of `d` levels: a power of two, which this module
||| keeps to itself. A walk's tree is 63 levels deep, so in a type outside
||| it, normalised as Idris normalises (the frontend's own compilation
||| does), the count would be written out in unary, 2^63 constructors deep.
export
capacity : Nat -> Nat
capacity d = power 2 d

||| The places not entered below a node.
free : {d : Nat} -> Seen d -> Nat
free {d} None = capacity d
free Leaf = 0
free (Split l r) = free l + free r

||| What a walk has entered, over a tree as deep as a placement's path.
export
record Walked where
  constructor MkWalked
  seen : Seen 63

export
Sized Walked where
  size w = free w.seen

||| A walk that has entered nothing yet.
export
start : Walked
start = MkWalked None

||| Fewer on the right of a sum is fewer in the sum.
0 rightOf : (a : Nat) -> LT b c -> LT (a + b) (a + c)
rightOf a p = rewrite plusSuccRightSucc a b in plusLteMonotoneLeft a (S b) c p

||| Fewer than `n` on the right of `n` is fewer than twice `n`.
0 leftOf : (n : Nat) -> LT b n -> LT (n + b) (n + (n + 0))
leftOf n p = rewrite plusZeroRightNeutral n in rightOf n p

||| A tree holding only the place at `path`.
seenOnly : Vect d Bool -> Seen d
seenOnly [] = Leaf
seenOnly (False :: bs) = Split (seenOnly bs) None
seenOnly (True :: bs) = Split None (seenOnly bs)

||| A tree holding only one place leaves one fewer free.
0 onlyFewer : {d : Nat} -> (path : Vect d Bool) -> LT (free (seenOnly path)) (capacity d)
onlyFewer [] = LTESucc LTEZero
onlyFewer {d = S k} (False :: bs) =
  rewrite plusZeroRightNeutral (power 2 k) in plusLteMonotoneRight (power 2 k) (S (free (seenOnly bs))) (power 2 k) (onlyFewer bs)
onlyFewer {d = S k} (True :: bs) = leftOf (power 2 k) (onlyFewer bs)

||| A tree holding only the place at `path`, which leaves one fewer free.
only : {d : Nat} -> (path : Vect d Bool) -> Subset (Seen d) (\t => LT (free t) (capacity d))
only path = Element (seenOnly path) (onlyFewer path)

||| The tree with the place at `path` entered, which leaves fewer free;
||| nothing when it was entered already.
enterAt : {d : Nat} -> (path : Vect d Bool) -> (t : Seen d) -> Maybe (Subset (Seen d) (\t' => LT (free t') (free t)))
enterAt path None = Just (only path)
enterAt [] Leaf = Nothing
enterAt (False :: bs) (Split l r) = case enterAt bs l of
  Just (Element l' p) => Just (Element (Split l' r) (plusLteMonotoneRight (free r) (S (free l')) (free l) p))
  Nothing => Nothing
enterAt (True :: bs) (Split l r) = case enterAt bs r of
  Just (Element r' p) =>
    Just (Element (Split l r') (rightOf (free l) p))
  Nothing => Nothing

||| A walk that has entered one definition and nothing before it, which a
||| first entry cannot find entered already.
export
startAt : Placement -> Walked
startAt p = MkWalked (seenOnly p.path)

||| The walk with a definition entered, which leaves fewer to enter;
||| nothing when it was entered already.
export
enter : Placement -> (w : Walked) -> Maybe (Subset Walked (\w' => Smaller w' w))
enter p (MkWalked t) = do
  Element t' less <- enterAt p.path t
  Just (Element (MkWalked t') less)

||| A walk after another has entered no more than it.
public export
0 NoMore : Walked -> Walked -> Type
NoMore w' w = LTE (size w') (size w)

export
0 noMore : (w : Walked) -> NoMore w w
noMore w = reflexive

export
0 fewer : Smaller w' w -> NoMore w' w
fewer = lteSuccLeft

export
0 thenNoMore : NoMore w2 w1 -> NoMore w1 w -> NoMore w2 w
thenNoMore p q = transitive p q

export
0 thenFewer : NoMore w2 w1 -> Smaller w1 w -> Smaller w2 w
thenFewer p q = transitive (LTESucc p) q

export
0 fewerThen : Smaller w2 w1 -> NoMore w1 w -> Smaller w2 w
fewerThen q p = transitive q p

------------------------------------------------------------------------------
-- Probes
------------------------------------------------------------------------------

||| A probe: a name of the frontend's own, which no definition has, so it
||| has no placement, standing in a term for something the term does not
||| hold. One constructor per family, each read back by its constructor:
|||
||| - `ProbeBinder i`: the `i`th binder of a constructor's type (`Types`);
||| - `ProbeHole i`: the runtime value `i` an implementation closes over
|||   (`Closed.holeMarker`);
||| - `ProbeHoleFound i`: a value a term's holes are found at, before the
|||   values one variable holds are made one (`Terms`);
||| - `ProbeUnknown`: what is not known of a runtime value (`Closed`);
||| - `ProbeRuntime`: the one runtime variable a closed term's cut stands at
|||   (`Closed`);
||| - `ProbeRuntimeAt p`: the runtime value at place `p` of a site's scope,
|||   until the term is closed (`Sites.holed`);
||| - `ProbeStandIn k`: the `k`th binder of a constructor's type, in its
|||   return type (`Fields`);
||| - `ProbePattern k`: the pattern variable `k` of a site (`Sites`);
||| - `ProbeForm`: the form a shape stands for (`Shapes`);
||| - `ProbeAxis i j`, with `ProbeAxisAt j`, the reference it is applied
|||   to: axis `i` of the array parameter `j` (`Shapes`);
||| - `ProbeSize i`: the size variable `i` (`Shapes`);
||| - `ProbePart i path`: the part of the growth walk's writer's parameter
|||   `i` that matches reached along `path`, the field of the parameter
|||   first, which reads as the writer's `Var i (length path)`; field j of a
|||   match on it is `ProbePart i (path ++ [j])`, so that each marker stands
|||   for one value an instance gives (`Template`);
||| - `ProbeFormal j a`: argument `j` of a family's value of arity `a`;
||| - `ProbeFieldPath i path`: the fields of the writer's dictionary
|||   parameter `i` along a path, the first field first. A dictionary keeps
|||   its marker through every match, so it is never a part of a parameter.
public export
data Probe = ProbeBinder Nat
           | ProbeHole Nat
           | ProbeHoleFound Nat
           | ProbeUnknown
           | ProbeRuntime
           | ProbeRuntimeAt Nat
           | ProbeStandIn Nat
           | ProbePattern Nat
           | ProbeForm
           | ProbeAxis Nat Nat
           | ProbeAxisAt Nat
           | ProbeSize Nat
           | ProbePart Nat (List Nat)
           | ProbeFormal Nat Nat
           | ProbeFieldPath Nat (List1 Nat)

-- A path's steps nested around a name, the first step outermost, as a
-- part's and a dictionary field's names hold their paths.
along : List Nat -> Name -> Name
along [] n = n
along (k :: ks) n = Nested (cast k, 0) (along ks n)

||| A probe's name: the one place a probe is spelled, each family by its
||| own identifier, a constant of the compiler's known vocabulary that the
||| session's table holds at a fixed id from its start, so no probe is ever
||| interned or looked up. Its spelling (`idris-mlir-hole` and kin) is no
||| text an Idris identifier can be, so no name of a program meets it. Each
||| family keeps the constructor of `Name` it has always had: a machine name
||| (`MN`) where no normaliser meets it under a binder, a name nested around
||| a user name where one does, since Idris's quotation takes a bound
||| machine name for the binder of that number
||| (`Core.Normalise.Quote.quoteHead`). An axis is two references, whose
||| head this is (`probeTerm`).
export
probeName : Probe -> Name
probeName (ProbeBinder i) = MN (known KProbeBinder) (cast i)
probeName (ProbeHole i) = Nested (cast i, 0) (knownUN KProbeHole)
probeName (ProbeHoleFound i) = Nested (cast i, 0) (knownUN KProbeHoleFound)
probeName ProbeUnknown = MN (known KProbeUnknown) 0
probeName ProbeRuntime = MN (known KProbeRuntime) 0
probeName (ProbeRuntimeAt p) = MN (known KProbeRuntimeAt) (cast p)
probeName (ProbeStandIn k) = MN (known KProbeField) (cast k)
probeName (ProbePattern k) = Nested (cast k, 0) (knownUN KProbePattern)
probeName ProbeForm = MN (known KProbeForm) 0
probeName (ProbeAxis i _) = MN (known KProbeAxis) (cast i)
probeName (ProbeAxisAt j) = MN (known KProbeAxisAt) (cast j)
probeName (ProbeSize i) = MN (known KProbeSize) (cast i)
probeName (ProbePart i path) = Nested (cast i, 0) (along path (knownUN KProbeVar))
probeName (ProbeFormal j a) = Nested (cast j, cast a) (knownUN KProbeFormal)
probeName (ProbeFieldPath i (k ::: ks)) = Nested (cast i, 0) (along (k :: ks) (knownUN KProbeField))

-- The pairs a nested name nests around, the outermost first, and the
-- name inside them.
nesting : Name -> (List (Int, Int), Name)
nesting (Nested p inner) = let (ps, n) = nesting inner in (p :: ps, n)
nesting n = ([], n)

||| The probe a name is (`probeName`'s inverse); nothing for a name that is
||| none. The name's shape gives the numbers of the probes it can be, and
||| `probeName` decides which, so that no spelling is written twice. An
||| axis is not one name, and `probeOfTerm` reads it.
export
probeOf : Name -> Maybe Probe
probeOf n@(MN _ k) =
  List.find named [ProbeBinder (cast k), ProbeUnknown, ProbeRuntime, ProbeRuntimeAt (cast k),
                   ProbeStandIn (cast k), ProbeForm, ProbeAxisAt (cast k), ProbeSize (cast k)]
  where
    named : Probe -> Bool
    named p = probeName p == n
probeOf n@(Nested _ _) = List.find (\p => probeName p == n) (candidates (nesting n))
  where
    candidates : (List (Int, Int), Name) -> List Probe
    candidates ([(i, d)], _) =
      [ProbeHole (cast i), ProbeHoleFound (cast i), ProbePattern (cast i),
       ProbePart (cast i) [], ProbeFormal (cast i) (cast d)]
    candidates ((i, _) :: f :: fs, _) =
      [ProbePart (cast i) (map (cast . fst) (f :: fs)), ProbeFieldPath (cast i) (map (cast . fst) (f ::: fs))]
    candidates _ = []
probeOf _ = Nothing

||| A probe as a term: a reference to its name, bound or to a function as
||| each family has always been, and an axis its head applied to the
||| reference to its array parameter.
export
probeTerm : Probe -> Term vs
probeTerm p@(ProbeBinder _) = Ref EmptyFC Bound (probeName p)
probeTerm p@(ProbeHole _) = Ref EmptyFC Bound (probeName p)
probeTerm p@(ProbeHoleFound _) = Ref EmptyFC Bound (probeName p)
probeTerm p@ProbeUnknown = Ref EmptyFC Func (probeName p)
probeTerm p@ProbeRuntime = Ref EmptyFC Func (probeName p)
probeTerm p@(ProbeRuntimeAt _) = Ref EmptyFC Bound (probeName p)
probeTerm p@(ProbeStandIn _) = Ref EmptyFC Bound (probeName p)
probeTerm p@(ProbePattern _) = Ref EmptyFC Bound (probeName p)
probeTerm p@ProbeForm = Ref EmptyFC Func (probeName p)
probeTerm p@(ProbeAxis _ j) =
  App EmptyFC (Ref EmptyFC Func (probeName p)) (Ref EmptyFC Func (probeName (ProbeAxisAt j)))
probeTerm p@(ProbeAxisAt _) = Ref EmptyFC Func (probeName p)
probeTerm p@(ProbeSize _) = Ref EmptyFC Func (probeName p)
probeTerm p@(ProbePart _ _) = Ref EmptyFC Bound (probeName p)
probeTerm p@(ProbeFormal _ _) = Ref EmptyFC Bound (probeName p)
probeTerm p@(ProbeFieldPath _ _) = Ref EmptyFC Bound (probeName p)

||| The hole a skeleton cuts (`Readings.SkeletonOf`), stated where it is
||| made: a reference to a function by the runtime probe's name. `probeTerm`
||| is exported without its body, so a proof elsewhere sees which term the
||| hole is only here: a function reference, which no data constructor is,
||| so no skeleton of it exists, and which a reading takes as one leaf.
export
0 runtimeProbeTerm : probeTerm {vs} ProbeRuntime = Ref EmptyFC Func (probeName ProbeRuntime)
runtimeProbeTerm = Refl

||| The probe a term is (`probeTerm`'s inverse): a reference to a probe's
||| name, or an axis's two references; nothing for any other term.
export
probeOfTerm : Term vs -> Maybe Probe
probeOfTerm (Ref _ _ n) = probeOf n
probeOfTerm (App _ (Ref _ _ h) (Ref _ _ a)) = case (h, probeOf a) of
  (MN _ i, Just (ProbeAxisAt j)) =>
    let p = ProbeAxis (cast i) j in if probeName p == h then Just p else Nothing
  _ => Nothing
probeOfTerm _ = Nothing
