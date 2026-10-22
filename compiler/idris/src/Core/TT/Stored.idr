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
module Core.TT.Stored

import Core.TT

import Array

import Control.WellFounded
import Data.DPair
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
||| below it: by id while a definition is frozen, by place in its arena
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

||| A place among `n`: its number, which both hosts hold as an integer, and
||| its bound, erased. A `Fin n` says the same, but the stock host holds one
||| as a chain of successors, so the `i`th would cost `i` cells to build and
||| `i` steps to read, and freezing a column of them would be quadratic.
public export
record Place (n : Nat) where
  constructor MkPlace
  spot : Nat
  0 inside : LT spot n

||| A binder of an arena of `n` nodes.
public export
SBinder : Nat -> Type
SBinder n = SBinderOf (Place n)

||| A node of an arena of `n` nodes: each child is one of them.
public export
Node : Nat -> Type
Node n = NodeOf (Place n)

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
-- The arena
------------------------------------------------------------------------------

||| One definition's terms. `nodes` holds each distinct subterm once, a
||| child before every node above it; `slots` holds, for each node, the
||| location slots of its unfolding (one for each occurrence of a node in
||| it, and one more for each binder, which has a location of its own); and
||| `locs` holds the locations, in the preorder of each term's unfolding,
||| the terms in the order they were frozen.
export
record Arena where
  constructor MkArena
  nodeCount : Nat
  nodes : Vector nodeCount (Node nodeCount)
  slots : Vector nodeCount Nat
  locCount : Nat
  locs : Vector locCount FC

||| A stored term in scope `vars`: its arena, its node, and the slot its
||| first location is at. Only `rootAt` makes one, at the place `freeze`
||| gave a term in scope `vars`, so its unfolding is that term's.
export
data Root : Scoped where
  MkRoot : (arena : Arena) -> (node : Place (nodeCount arena)) ->
           (slot : Place (locCount arena)) -> Root vars

-- The cell of a column at a place. The array is read by a `Fin`, so the
-- place's number becomes one here, the one place the arena reads a column.
cellAt : Vector n a -> Place n -> a
cellAt v (MkPlace i inside) = v !! [<natToFinLT i {prf = inside}]

-- `i` as a place among `n`, when it is one: one comparison, its proof
-- erased.
placeIn : (n : Nat) -> Nat -> Maybe (Place n)
placeIn n i = case choose (i < n) of
                Left lt => Just (MkPlace i (ltOpReflectsLT i n lt))
                Right _ => Nothing

nodeAt : (a : Arena) -> Place (nodeCount a) -> Node (nodeCount a)
nodeAt a i = cellAt (nodes a) i

sizeAt : (a : Arena) -> Place (nodeCount a) -> Nat
sizeAt a i = cellAt (slots a) i

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

||| Every node's children as places among `n` nodes, when each is one.
bounded : (n : Nat) -> Column k (NodeOf Nat) -> Maybe (Column k (Node n))
bounded n NoCells = Just NoCells
bounded n (Then col x) = [| Then (bounded n col) (traverseNode (placeIn n) x) |]

------------------------------------------------------------------------------
-- Freezing
------------------------------------------------------------------------------

||| What freezing one definition has made so far: the nodes, by id, each
||| with the location slots of its unfolding; the table that finds a node
||| already made; and the locations, in preorder.
record Freezing where
  constructor MkFreezing
  made : Nat
  built : Column made (NodeOf Nat)
  sizes : Column made Nat
  seen : SortedMap (NodeOf Nat) Nat
  located : Nat
  locations : Column located FC

initial : Freezing
initial = MkFreezing Z NoCells NoCells SortedMap.empty Z NoCells

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

||| A frozen term's place before its arena is sealed: its node's id and its
||| first location's slot.
export
data Pos : Scoped where
  MkPos : (node : Nat) -> (slot : Nat) -> Pos vars

-- What freezing a part of a term gives: the state after it, the part, and
-- the location slots of its unfolding.
record Part (a : Type) where
  constructor MkPart
  after : Freezing
  part : a
  extent : Nat

-- The node's id: the one already made if there is one, or a new one.
intern : NodeOf Nat -> Nat -> Freezing -> Part Nat
intern n sz st
    = case SortedMap.lookup n st.seen of
           Just i => MkPart st i sz
           Nothing =>
             MkPart (MkFreezing (S st.made) (Then st.built n) (Then st.sizes sz)
                                (SortedMap.insert n st.made st.seen)
                                st.located st.locations)
                    st.made sz

