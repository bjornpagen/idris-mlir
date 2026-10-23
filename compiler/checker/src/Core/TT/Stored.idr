-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2026 Bjorn Pagen
||| A stored definition's terms: columns in preorder, frozen arrays of
||| `mlir-array`, so that every read of one is a pure read of an immutable
||| value.
|||
||| A definition is stored once it is read from a TTC. Its terms (its type,
||| its case tree's, its clauses' and their environments', its clause
||| patterns') are one arena, in which every distinct subterm is one node,
||| shared by each of its occurrences, its children the nodes made before
||| it. A shared node has no one location, so the locations are one more
||| column beside the nodes, one for each occurrence in the preorder of each
||| term's unfolding, the terms in the order they were frozen: no location
||| is lost and no node needs one. Definitions refer to one another by
||| name, never by a node of another arena, so nothing is shared across
||| definitions and no column grows under a read.
|||
||| A read relies on facts of the columns: a child is a node of the arena,
||| a node's slots are its own and its parts', its bound bounds its locals,
||| and a root's locations are in the column and its scope holds its
||| locals. Freezing lays every one, but the columns are `mlir-array`'s
||| arrays, of which a type knows nothing element by element, so `seal` and
||| `rootAt` decide them, once, where the columns are made, and every read
||| after takes them, erased, and checks nothing.
module Core.TT.Stored

import Core.TT

import Array

import Control.WellFounded
import Data.DPair
import Data.Fin
import Data.Fin.Properties
import Data.List
import Data.List.HasLength
import Data.Nat
import Data.So
import Data.SortedMap

import Libraries.Data.List.SizeOf

%default total

------------------------------------------------------------------------------
-- Nodes
------------------------------------------------------------------------------

||| A binder of a stored term without its location, its terms the nodes
||| below it.
public export
data SBinderOf : Type -> Type where
  BLam : RigCount -> PiInfo c -> (ty : c) -> SBinderOf c
  BLet : RigCount -> (val : c) -> (ty : c) -> SBinderOf c
  BPi : RigCount -> PiInfo c -> (ty : c) -> SBinderOf c
  BPVar : RigCount -> PiInfo c -> (ty : c) -> SBinderOf c
  BPLet : RigCount -> (val : c) -> (ty : c) -> SBinderOf c
  BPVTy : RigCount -> (ty : c) -> SBinderOf c

||| A node of a stored term without its location, its children the nodes
||| below it: by id while a definition is frozen, by position in its arena
||| once it is.
public export
data NodeOf : Type -> Type where
  SLocal : (isLet : Maybe Bool) -> (idx : Nat) -> NodeOf c
  SRef : NameType -> Name -> NodeOf c
  SMeta : Name -> Int -> List c -> NodeOf c
  SBind : Name -> SBinderOf c -> (scope : c) -> NodeOf c
  SApp : (fn : c) -> (arg : c) -> NodeOf c
  SAs : UseSide -> (as : c) -> (pat : c) -> NodeOf c
  SDelayed : LazyReason -> c -> NodeOf c
  SDelay : Delaying -> (ty : c) -> (arg : c) -> NodeOf c
  SForce : LazyReason -> c -> NodeOf c
  SPrim : Constant -> NodeOf c
  SErased : WhyErased c -> NodeOf c
  SType : Name -> NodeOf c

||| A binder of an arena of `n` nodes.
public export
SBinder : Nat -> Type
SBinder n = SBinderOf (Fin n)

||| A node of an arena of `n` nodes: each child is one of them.
public export
Node : Nat -> Type
Node n = NodeOf (Fin n)

traverseBinder : Applicative f => (a -> f b) -> SBinderOf a -> f (SBinderOf b)
traverseBinder g (BLam c p ty) = BLam c <$> traverse g p <*> g ty
traverseBinder g (BLet c v ty) = BLet c <$> g v <*> g ty
traverseBinder g (BPi c p ty) = BPi c <$> traverse g p <*> g ty
traverseBinder g (BPVar c p ty) = BPVar c <$> traverse g p <*> g ty
traverseBinder g (BPLet c v ty) = BPLet c <$> g v <*> g ty
traverseBinder g (BPVTy c ty) = BPVTy c <$> g ty

traverseNode : Applicative f => (a -> f b) -> NodeOf a -> f (NodeOf b)
traverseNode g (SLocal l i) = pure (SLocal l i)
traverseNode g (SRef nt n) = pure (SRef nt n)
traverseNode g (SMeta n i xs) = SMeta n i <$> traverse g xs
traverseNode g (SBind x b s) = SBind x <$> traverseBinder g b <*> g s
traverseNode g (SApp f a) = SApp <$> g f <*> g a
traverseNode g (SAs u a p) = SAs u <$> g a <*> g p
traverseNode g (SDelayed r t) = SDelayed r <$> g t
traverseNode g (SDelay d ty t) = SDelay d <$> g ty <*> g t
traverseNode g (SForce r t) = SForce r <$> g t
traverseNode g (SPrim k) = pure (SPrim k)
traverseNode g (SErased w) = SErased <$> traverse g w
traverseNode g (SType u) = pure (SType u)

-- The order of the table that finds a node already made: any total order
-- of a node's fields, its children by id. Two nodes it calls equal are
-- one node.

lexi : Ordering -> Lazy Ordering -> Ordering
lexi EQ next = next
lexi o _ = o

rigTag : RigCount -> Int
rigTag Rig0 = 0
rigTag Rig1 = 1
rigTag RigW = 2

nameTypeTag : NameType -> Int
nameTypeTag Bound = 0
nameTypeTag Func = 1
nameTypeTag (DataCon {}) = 2
nameTypeTag (TyCon {}) = 3

nameTypeOrder : NameType -> NameType -> Ordering
nameTypeOrder (DataCon t a) (DataCon t' a') = lexi (compare t t') (compare a a')
nameTypeOrder (TyCon a) (TyCon a') = compare a a'
nameTypeOrder x y = compare (nameTypeTag x) (nameTypeTag y)

piTag : PiInfo c -> Int
piTag Implicit = 0
piTag Explicit = 1
piTag AutoImplicit = 2
piTag (DefImplicit _) = 3

piOrder : PiInfo Nat -> PiInfo Nat -> Ordering
piOrder (DefImplicit x) (DefImplicit y) = compare x y
piOrder x y = compare (piTag x) (piTag y)

binderTag : SBinderOf c -> Int
binderTag (BLam {}) = 0
binderTag (BLet {}) = 1
binderTag (BPi {}) = 2
binderTag (BPVar {}) = 3
binderTag (BPLet {}) = 4
binderTag (BPVTy {}) = 5

-- A binder that holds a quantity, implicitness and type, compared in turn.
piBinderOrder : RigCount -> PiInfo Nat -> Nat -> RigCount -> PiInfo Nat -> Nat -> Ordering
piBinderOrder c p ty c' p' ty'
    = lexi (compare ty ty') (lexi (compare (rigTag c) (rigTag c')) (piOrder p p'))

-- A binder that holds a quantity, value and type, compared in turn.
valBinderOrder : RigCount -> Nat -> Nat -> RigCount -> Nat -> Nat -> Ordering
valBinderOrder c v ty c' v' ty'
    = lexi (compare v v') (lexi (compare ty ty') (compare (rigTag c) (rigTag c')))

binderOrder : SBinderOf Nat -> SBinderOf Nat -> Ordering
binderOrder (BLam c p ty) (BLam c' p' ty') = piBinderOrder c p ty c' p' ty'
binderOrder (BLet c v ty) (BLet c' v' ty') = valBinderOrder c v ty c' v' ty'
binderOrder (BPi c p ty) (BPi c' p' ty') = piBinderOrder c p ty c' p' ty'
binderOrder (BPVar c p ty) (BPVar c' p' ty') = piBinderOrder c p ty c' p' ty'
binderOrder (BPLet c v ty) (BPLet c' v' ty') = valBinderOrder c v ty c' v' ty'
binderOrder (BPVTy c ty) (BPVTy c' ty') = lexi (compare ty ty') (compare (rigTag c) (rigTag c'))
binderOrder x y = compare (binderTag x) (binderTag y)

useTag : UseSide -> Int
useTag UseLeft = 0
useTag UseRight = 1

lazyTag : LazyReason -> Int
lazyTag LInf = 0
lazyTag LLazy = 1
lazyTag LUnknown = 2

originTag : DelayOrigin -> Int
originTag InSource = 0
originTag ByElaborator = 1

delayingOrder : Delaying -> Delaying -> Ordering
delayingOrder d d'
    = lexi (compare (lazyTag d.reason) (lazyTag d'.reason))
           (compare (originTag d.origin) (originTag d'.origin))

erasedOrder : WhyErased Nat -> WhyErased Nat -> Ordering
erasedOrder Placeholder Placeholder = EQ
erasedOrder Impossible Impossible = EQ
erasedOrder (Dotted x) (Dotted y) = compare x y
erasedOrder x y = compare (whyTag x) (whyTag y)
  where
    whyTag : WhyErased Nat -> Int
    whyTag Placeholder = 0
    whyTag Impossible = 1
    whyTag (Dotted _) = 2

nodeTag : NodeOf c -> Int
nodeTag (SLocal {}) = 0
nodeTag (SRef {}) = 1
nodeTag (SMeta {}) = 2
nodeTag (SBind {}) = 3
nodeTag (SApp {}) = 4
nodeTag (SAs {}) = 5
nodeTag (SDelayed {}) = 6
nodeTag (SDelay {}) = 7
nodeTag (SForce {}) = 8
nodeTag (SPrim {}) = 9
nodeTag (SErased {}) = 10
nodeTag (SType {}) = 11

nodeOrder : NodeOf Nat -> NodeOf Nat -> Ordering
nodeOrder (SLocal l i) (SLocal l' i') = lexi (compare i i') (compare l l')
nodeOrder (SRef nt n) (SRef nt' n') = lexi (compare n n') (nameTypeOrder nt nt')
nodeOrder (SMeta n i xs) (SMeta n' i' xs')
    = lexi (compare i i') (lexi (compare n n') (compare xs xs'))
nodeOrder (SBind x b s) (SBind x' b' s')
    = lexi (compare s s') (lexi (binderOrder b b') (compare x x'))
nodeOrder (SApp f a) (SApp f' a') = lexi (compare f f') (compare a a')
nodeOrder (SAs u a p) (SAs u' a' p')
    = lexi (compare p p') (lexi (compare a a') (compare (useTag u) (useTag u')))
nodeOrder (SDelayed r t) (SDelayed r' t')
    = lexi (compare t t') (compare (lazyTag r) (lazyTag r'))
nodeOrder (SDelay d ty t) (SDelay d' ty' t')
    = lexi (compare t t') (lexi (compare ty ty') (delayingOrder d d'))
nodeOrder (SForce r t) (SForce r' t')
    = lexi (compare t t') (compare (lazyTag r) (lazyTag r'))
nodeOrder (SPrim k) (SPrim k') = compare k k'
nodeOrder (SErased w) (SErased w') = erasedOrder w w'
nodeOrder (SType u) (SType u') = compare u u'
nodeOrder x y = compare (nodeTag x) (nodeTag y)

Eq (NodeOf Nat) where
  x == y = nodeOrder x y == EQ

Ord (NodeOf Nat) where
  compare = nodeOrder

------------------------------------------------------------------------------
-- What an arena holds of each node
------------------------------------------------------------------------------

-- A node's location slots beyond its own, in the preorder `freeze` lays
-- them, given each child's (`sz`): a part's slots are a child's, and a
-- binder's own location is one more.

public export
piSlots : (Fin n -> Nat) -> PiInfo (Fin n) -> Nat
piSlots sz Implicit = 0
piSlots sz Explicit = 0
piSlots sz AutoImplicit = 0
piSlots sz (DefImplicit d) = sz d

public export
binderSlots : (Fin n -> Nat) -> SBinder n -> Nat
binderSlots sz (BLam _ p ty) = S (piSlots sz p + sz ty)
binderSlots sz (BLet _ v ty) = S (sz v + sz ty)
binderSlots sz (BPi _ p ty) = S (piSlots sz p + sz ty)
binderSlots sz (BPVar _ p ty) = S (piSlots sz p + sz ty)
binderSlots sz (BPLet _ v ty) = S (sz v + sz ty)
binderSlots sz (BPVTy _ ty) = S (sz ty)

public export
listSlots : (Fin n -> Nat) -> List (Fin n) -> Nat
listSlots sz [] = 0
listSlots sz (c :: cs) = sz c + listSlots sz cs

public export
partSlots : (Fin n -> Nat) -> Node n -> Nat
partSlots sz (SLocal _ _) = 0
partSlots sz (SRef _ _) = 0
partSlots sz (SMeta _ _ xs) = listSlots sz xs
partSlots sz (SBind _ b sc) = binderSlots sz b + sz sc
partSlots sz (SApp f x) = sz f + sz x
partSlots sz (SAs _ a p) = sz a + sz p
partSlots sz (SDelayed _ t) = sz t
partSlots sz (SDelay _ ty t) = sz ty + sz t
partSlots sz (SForce _ t) = sz t
partSlots sz (SPrim _) = 0
partSlots sz (SErased Placeholder) = 0
partSlots sz (SErased Impossible) = 0
partSlots sz (SErased (Dotted t)) = sz t
partSlots sz (SType _) = 0

-- What a node's bound says of it, given each child's (`bd`): every local
-- it holds is below the number of variables of any scope at least that
-- long. A local is below it, a child's bound is at most it, and a
-- binder's scope, one variable deeper, is bound by one more.

public export
piBounded : (Fin n -> Nat) -> PiInfo (Fin n) -> Nat -> Type
piBounded bd Implicit b = ()
piBounded bd Explicit b = ()
piBounded bd AutoImplicit b = ()
piBounded bd (DefImplicit d) b = LTE (bd d) b

public export
binderBounded : (Fin n -> Nat) -> SBinder n -> Nat -> Type
binderBounded bd (BLam _ p ty) b = (piBounded bd p b, LTE (bd ty) b)
binderBounded bd (BLet _ v ty) b = (LTE (bd v) b, LTE (bd ty) b)
binderBounded bd (BPi _ p ty) b = (piBounded bd p b, LTE (bd ty) b)
binderBounded bd (BPVar _ p ty) b = (piBounded bd p b, LTE (bd ty) b)
binderBounded bd (BPLet _ v ty) b = (LTE (bd v) b, LTE (bd ty) b)
binderBounded bd (BPVTy _ ty) b = LTE (bd ty) b

public export
listBounded : (Fin n -> Nat) -> List (Fin n) -> Nat -> Type
listBounded bd [] b = ()
listBounded bd (c :: cs) b = (LTE (bd c) b, listBounded bd cs b)

public export
bounded : (Fin n -> Nat) -> Node n -> Nat -> Type
bounded bd (SLocal _ idx) b = LT idx b
bounded bd (SRef _ _) b = ()
bounded bd (SMeta _ _ xs) b = listBounded bd xs b
bounded bd (SBind _ bnd sc) b = (binderBounded bd bnd b, LTE (bd sc) (S b))
bounded bd (SApp f x) b = (LTE (bd f) b, LTE (bd x) b)
bounded bd (SAs _ a p) b = (LTE (bd a) b, LTE (bd p) b)
bounded bd (SDelayed _ t) b = LTE (bd t) b
bounded bd (SDelay _ ty t) b = (LTE (bd ty) b, LTE (bd t) b)
bounded bd (SForce _ t) b = LTE (bd t) b
bounded bd (SPrim _) b = ()
bounded bd (SErased Placeholder) b = ()
bounded bd (SErased Impossible) b = ()
bounded bd (SErased (Dotted t)) b = LTE (bd t) b
bounded bd (SType _) b = ()

-- What a sealed arena holds of its node at `c`: its slots are its own and
-- its parts', and its bound bounds its locals and its children's.
0 Laid : Vector n (Node n) -> Vector n Nat -> Vector n Nat -> Fin n -> Type
Laid nodes slots bounds c
    = (slots !! [<c] = S (partSlots (\d => slots !! [<d]) (nodes !! [<c])),
       bounded (\d => bounds !! [<d]) (nodes !! [<c]) (bounds !! [<c]))

------------------------------------------------------------------------------
-- The arena
------------------------------------------------------------------------------

||| One definition's terms. `nodes` holds each distinct subterm once, a
||| child before every node above it; `slots` holds, for each node, the
||| location slots of its unfolding (one for each occurrence of a node in
||| it, and one more for each binder, which has a location of its own);
||| `bounds` holds, for each node, the fewest variables a scope it is read
||| in has; and `locs` holds the locations, in the preorder of each term's
||| unfolding, the terms in the order they were frozen. What it holds of
||| each node (`Laid`) is decided once, as it is sealed, so a read through
||| it checks nothing.
export
record Arena where
  constructor MkArena
  nodeCount : Nat
  nodes : Vector nodeCount (Node nodeCount)
  slots : Vector nodeCount Nat
  bounds : Vector nodeCount Nat
  locCount : Nat
  locs : Vector locCount FC
  0 laid : (c : Fin nodeCount) -> Laid nodes slots bounds c

nodeAt : (a : Arena) -> Fin (nodeCount a) -> Node (nodeCount a)
nodeAt a i = nodes a !! [<i]

sizeAt : (a : Arena) -> Fin (nodeCount a) -> Nat
sizeAt a i = slots a !! [<i]

boundAt : (a : Arena) -> Fin (nodeCount a) -> Nat
boundAt a i = bounds a !! [<i]

0 sized : (a : Arena) -> (c : Fin (nodeCount a)) ->
          sizeAt a c = S (partSlots (sizeAt a) (nodeAt a c))
sized a c = fst (laid a c)

0 boundedAt : (a : Arena) -> (c : Fin (nodeCount a)) ->
              bounded (boundAt a) (nodeAt a c) (boundAt a c)
boundedAt a c = snd (laid a c)

||| A stored term in scope `vars`: its arena, its node, the slot its first
||| location is at, and, as sealing found them, that its unfolding's
||| locations are in the arena and that the scope bounds its locals. Only
||| `rootAt` makes one.
export
data Root : Scoped where
  MkRoot : (arena : Arena) -> (node : Fin (nodeCount arena)) -> (slot : Nat) ->
           (0 fits : LTE (slot + sizeAt arena node) (locCount arena)) ->
           (0 scoped : LTE (boundAt arena node) (length vars)) -> Root vars

------------------------------------------------------------------------------
-- Columns
------------------------------------------------------------------------------

||| A column being built: its cells in the order they were added, its
||| length in its type.
data Column : Nat -> Type -> Type where
  NoCells : Column Z a
  Then : Column n a -> a -> Column (S n) a

||| A column's cells in the order they were added, and that there are `k`
||| of them, which only the type says.
cells : Column k a -> Subset (List a) (\xs => length xs = k)
cells col = let Element xs same = after col [] in
                Element xs (trans same (plusZeroRightNeutral k))
  where
    after : Column j a -> (acc : List a) -> Subset (List a) (\xs => length xs = j + length acc)
    after NoCells acc = Element acc Refl
    after {j = S i} (Then col x) acc
        = let Element xs same = after col (x :: acc) in
              Element xs (trans same (sym (plusSuccRightSucc i (length acc))))

||| A column frozen, its cells in the order they were added.
column : Column k a -> Vector k a
column col = let Element xs same = cells col in
                 replace {p = \m => Vector m a} same (Array.fromList xs)

||| Every node's children as positions among `n` nodes, when each is one.
inArena : (n : Nat) -> Column k (NodeOf Nat) -> Maybe (Column k (Node n))
inArena n NoCells = Just NoCells
inArena n (Then col x) = [| Then (inArena n col) (traverseNode (checkIndex n) x) |]

------------------------------------------------------------------------------
-- Deciding what an arena holds
------------------------------------------------------------------------------

-- A fact decided at run time, its proof erased.
data Holds : Type -> Type where
  Holding : (0 _ : p) -> Holds p

both : Maybe (Holds p) -> Maybe (Holds q) -> Maybe (Holds (p, q))
both (Just (Holding x)) (Just (Holding y)) = Just (Holding (x, y))
both _ _ = Nothing

0 equalReflects : (x, y : Nat) -> So (x == y) -> x = y
equalReflects Z Z _ = Refl
equalReflects (S x) (S y) same = cong S (equalReflects x y same)
equalReflects Z (S _) Oh impossible
equalReflects (S _) Z Oh impossible

-- One comparison each, the program's own, its proof erased.

sameAs : (x, y : Nat) -> Maybe (Holds (x = y))
sameAs x y = case choose (x == y) of
  Left same => Just (Holding (equalReflects x y same))
  Right _ => Nothing

atMost : (x, y : Nat) -> Maybe (Holds (LTE x y))
atMost x y = case choose (x < S y) of
  Left below => Just (Holding (fromLteSucc (ltOpReflectsLT x (S y) below)))
  Right _ => Nothing

piHolds : (bd : Fin n -> Nat) -> (p : PiInfo (Fin n)) -> (b : Nat) -> Maybe (Holds (piBounded bd p b))
piHolds bd Implicit b = Just (Holding ())
piHolds bd Explicit b = Just (Holding ())
piHolds bd AutoImplicit b = Just (Holding ())
piHolds bd (DefImplicit d) b = atMost (bd d) b

binderHolds : (bd : Fin n -> Nat) -> (bnd : SBinder n) -> (b : Nat) -> Maybe (Holds (binderBounded bd bnd b))
binderHolds bd (BLam _ p ty) b = both (piHolds bd p b) (atMost (bd ty) b)
binderHolds bd (BLet _ v ty) b = both (atMost (bd v) b) (atMost (bd ty) b)
binderHolds bd (BPi _ p ty) b = both (piHolds bd p b) (atMost (bd ty) b)
binderHolds bd (BPVar _ p ty) b = both (piHolds bd p b) (atMost (bd ty) b)
binderHolds bd (BPLet _ v ty) b = both (atMost (bd v) b) (atMost (bd ty) b)
binderHolds bd (BPVTy _ ty) b = atMost (bd ty) b

listHolds : (bd : Fin n -> Nat) -> (cs : List (Fin n)) -> (b : Nat) -> Maybe (Holds (listBounded bd cs b))
listHolds bd [] b = Just (Holding ())
listHolds bd (c :: cs) b = both (atMost (bd c) b) (listHolds bd cs b)

boundHolds : (bd : Fin n -> Nat) -> (nd : Node n) -> (b : Nat) -> Maybe (Holds (bounded bd nd b))
boundHolds bd (SLocal _ idx) b = atMost (S idx) b
boundHolds bd (SRef _ _) b = Just (Holding ())
boundHolds bd (SMeta _ _ xs) b = listHolds bd xs b
boundHolds bd (SBind _ bnd sc) b = both (binderHolds bd bnd b) (atMost (bd sc) (S b))
boundHolds bd (SApp f x) b = both (atMost (bd f) b) (atMost (bd x) b)
boundHolds bd (SAs _ a p) b = both (atMost (bd a) b) (atMost (bd p) b)
boundHolds bd (SDelayed _ t) b = atMost (bd t) b
boundHolds bd (SDelay _ ty t) b = both (atMost (bd ty) b) (atMost (bd t) b)
boundHolds bd (SForce _ t) b = atMost (bd t) b
boundHolds bd (SPrim _) b = Just (Holding ())
boundHolds bd (SErased Placeholder) b = Just (Holding ())
boundHolds bd (SErased Impossible) b = Just (Holding ())
boundHolds bd (SErased (Dotted t)) b = atMost (bd t) b
boundHolds bd (SType _) b = Just (Holding ())

laidHolds : (nodes : Vector n (Node n)) -> (slots, bounds : Vector n Nat) -> (c : Fin n) ->
            Maybe (Holds (Laid nodes slots bounds c))
laidHolds nodes slots bounds c
    = both (sameAs (slots !! [<c]) (S (partSlots (\d => slots !! [<d]) (nodes !! [<c]))))
           (boundHolds (\d => bounds !! [<d]) (nodes !! [<c]) (bounds !! [<c]))

0 finToNatSame : (c, d : Fin n) -> finToNat c = finToNat d -> c = d
finToNatSame FZ FZ _ = Refl
finToNatSame (FS c) (FS d) same = cong FS (finToNatSame c d (injective same))
finToNatSame FZ (FS _) Refl impossible
finToNatSame (FS _) FZ Refl impossible

0 natToFinToNat : (i : Nat) -> (0 below : LT i n) -> finToNat (natToFinLT i {prf = below}) = i
natToFinToNat Z (LTESucc _) = Refl
natToFinToNat (S k) (LTESucc below) = cong S (natToFinToNat k below)

0 atOrAbove : LTE i m -> Either (i = m) (LTE (S i) m)
atOrAbove {m = Z} LTEZero = Left Refl
atOrAbove {m = S _} LTEZero = Right (LTESucc LTEZero)
atOrAbove (LTESucc le) = case atOrAbove le of
  Left same => Left (cong S same)
  Right above => Right (LTESucc above)

-- `p` at each position, decided at each from `i` down, the positions from
-- `i` up already decided (`above`): one pass over the positions.
everyBelow : {0 p : Fin n -> Type} -> ((c : Fin n) -> Maybe (Holds (p c))) ->
             (i : Nat) -> (0 _ : LTE i n) ->
             (0 above : (c : Fin n) -> LTE i (finToNat c) -> p c) ->
             Maybe (Holds ((c : Fin n) -> p c))
everyBelow decide Z _ above = Just (Holding (\c => above c LTEZero))
everyBelow decide (S i) fits above
    = case decide (natToFinLT i {prf = fits}) of
           Nothing => Nothing
           Just (Holding here) =>
             everyBelow decide i (lteSuccLeft fits) (\c, le => case atOrAbove le of
               Left same =>
                 replace {p} (finToNatSame _ c (trans (natToFinToNat i fits) same)) here
               Right higher => above c higher)

------------------------------------------------------------------------------
-- Freezing
------------------------------------------------------------------------------

||| What freezing one definition has made so far: the nodes, by id, each
||| with the location slots of its unfolding and its bound; the table that
||| finds a node already made; and the locations, in preorder.
record Freezing where
  constructor MkFreezing
  made : Nat
  built : Column made (NodeOf Nat)
  sizes : Column made Nat
  bounds : Column made Nat
  seen : SortedMap (NodeOf Nat) Nat
  located : Nat
  locations : Column located FC

initial : Freezing
initial = MkFreezing Z NoCells NoCells NoCells SortedMap.empty Z NoCells

||| Freezing one definition's terms into one arena.
export
record Freeze (a : Type) where
  constructor MkFreeze
  step : Freezing -> (Freezing, a)

export
Functor Freeze where
  map f (MkFreeze g) = MkFreeze (\st => let (st', x) = g st in (st', f x))

export
Applicative Freeze where
  pure x = MkFreeze (\st => (st, x))
  MkFreeze f <*> MkFreeze g
      = MkFreeze (\st => let (st1, h) = f st
                             (st2, x) = g st1 in
                             (st2, h x))

export
Monad Freeze where
  MkFreeze g >>= k = MkFreeze (\st => let (st1, x) = g st in step (k x) st1)

||| A frozen term's place before its arena is sealed: its node's id, its
||| first location's slot, and the number of variables of its scope.
export
data Pos : Scoped where
  MkPos : (node : Nat) -> (slot : Nat) -> (scope : Nat) -> (0 _ : HasLength scope vars) -> Pos vars

-- What freezing a part of a term gives: the state after it, the part, the
-- location slots of its unfolding, and its bound: the fewest variables a
-- scope it is read in has.
record Part (a : Type) where
  constructor MkPart
  after : Freezing
  part : a
  extent : Nat
  bound : Nat

-- The node's id: the one already made if there is one, or a new one.
intern : NodeOf Nat -> Nat -> Nat -> Freezing -> Part Nat
intern n sz bd st
    = case SortedMap.lookup n st.seen of
           Just i => MkPart st i sz bd
           Nothing =>
             MkPart (MkFreezing (S st.made) (Then st.built n) (Then st.sizes sz) (Then st.bounds bd)
                                (SortedMap.insert n st.made st.seen)
                                st.located st.locations)
                    st.made sz bd

-- An occurrence's location, the next in preorder.
locate : FC -> Freezing -> Freezing
locate fc st
    = MkFreezing st.made st.built st.sizes st.bounds st.seen (S st.located) (Then st.locations fc)

-- Each kind of node that holds terms is frozen by a function of its own,
-- so that every recursive call is on a part of its argument. A node's
-- location is recorded before its children's, and a binder's after its
-- node's, which is the preorder `decode` reads. A node's bound is the
-- most its parts need, a local's one past its index, and a scope's one
-- less than its body's, which counts its binder's variable.
mutual
  frozenPi : PiInfo (Term vars) -> Freezing -> Part (PiInfo Nat)
  frozenPi Implicit st = MkPart st Implicit 0 0
  frozenPi Explicit st = MkPart st Explicit 0 0
  frozenPi AutoImplicit st = MkPart st AutoImplicit 0 0
  frozenPi (DefImplicit t) st
      = let MkPart st1 i n b = frozenTerm t st in MkPart st1 (DefImplicit i) n b

  frozenBinder : Binder (Term vars) -> Freezing -> Part (SBinderOf Nat)
  frozenBinder (Lam fc c p ty) st
      = let MkPart st1 p' np bp = frozenPi p (locate fc st)
            MkPart st2 ty' nt bt = frozenTerm ty st1 in
            MkPart st2 (BLam c p' ty') (S (np + nt)) (maximum bp bt)
  frozenBinder (Let fc c v ty) st
      = let MkPart st1 v' nv bv = frozenTerm v (locate fc st)
            MkPart st2 ty' nt bt = frozenTerm ty st1 in
            MkPart st2 (BLet c v' ty') (S (nv + nt)) (maximum bv bt)
  frozenBinder (Pi fc c p ty) st
      = let MkPart st1 p' np bp = frozenPi p (locate fc st)
            MkPart st2 ty' nt bt = frozenTerm ty st1 in
            MkPart st2 (BPi c p' ty') (S (np + nt)) (maximum bp bt)
  frozenBinder (PVar fc c p ty) st
      = let MkPart st1 p' np bp = frozenPi p (locate fc st)
            MkPart st2 ty' nt bt = frozenTerm ty st1 in
            MkPart st2 (BPVar c p' ty') (S (np + nt)) (maximum bp bt)
  frozenBinder (PLet fc c v ty) st
      = let MkPart st1 v' nv bv = frozenTerm v (locate fc st)
            MkPart st2 ty' nt bt = frozenTerm ty st1 in
            MkPart st2 (BPLet c v' ty') (S (nv + nt)) (maximum bv bt)
  frozenBinder (PVTy fc c ty) st
      = let MkPart st1 ty' nt bt = frozenTerm ty (locate fc st) in
            MkPart st1 (BPVTy c ty') (S nt) bt

  frozenTerms : List (Term vars) -> Freezing -> Part (List Nat)
  frozenTerms [] st = MkPart st [] 0 0
  frozenTerms (t :: ts) st
      = let MkPart st1 i n b = frozenTerm t st
            MkPart st2 is ns bs = frozenTerms ts st1 in
            MkPart st2 (i :: is) (n + ns) (maximum b bs)

  -- A node with one child: its location, then the child.
  frozenOne : FC -> (Nat -> NodeOf Nat) -> Term vars -> Freezing -> Part Nat
  frozenOne fc mk t st
      = let MkPart st1 i n b = frozenTerm t (locate fc st) in
            intern (mk i) (S n) b st1

  -- A node with two children: its location, then each child in turn.
  frozenTwo : FC -> (Nat -> Nat -> NodeOf Nat) -> Term vars -> Term vars -> Freezing -> Part Nat
  frozenTwo fc mk t u st
      = let MkPart st1 i n b = frozenTerm t (locate fc st)
            MkPart st2 j m c = frozenTerm u st1 in
            intern (mk i j) (S (n + m)) (maximum b c) st2

  frozenTerm : Term vars -> Freezing -> Part Nat
  frozenTerm (Local fc l idx _) st = intern (SLocal l idx) 1 (S idx) (locate fc st)
  frozenTerm (Ref fc nt n) st = intern (SRef nt n) 1 0 (locate fc st)
  frozenTerm (Meta fc n i args) st
      = let MkPart st1 is ns bs = frozenTerms args (locate fc st) in
            intern (SMeta n i is) (S ns) bs st1
  frozenTerm (Bind fc x b sc) st
      = let MkPart st1 b' nb bb = frozenBinder b (locate fc st)
            MkPart st2 s ns bs = frozenTerm sc st1 in
            intern (SBind x b' s) (S (nb + ns)) (maximum bb (pred bs)) st2
  frozenTerm (App fc f a) st = frozenTwo fc SApp f a st
  frozenTerm (As fc u a p) st = frozenTwo fc (SAs u) a p st
  frozenTerm (TDelayed fc r t) st = frozenOne fc (SDelayed r) t st
  frozenTerm (TDelay fc d ty t) st = frozenTwo fc (SDelay d) ty t st
  frozenTerm (TForce fc r t) st = frozenOne fc (SForce r) t st
  frozenTerm (PrimVal fc k) st = intern (SPrim k) 1 0 (locate fc st)
  frozenTerm (Erased fc Placeholder) st = intern (SErased Placeholder) 1 0 (locate fc st)
  frozenTerm (Erased fc Impossible) st = intern (SErased Impossible) 1 0 (locate fc st)
  frozenTerm (Erased fc (Dotted t)) st = frozenOne fc (\i => SErased (Dotted i)) t st
  frozenTerm (TType fc u) st = intern (SType u) 1 0 (locate fc st)

||| A term frozen into the definition's arena, every subterm the arena
||| already holds shared: its place there, made a root once the arena is
||| sealed.
export
freeze : SizeOf vars -> Term vars -> Freeze (Pos vars)
freeze s tm = MkFreeze (\st => let MkPart st' i _ _ = frozenTerm tm st in
                                   (st', MkPos i st.located (size s) (hasLength s)))

||| The arena a freezing made, and what it gave, each place in it still to
||| be made a root of that arena (`rootAt`). Nothing when a node's child is
||| not among the nodes made, or a node's slots or bound are not what its
||| parts make them: interning a child before its parent, and counting each
||| node's slots and bound from its children's, makes either impossible.
export
seal : Freeze a -> Maybe (Arena, a)
seal (MkFreeze run)
    = let (st, x) = run initial in
      do ns <- inArena st.made st.built
         let nodes = column ns
         let slots = column st.sizes
         let bounds = column st.bounds
         Holding laid <- everyBelow (laidHolds nodes slots bounds) st.made reflexive
                                    (\c, above => void (succNotLTEpred (transitive (elemSmallerThanBound c) above)))
         pure (MkArena st.made nodes slots bounds st.located (column st.locations) laid, x)

||| The root of an arena at a place its own freezing gave: the arena and the
||| places `seal` gives together. Nothing for a place outside the arena, or
||| whose term's locations or locals the arena does not hold as its scope
||| needs, which only another freezing gives.
export
rootAt : (a : Arena) -> Pos vars -> Maybe (Root vars)
rootAt {vars} a (MkPos n slot scope len)
    = do c <- checkIndex (nodeCount a) n
         Holding fits <- atMost (slot + sizeAt a c) (locCount a)
         Holding scoped <- atMost (boundAt a c) scope
         pure (MkRoot a c slot fits
                 (replace {p = LTE (boundAt a c)} (hasLengthUnique len (hasLength vars)) scoped))

------------------------------------------------------------------------------
-- Decoding
------------------------------------------------------------------------------

-- The name at a place below the length of a scope. The bound is the
-- evidence `LT`, whose steps follow the place down the scope.
0 nameBelow : {0 vars : List a} -> {0 idx : Nat} -> HasLength n vars -> LT idx n -> a
nameBelow Z LTEZero impossible
nameBelow Z (LTESucc _) impossible
nameBelow {vars = x :: _} {idx = Z} (S _) _ = x
nameBelow {idx = S k} (S p) (LTESucc lt) = nameBelow p lt

-- A place below the length of a scope is a variable of it.
0 inScope : {0 idx : Nat} -> (h : HasLength n vars) -> (lt : LT idx n) ->
            IsVar (nameBelow h lt) idx vars
inScope Z LTEZero impossible
inScope Z (LTESucc _) impossible
inScope {idx = Z} (S _) _ = First
inScope {idx = S k} (S p) (LTESucc lt) = Later (inScope p lt)

-- A local variable, below the length of its scope, as the arena's bounds
-- say: its proof is that bound, erased.
decodeLocal : FC -> Maybe Bool -> (idx : Nat) -> (s : SizeOf vars) -> (0 _ : LT idx (size s)) ->
              Term (vars ++ outer)
decodeLocal fc l idx s below
    = Local {name = nameBelow (hasLength s) below} fc l idx
            (embedIsVar (inScope (hasLength s) below))

-- How a node's location slots sit in the column. A node of `S r` slots at
-- `slot` has its own slot inside the column, and its parts' after it; two
-- parts laid one after the other from `o` are each inside what both fill;
-- and each part of a node has fewer slots than the node.

0 ownSlot : LTE (slot + S r) l -> (LT slot l, LTE (S slot + r) l)
ownSlot fits = let fits' = replace {p = \k => LTE k l} (sym (plusSuccRightSucc slot r)) fits in
                   (transitive (LTESucc (lteAddRight slot)) fits', fits')

0 twoParts : LTE (o + (x + y)) l -> (LTE (o + x) l, LTE ((o + x) + y) l)
twoParts fits = let fits' = replace {p = \k => LTE k l} (plusAssociative o x y) fits in
                    (transitive (lteAddRight (o + x)) fits', fits')

0 firstSmaller : m = S (x + y) -> LT x m
firstSmaller same = replace {p = LT x} (sym same) (LTESucc (lteAddRight x))

0 secondSmaller : m = S (x + y) -> LT y m
secondSmaller same
    = replace {p = LT y} (sym same) (LTESucc (replace {p = LTE y} (plusCommutative y x) (lteAddRight y)))

0 onlySmaller : m = S x -> LT x m
onlySmaller same = replace {p = LT x} (sym same) reflexive

0 inside : LT x y -> LT y m -> LT x m
inside lt lt' = transitive lt (lteSuccLeft lt')

0 partOf : LTE x y -> LT y m -> LT x m
partOf le lt = transitive (LTESucc le) lt

0 sizeSuc : {0 x : t} -> {0 vars : List t} -> (s : SizeOf vars) -> size (suc {a = x} s) = S (size s)
sizeSuc (MkSizeOf _ _) = Refl

0 atLength : (s : SizeOf vars) -> size s = length vars
atLength {vars} (MkSizeOf _ h) = hasLengthUnique h (hasLength vars)

-- Decoding a stored term is a recursion over the location slots of the
-- unfolding left to decode: each child has fewer than the node above it,
-- as the arena holds, so the recursion descends a measure. A child's first
-- location follows the locations of the children before it, whose counts
-- the slots column gives; each location read is in the column, and each
-- local is in its scope, as the arena and the root hold.
mutual
  decodeChild : (a : Arena) -> (s : SizeOf vars) -> (0 m : Nat) -> (0 _ : Accessible LT m) ->
                (c : Fin (nodeCount a)) -> (0 _ : LT (sizeAt a c) m) -> (slot : Nat) ->
                (0 _ : LTE (slot + sizeAt a c) (locCount a)) ->
                (0 _ : LTE (boundAt a c) (size s)) -> Term (vars ++ outer)
  decodeChild a s m (Access rec) c lt slot fits within
      = decodeNode a s c (rec (sizeAt a c) lt) slot fits within

  decodeAll : (a : Arena) -> (s : SizeOf vars) -> (0 m : Nat) -> (0 _ : Accessible LT m) ->
              (0 b : Nat) -> (0 _ : LTE b (size s)) ->
              (cs : List (Fin (nodeCount a))) -> (0 _ : LT (listSlots (sizeAt a) cs) m) ->
              (0 _ : listBounded (boundAt a) cs b) -> (slot : Nat) ->
              (0 _ : LTE (slot + listSlots (sizeAt a) cs) (locCount a)) ->
              List (Term (vars ++ outer))
  decodeAll a s m acc b within [] _ _ slot _ = []
  decodeAll a s m acc b within (c :: cs) lt held slot fits
      = let 0 ps = twoParts fits
            0 ltc = partOf (lteAddRight (sizeAt a c)) lt
            0 ltcs = partOf (replace {p = LTE (listSlots (sizeAt a) cs)}
                                     (plusCommutative (listSlots (sizeAt a) cs) (sizeAt a c))
                                     (lteAddRight (listSlots (sizeAt a) cs))) lt in
            decodeChild a s m acc c ltc slot (fst ps) (transitive (fst held) within)
              :: decodeAll a s m acc b within cs ltcs (snd held) (slot + sizeAt a c) (snd ps)

  decodePi : (a : Arena) -> (s : SizeOf vars) -> (0 m : Nat) -> (0 _ : Accessible LT m) ->
             (0 b : Nat) -> (0 _ : LTE b (size s)) ->
             (p : PiInfo (Fin (nodeCount a))) -> (0 _ : LT (piSlots (sizeAt a) p) m) ->
             (0 _ : piBounded (boundAt a) p b) -> (slot : Nat) ->
             (0 _ : LTE (slot + piSlots (sizeAt a) p) (locCount a)) ->
             PiInfo (Term (vars ++ outer))
  decodePi a s m acc b within Implicit _ _ slot _ = Implicit
  decodePi a s m acc b within Explicit _ _ slot _ = Explicit
  decodePi a s m acc b within AutoImplicit _ _ slot _ = AutoImplicit
  decodePi a s m acc b within (DefImplicit d) lt held slot fits
      = DefImplicit (decodeChild a s m acc d lt slot fits (transitive held within))

  -- A binder from its own location's slot, its parts after it.
  decodeBinder : (a : Arena) -> (s : SizeOf vars) -> (0 m : Nat) -> (0 _ : Accessible LT m) ->
                 (0 b : Nat) -> (0 _ : LTE b (size s)) ->
                 (bnd : SBinder (nodeCount a)) -> (0 _ : LT (binderSlots (sizeAt a) bnd) m) ->
                 (0 _ : binderBounded (boundAt a) bnd b) -> (slot : Nat) ->
                 (0 _ : LTE (slot + binderSlots (sizeAt a) bnd) (locCount a)) ->
                 Binder (Term (vars ++ outer))
  decodeBinder a s m acc b within (BLam c p ty) lt held slot fits
      = let 0 own = ownSlot fits
            0 ps = twoParts {o = S slot} (snd own) in
            Lam (locs a !! [<natToFinLT slot {prf = fst own}]) c
                (decodePi a s m acc b within p (inside (firstSmaller Refl) lt) (fst held) (S slot) (fst ps))
                (decodeChild a s m acc ty (inside (secondSmaller Refl) lt) (S slot + piSlots (sizeAt a) p)
                             (snd ps) (transitive (snd held) within))
  decodeBinder a s m acc b within (BLet c v ty) lt held slot fits
      = let 0 own = ownSlot fits
            0 ps = twoParts {o = S slot} (snd own) in
            Let (locs a !! [<natToFinLT slot {prf = fst own}]) c
                (decodeChild a s m acc v (inside (firstSmaller Refl) lt) (S slot) (fst ps)
                             (transitive (fst held) within))
                (decodeChild a s m acc ty (inside (secondSmaller Refl) lt) (S slot + sizeAt a v)
                             (snd ps) (transitive (snd held) within))
  decodeBinder a s m acc b within (BPi c p ty) lt held slot fits
      = let 0 own = ownSlot fits
            0 ps = twoParts {o = S slot} (snd own) in
            Pi (locs a !! [<natToFinLT slot {prf = fst own}]) c
               (decodePi a s m acc b within p (inside (firstSmaller Refl) lt) (fst held) (S slot) (fst ps))
               (decodeChild a s m acc ty (inside (secondSmaller Refl) lt) (S slot + piSlots (sizeAt a) p)
                            (snd ps) (transitive (snd held) within))
  decodeBinder a s m acc b within (BPVar c p ty) lt held slot fits
      = let 0 own = ownSlot fits
            0 ps = twoParts {o = S slot} (snd own) in
            PVar (locs a !! [<natToFinLT slot {prf = fst own}]) c
                 (decodePi a s m acc b within p (inside (firstSmaller Refl) lt) (fst held) (S slot) (fst ps))
                 (decodeChild a s m acc ty (inside (secondSmaller Refl) lt) (S slot + piSlots (sizeAt a) p)
                              (snd ps) (transitive (snd held) within))
  decodeBinder a s m acc b within (BPLet c v ty) lt held slot fits
      = let 0 own = ownSlot fits
            0 ps = twoParts {o = S slot} (snd own) in
            PLet (locs a !! [<natToFinLT slot {prf = fst own}]) c
                 (decodeChild a s m acc v (inside (firstSmaller Refl) lt) (S slot) (fst ps)
                              (transitive (fst held) within))
                 (decodeChild a s m acc ty (inside (secondSmaller Refl) lt) (S slot + sizeAt a v)
                              (snd ps) (transitive (snd held) within))
  decodeBinder a s m acc b within (BPVTy c ty) lt held slot fits
      = let 0 own = ownSlot fits in
            PVTy (locs a !! [<natToFinLT slot {prf = fst own}]) c
                 (decodeChild a s m acc ty (inside (onlySmaller Refl) lt) (S slot) (snd own)
                              (transitive held within))

  decodeNode : (a : Arena) -> (s : SizeOf vars) -> (c : Fin (nodeCount a)) ->
               (0 _ : Accessible LT (sizeAt a c)) -> (slot : Nat) ->
               (0 _ : LTE (slot + sizeAt a c) (locCount a)) ->
               (0 _ : LTE (boundAt a c) (size s)) -> Term (vars ++ outer)
  decodeNode a s c acc slot fits within
      = decodeAt a s (sizeAt a c) acc (boundAt a c) within slot fits (nodeAt a c) (sized a c) (boundedAt a c)

  -- A node, at its first location's slot, of `m` slots and bound `b`.
  decodeAt : (a : Arena) -> (s : SizeOf vars) -> (0 m : Nat) -> (0 _ : Accessible LT m) ->
             (0 b : Nat) -> (0 _ : LTE b (size s)) -> (slot : Nat) ->
             (0 _ : LTE (slot + m) (locCount a)) ->
             (nd : Node (nodeCount a)) -> (0 _ : m = S (partSlots (sizeAt a) nd)) ->
             (0 _ : bounded (boundAt a) nd b) -> Term (vars ++ outer)
  decodeAt a s m acc b within slot fits (SLocal l idx) laid held
      = let 0 own = ownSlot (replace {p = \k => LTE (slot + k) (locCount a)} laid fits) in
            decodeLocal (locs a !! [<natToFinLT slot {prf = fst own}]) l idx s (transitive held within)
  decodeAt a s m acc b within slot fits (SRef nt n) laid held
      = let 0 own = ownSlot (replace {p = \k => LTE (slot + k) (locCount a)} laid fits) in
            Ref (locs a !! [<natToFinLT slot {prf = fst own}]) nt n
  decodeAt a s m acc b within slot fits (SMeta n i xs) laid held
      = let 0 own = ownSlot (replace {p = \k => LTE (slot + k) (locCount a)} laid fits) in
            Meta (locs a !! [<natToFinLT slot {prf = fst own}]) n i
                 (decodeAll a s m acc b within xs (onlySmaller laid) held (S slot) (snd own))
  decodeAt a s m acc b within slot fits (SBind x bnd sc) laid held
      = let 0 own = ownSlot (replace {p = \k => LTE (slot + k) (locCount a)} laid fits)
            0 ps = twoParts {o = S slot} (snd own) in
            Bind (locs a !! [<natToFinLT slot {prf = fst own}]) x
                 (decodeBinder a s m acc b within bnd (firstSmaller laid) (fst held) (S slot) (fst ps))
                 (decodeChild {vars = x :: vars} a (suc s) m acc sc (secondSmaller laid)
                              (S slot + binderSlots (sizeAt a) bnd) (snd ps)
                              (replace {p = LTE (boundAt a sc)} (sym (sizeSuc {x} s))
                                       (transitive (snd held) (LTESucc within))))
  decodeAt a s m acc b within slot fits (SApp f x) laid held
      = let 0 own = ownSlot (replace {p = \k => LTE (slot + k) (locCount a)} laid fits)
            0 ps = twoParts {o = S slot} (snd own) in
            App (locs a !! [<natToFinLT slot {prf = fst own}])
                (decodeChild a s m acc f (firstSmaller laid) (S slot) (fst ps) (transitive (fst held) within))
                (decodeChild a s m acc x (secondSmaller laid) (S slot + sizeAt a f) (snd ps)
                             (transitive (snd held) within))
  decodeAt a s m acc b within slot fits (SAs u p t) laid held
      = let 0 own = ownSlot (replace {p = \k => LTE (slot + k) (locCount a)} laid fits)
            0 ps = twoParts {o = S slot} (snd own) in
            As (locs a !! [<natToFinLT slot {prf = fst own}]) u
               (decodeChild a s m acc p (firstSmaller laid) (S slot) (fst ps) (transitive (fst held) within))
               (decodeChild a s m acc t (secondSmaller laid) (S slot + sizeAt a p) (snd ps)
                            (transitive (snd held) within))
  decodeAt a s m acc b within slot fits (SDelayed r t) laid held
      = let 0 own = ownSlot (replace {p = \k => LTE (slot + k) (locCount a)} laid fits) in
            TDelayed (locs a !! [<natToFinLT slot {prf = fst own}]) r
                     (decodeChild a s m acc t (onlySmaller laid) (S slot) (snd own) (transitive held within))
  decodeAt a s m acc b within slot fits (SDelay d ty t) laid held
      = let 0 own = ownSlot (replace {p = \k => LTE (slot + k) (locCount a)} laid fits)
            0 ps = twoParts {o = S slot} (snd own) in
            TDelay (locs a !! [<natToFinLT slot {prf = fst own}]) d
                   (decodeChild a s m acc ty (firstSmaller laid) (S slot) (fst ps) (transitive (fst held) within))
                   (decodeChild a s m acc t (secondSmaller laid) (S slot + sizeAt a ty) (snd ps)
                                (transitive (snd held) within))
  decodeAt a s m acc b within slot fits (SForce r t) laid held
      = let 0 own = ownSlot (replace {p = \k => LTE (slot + k) (locCount a)} laid fits) in
            TForce (locs a !! [<natToFinLT slot {prf = fst own}]) r
                   (decodeChild a s m acc t (onlySmaller laid) (S slot) (snd own) (transitive held within))
  decodeAt a s m acc b within slot fits (SPrim k) laid held
      = let 0 own = ownSlot (replace {p = \k => LTE (slot + k) (locCount a)} laid fits) in
            PrimVal (locs a !! [<natToFinLT slot {prf = fst own}]) k
  decodeAt a s m acc b within slot fits (SErased Placeholder) laid held
      = let 0 own = ownSlot (replace {p = \k => LTE (slot + k) (locCount a)} laid fits) in
            Erased (locs a !! [<natToFinLT slot {prf = fst own}]) Placeholder
  decodeAt a s m acc b within slot fits (SErased Impossible) laid held
      = let 0 own = ownSlot (replace {p = \k => LTE (slot + k) (locCount a)} laid fits) in
            Erased (locs a !! [<natToFinLT slot {prf = fst own}]) Impossible
  decodeAt a s m acc b within slot fits (SErased (Dotted t)) laid held
      = let 0 own = ownSlot (replace {p = \k => LTE (slot + k) (locCount a)} laid fits) in
            Erased (locs a !! [<natToFinLT slot {prf = fst own}])
                   (Dotted (decodeChild a s m acc t (onlySmaller laid) (S slot) (snd own)
                                        (transitive held within)))
  decodeAt a s m acc b within slot fits (SType u) laid held
      = let 0 own = ownSlot (replace {p = \k => LTE (slot + k) (locCount a)} laid fits) in
            TType (locs a !! [<natToFinLT slot {prf = fst own}]) u

||| The term a root stands for, with its locations, in its scope and any
||| scope beyond it: where a reader embedded the live term, it reads the
||| stored one into the larger scope at once, so decoding costs what
||| embedding did.
export
decodeWithin : SizeOf vars -> Root vars -> Term (vars ++ outer)
decodeWithin s (MkRoot a c slot fits scoped)
    = decodeNode a s c (wellFounded (sizeAt a c)) slot fits
                 (replace {p = LTE (boundAt a c)} (sym (atLength s)) scoped)

||| The term a root stands for, with its locations.
export
decode : SizeOf vars -> Root vars -> Term vars
decode s r = replace {p = Term} (appendNilRightNeutral vars) (decodeWithin {outer = []} s r)

export
{vars : _} -> Show (Root vars) where
  show r = show (decode (mkSizeOf vars) r)

------------------------------------------------------------------------------
-- What a type computes
------------------------------------------------------------------------------

||| What a type computes once its arguments are given, as far as normalising
||| a type asks of it: a universe; a function of no arguments, which may
||| stand for a type; an application of a type constructor; or anything
||| else.
public export
data ResultHead = HeadUniverse | HeadAlias Name | HeadFamily Name | HeadOther

||| What a live type computes: the head of its result, once every
||| Π-binder is gone.
export
resultHead : Term vars -> ResultHead
resultHead (Bind _ _ (Pi {}) sc) = resultHead sc
resultHead (TType {}) = HeadUniverse
resultHead (Ref _ Func n) = HeadAlias n
resultHead tm = case getFn tm of
                     Ref _ (TyCon _) tn => HeadFamily tn
                     _ => HeadOther

-- The head of an application's spine and of a type's result, read off the
-- nodes without decoding them, each step to a child with fewer location
-- slots, as the arena holds.
mutual
  spineHead : (a : Arena) -> (c : Fin (nodeCount a)) -> (0 _ : Accessible LT (sizeAt a c)) -> ResultHead
  spineHead a c acc = spineAt a (sizeAt a c) acc (nodeAt a c) (sized a c)

  spineAt : (a : Arena) -> (0 m : Nat) -> (0 _ : Accessible LT m) -> (nd : Node (nodeCount a)) ->
            (0 _ : m = S (partSlots (sizeAt a) nd)) -> ResultHead
  spineAt a m (Access rec) (SApp f _) laid = spineHead a f (rec (sizeAt a f) (firstSmaller laid))
  spineAt a m acc (SRef (TyCon _) tn) _ = HeadFamily tn
  spineAt a m acc _ _ = HeadOther

mutual
  afterPis : (a : Arena) -> (c : Fin (nodeCount a)) -> (0 _ : Accessible LT (sizeAt a c)) -> ResultHead
  afterPis a c acc = pisAt a (sizeAt a c) acc (nodeAt a c) (sized a c)

  pisAt : (a : Arena) -> (0 m : Nat) -> (0 _ : Accessible LT m) -> (nd : Node (nodeCount a)) ->
          (0 _ : m = S (partSlots (sizeAt a) nd)) -> ResultHead
  pisAt a m (Access rec) (SBind _ b@(BPi {}) sc) laid
      = afterPis a sc (rec (sizeAt a sc) (secondSmaller {x = binderSlots (sizeAt a) b} laid))
  pisAt a m acc (SType _) _ = HeadUniverse
  pisAt a m acc (SRef Func n) _ = HeadAlias n
  pisAt a m acc nd laid = spineAt a m acc nd laid

||| What a stored type computes, as `resultHead` says of the live one, read
||| off its nodes without decoding it.
export
storedHead : Root vars -> ResultHead
storedHead (MkRoot a c _ _ _) = afterPis a c (wellFounded (sizeAt a c))