-- An occurrence's location, the next in preorder.
locate : FC -> Freezing -> Freezing
locate fc st
    = MkFreezing st.made st.built st.sizes st.seen (S st.located) (Then st.locations fc)

-- Each kind of node that holds terms is frozen by a function of its own,
-- so that every recursive call is on a part of its argument. A node's
-- location is recorded before its children's, and a binder's after its
-- node's, which is the preorder `decode` reads.
mutual
  frozenPi : PiInfo (Term vars) -> Freezing -> Part (PiInfo Nat)
  frozenPi Implicit st = MkPart st Implicit 0
  frozenPi Explicit st = MkPart st Explicit 0
  frozenPi AutoImplicit st = MkPart st AutoImplicit 0
  frozenPi (DefImplicit t) st
      = let MkPart st1 i n = frozenTerm t st in MkPart st1 (DefImplicit i) n

  frozenBinder : Binder (Term vars) -> Freezing -> Part (SBinderOf Nat)
  frozenBinder (Lam fc c p ty) st
      = let MkPart st1 p' np = frozenPi p (locate fc st)
            MkPart st2 ty' nt = frozenTerm ty st1 in
            MkPart st2 (BLam c p' ty') (S (np + nt))
  frozenBinder (Let fc c v ty) st
      = let MkPart st1 v' nv = frozenTerm v (locate fc st)
            MkPart st2 ty' nt = frozenTerm ty st1 in
            MkPart st2 (BLet c v' ty') (S (nv + nt))
  frozenBinder (Pi fc c p ty) st
      = let MkPart st1 p' np = frozenPi p (locate fc st)
            MkPart st2 ty' nt = frozenTerm ty st1 in
            MkPart st2 (BPi c p' ty') (S (np + nt))
  frozenBinder (PVar fc c p ty) st
      = let MkPart st1 p' np = frozenPi p (locate fc st)
            MkPart st2 ty' nt = frozenTerm ty st1 in
            MkPart st2 (BPVar c p' ty') (S (np + nt))
  frozenBinder (PLet fc c v ty) st
      = let MkPart st1 v' nv = frozenTerm v (locate fc st)
            MkPart st2 ty' nt = frozenTerm ty st1 in
            MkPart st2 (BPLet c v' ty') (S (nv + nt))
  frozenBinder (PVTy fc c ty) st
      = let MkPart st1 ty' nt = frozenTerm ty (locate fc st) in
            MkPart st1 (BPVTy c ty') (S nt)

  frozenTerms : List (Term vars) -> Freezing -> Part (List Nat)
  frozenTerms [] st = MkPart st [] 0
  frozenTerms (t :: ts) st
      = let MkPart st1 i n = frozenTerm t st
            MkPart st2 is ns = frozenTerms ts st1 in
            MkPart st2 (i :: is) (n + ns)

  -- A node with one child: its location, then the child.
  frozenOne : FC -> (Nat -> NodeOf Nat) -> Term vars -> Freezing -> Part Nat
  frozenOne fc mk t st
      = let MkPart st1 i n = frozenTerm t (locate fc st) in
            intern (mk i) (S n) st1

  -- A node with two children: its location, then each child in turn.
  frozenTwo : FC -> (Nat -> Nat -> NodeOf Nat) -> Term vars -> Term vars -> Freezing -> Part Nat
  frozenTwo fc mk t u st
      = let MkPart st1 i n = frozenTerm t (locate fc st)
            MkPart st2 j m = frozenTerm u st1 in
            intern (mk i j) (S (n + m)) st2

  frozenTerm : Term vars -> Freezing -> Part Nat
  frozenTerm (Local fc l idx _) st = intern (SLocal l idx) 1 (locate fc st)
  frozenTerm (Ref fc nt n) st = intern (SRef nt n) 1 (locate fc st)
  frozenTerm (Meta fc n i args) st
      = let MkPart st1 is ns = frozenTerms args (locate fc st) in
            intern (SMeta n i is) (S ns) st1
  frozenTerm (Bind fc x b sc) st
      = let MkPart st1 b' nb = frozenBinder b (locate fc st)
            MkPart st2 s ns = frozenTerm sc st1 in
            intern (SBind x b' s) (S (nb + ns)) st2
  frozenTerm (App fc f a) st = frozenTwo fc SApp f a st
  frozenTerm (As fc u a p) st = frozenTwo fc (SAs u) a p st
  frozenTerm (TDelayed fc r t) st = frozenOne fc (SDelayed r) t st
  frozenTerm (TDelay fc d ty t) st = frozenTwo fc (SDelay d) ty t st
  frozenTerm (TForce fc r t) st = frozenOne fc (SForce r) t st
  frozenTerm (PrimVal fc k) st = intern (SPrim k) 1 (locate fc st)
  frozenTerm (Erased fc Placeholder) st = intern (SErased Placeholder) 1 (locate fc st)
  frozenTerm (Erased fc Impossible) st = intern (SErased Impossible) 1 (locate fc st)
  frozenTerm (Erased fc (Dotted t)) st = frozenOne fc (\i => SErased (Dotted i)) t st
  frozenTerm (TType fc u) st = intern (SType u) 1 (locate fc st)

||| A term frozen into the definition's arena, every subterm the arena
||| already holds shared: its place there, made a root once the arena is
||| sealed.
export
freeze : Term vars -> Freeze (Pos vars)
freeze tm = MkFreeze (\st => let MkPart st' i _ = frozenTerm tm st in
                                 (st', MkPos i st.located))

||| The arena a freezing made, and what it gave, each place in it still to
||| be made a root of that arena (`rootAt`). Nothing when a node's child is
||| not among the nodes made, which interning a child before its parent
||| makes impossible.
export
seal : Freeze a -> Maybe (Arena, a)
seal (MkFreeze run)
    = let (st, x) = run initial in
      case bounded st.made st.built of
           Nothing => Nothing
           Just ns => Just (MkArena st.made (column ns) (column st.sizes)
                                    st.located (column st.locations), x)

||| The root of an arena at a place its own freezing gave: the arena and the
||| places `seal` gives together. Nothing for a place outside the arena,
||| which only another freezing gives.
export
rootAt : (a : Arena) -> Pos vars -> Maybe (Root vars)
rootAt a (MkPos n s) = MkRoot a <$> placeIn (nodeCount a) n <*> placeIn (locCount a) s

------------------------------------------------------------------------------
-- Decoding
------------------------------------------------------------------------------

-- The name at a place below the length of a scope.
0 nameBelow : {0 vars : List a} -> HasLength n vars -> So (idx < n) -> a
nameBelow {idx = Z} Z lt = absurd lt
nameBelow {idx = S _} Z lt = absurd lt
nameBelow {vars = x :: _} {idx = Z} (S _) _ = x
nameBelow {idx = S k} (S p) lt = nameBelow {idx = k} p lt

-- A place below the length of a scope is a variable of it.
0 inScope : (h : HasLength n vars) -> (lt : So (idx < n)) -> IsVar (nameBelow h lt) idx vars
inScope {idx = Z} Z lt = absurd lt
inScope {idx = S _} Z lt = absurd lt
inScope {idx = Z} (S _) _ = First
inScope {idx = S k} (S p) lt = Later (inScope {idx = k} p lt)

-- A local variable: its proof is decided from the scope's length, which
-- the decoder carries, so deciding it is one comparison.
decodeLocal : FC -> Maybe Bool -> (idx : Nat) -> SizeOf vars -> Maybe (Term (vars ++ outer))
decodeLocal fc l idx s
    = case choose (idx < size s) of
           Left lt =>
             Just (Local {name = nameBelow (hasLength s) lt} fc l idx
                         (embedIsVar (inScope (hasLength s) lt)))
           Right _ => Nothing

both : (p -> q -> r) -> Maybe p -> Maybe q -> Maybe r
both f (Just x) (Just y) = Just (f x y)
both f _ _ = Nothing

piSize : (a : Arena) -> PiInfo (Place (nodeCount a)) -> Nat
piSize a (DefImplicit d) = sizeAt a d
piSize a _ = 0

-- A binder's location slots: its own, then its terms'.
binderSize : (a : Arena) -> SBinder (nodeCount a) -> Nat
binderSize a (BLam _ p ty) = S (piSize a p + sizeAt a ty)
binderSize a (BLet _ v ty) = S (sizeAt a v + sizeAt a ty)
binderSize a (BPi _ p ty) = S (piSize a p + sizeAt a ty)
binderSize a (BPVar _ p ty) = S (piSize a p + sizeAt a ty)
binderSize a (BPLet _ v ty) = S (sizeAt a v + sizeAt a ty)
binderSize a (BPVTy _ ty) = S (sizeAt a ty)

-- Decoding a stored term is a recursion over the location slots of the
-- unfolding left to decode. Each child has fewer than the node above it,
-- which is decided as the child is reached (`decodeChild`), so the
-- recursion descends a measure. A child's first location follows the
-- locations of the children before it, whose counts the slots column
-- gives. A stored term `freeze` made breaks neither fact, nor puts a
-- variable outside its scope; one that does is no term, and decodes to
-- nothing.
mutual
  decodeChild : (a : Arena) -> SizeOf vars -> (m : Nat) -> (0 _ : Accessible LT m) ->
                (c : Place (nodeCount a)) -> (mc : Nat) -> (slot : Nat) ->
                Maybe (Term (vars ++ outer))
  decodeChild a s m (Access rec) c mc slot
      = case choose (mc < m) of
             Left lt => decodeNode a s c mc (rec mc (ltOpReflectsLT mc m lt)) slot
             Right _ => Nothing

  decodeAll : (a : Arena) -> SizeOf vars -> (m : Nat) -> (0 _ : Accessible LT m) ->
              List (Place (nodeCount a)) -> (slot : Nat) ->
              Maybe (List (Term (vars ++ outer)))
  decodeAll a s m acc [] slot = Just []
  decodeAll a s m acc (c :: cs) slot
      = let mc = sizeAt a c in
            both (::) (decodeChild a s m acc c mc slot) (decodeAll a s m acc cs (slot + mc))

  decodePi : (a : Arena) -> SizeOf vars -> (m : Nat) -> (0 _ : Accessible LT m) ->
             PiInfo (Place (nodeCount a)) -> (slot : Nat) ->
             Maybe (PiInfo (Term (vars ++ outer)))
  decodePi a s m acc Implicit slot = Just Implicit
  decodePi a s m acc Explicit slot = Just Explicit
  decodePi a s m acc AutoImplicit slot = Just AutoImplicit
  decodePi a s m acc (DefImplicit d) slot
      = map DefImplicit (decodeChild a s m acc d (sizeAt a d) slot)

  -- A binder from its own location's slot.
  decodeBinder : (a : Arena) -> SizeOf vars -> (m : Nat) -> (0 _ : Accessible LT m) ->
                 SBinder (nodeCount a) -> (slot : Nat) ->
                 Maybe (Binder (Term (vars ++ outer)))
  decodeBinder a s m acc b slot
      = case placeIn (locCount a) slot of
          Nothing => Nothing
          Just at =>
            let fc = cellAt (locs a) at in
            case b of
              BLam c p ty =>
                both (Lam fc c) (decodePi a s m acc p (S slot))
                     (decodeChild a s m acc ty (sizeAt a ty) (S slot + piSize a p))
              BLet c v ty =>
                let mv = sizeAt a v in
                both (Let fc c) (decodeChild a s m acc v mv (S slot))
                     (decodeChild a s m acc ty (sizeAt a ty) (S slot + mv))
              BPi c p ty =>
                both (Pi fc c) (decodePi a s m acc p (S slot))
                     (decodeChild a s m acc ty (sizeAt a ty) (S slot + piSize a p))
              BPVar c p ty =>
                both (PVar fc c) (decodePi a s m acc p (S slot))
                     (decodeChild a s m acc ty (sizeAt a ty) (S slot + piSize a p))
              BPLet c v ty =>
                let mv = sizeAt a v in
                both (PLet fc c) (decodeChild a s m acc v mv (S slot))
                     (decodeChild a s m acc ty (sizeAt a ty) (S slot + mv))
              BPVTy c ty => map (PVTy fc c) (decodeChild a s m acc ty (sizeAt a ty) (S slot))

  decodeNode : (a : Arena) -> SizeOf vars -> (c : Place (nodeCount a)) ->
               (m : Nat) -> (0 _ : Accessible LT m) -> (slot : Nat) ->
               Maybe (Term (vars ++ outer))
  decodeNode a s c m acc slot
      = case placeIn (locCount a) slot of
          Nothing => Nothing
          Just at =>
            let fc = cellAt (locs a) at in
            case nodeAt a c of
              SLocal l idx => decodeLocal fc l idx s
              SRef nt n => Just (Ref fc nt n)
              SMeta n i xs => map (Meta fc n i) (decodeAll a s m acc xs (S slot))
              SBind x b sc =>
                both (Bind fc x) (decodeBinder a s m acc b (S slot))
                     (decodeChild {vars = x :: vars} a (suc s) m acc sc (sizeAt a sc)
                                  (S slot + binderSize a b))
              SApp f x =>
                let mf = sizeAt a f in
                both (App fc) (decodeChild a s m acc f mf (S slot))
                     (decodeChild a s m acc x (sizeAt a x) (S slot + mf))
              SAs u p t =>
                let mp = sizeAt a p in
                both (As fc u) (decodeChild a s m acc p mp (S slot))
                     (decodeChild a s m acc t (sizeAt a t) (S slot + mp))
              SDelayed r t => map (TDelayed fc r) (decodeChild a s m acc t (sizeAt a t) (S slot))
              SDelay d ty t =>
                let mty = sizeAt a ty in
                both (TDelay fc d) (decodeChild a s m acc ty mty (S slot))
                     (decodeChild a s m acc t (sizeAt a t) (S slot + mty))
              SForce r t => map (TForce fc r) (decodeChild a s m acc t (sizeAt a t) (S slot))
              SPrim k => Just (PrimVal fc k)
              SErased Placeholder => Just (Erased fc Placeholder)
              SErased Impossible => Just (Erased fc Impossible)
              SErased (Dotted t) =>
                map (\t' => Erased fc (Dotted t')) (decodeChild a s m acc t (sizeAt a t) (S slot))
              SType u => Just (TType fc u)

||| The term a root stands for, with its locations, in its scope and any
||| scope beyond it: where a reader embedded the live term, it reads the
||| stored one into the larger scope at once, so decoding costs what
||| embedding did. Nothing for a root `freeze` never made.
export
decodeWithin : SizeOf vars -> Root vars -> Maybe (Term (vars ++ outer))
decodeWithin s (MkRoot a c slot)
    = let m = sizeAt a c in decodeNode a s c m (wellFounded m) (spot slot)

||| The term a root stands for, with its locations.
export
decode : SizeOf vars -> Root vars -> Maybe (Term vars)
decode s r = replace {p = \vs => Maybe (Term vs)} (appendNilRightNeutral vars)
                     (decodeWithin {outer = []} s r)

export
{vars : _} -> Show (Root vars) where
  show r = case decode (mkSizeOf vars) r of
                Just tm => show tm
                Nothing => "<a stored term outside its arena>"

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

-- The head of an application's spine, read off the nodes without decoding
-- them, each step to a child with fewer location slots.
spineHead : (a : Arena) -> Place (nodeCount a) -> (m : Nat) -> (0 _ : Accessible LT m) ->
            Maybe ResultHead
spineHead a c m (Access rec)
    = case nodeAt a c of
           SApp f _ =>
             let mf = sizeAt a f in
             case choose (mf < m) of
                  Left lt => spineHead a f mf (rec mf (ltOpReflectsLT mf m lt))
                  Right _ => Nothing
           SRef (TyCon _) tn => Just (HeadFamily tn)
           _ => Just HeadOther

afterPis : (a : Arena) -> Place (nodeCount a) -> (m : Nat) -> (0 _ : Accessible LT m) ->
           Maybe ResultHead
afterPis a c m (Access rec)
    = case nodeAt a c of
           SBind _ (BPi {}) sc =>
             let ms = sizeAt a sc in
             case choose (ms < m) of
                  Left lt => afterPis a sc ms (rec ms (ltOpReflectsLT ms m lt))
                  Right _ => Nothing
           SType _ => Just HeadUniverse
           SRef Func n => Just (HeadAlias n)
           _ => spineHead a c m (Access rec)

||| What a stored type computes, as `resultHead` says of the live one, read
||| off its nodes without decoding it. Nothing for a root `freeze` never
||| made.
export
storedHead : Root vars -> Maybe ResultHead
storedHead (MkRoot a c _) = let m = sizeAt a c in afterPis a c m (wellFounded m)
