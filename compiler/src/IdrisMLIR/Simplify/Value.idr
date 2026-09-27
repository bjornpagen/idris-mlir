||| Static values: what `Simplify` knows about a value at compile time.
|||
||| A static value is Futhark's `StaticVal` and Kovács's partially static
||| value: a tree whose leaves are runtime atoms. It has one base functor,
||| `SValF r a`, with `r` the recursive positions and `a` the atoms, and one
||| generic operation on it, `zipMatch` (Sheard, "Generic unification via
||| two-level types", ICFP 2001): two layers with the same head zip into one
||| layer of pairs. Everything else is derived from the functor, its
||| traversal and `zipMatch`:
|||
||| * equality and order, for specialization keys (ELIM-G-3);
||| * homeomorphic embedding, the whistle that stops unfolding (ELIM-G-19);
||| * the most specific generalization, which a specialization is keyed by
|||   when the whistle blows (ELIM-G-19);
||| * the least upper bound with choices, the shape a residual match's
|||   alternatives join at (ELIM-G-20).
|||
||| Strings are static values too: a string is a tree of literal text,
||| runtime strings, characters and shown numbers, joined by `Append`
||| (ELIM-G-6, ELIM-G-7). A `Choice` is one of several static values, which
||| one being decided at runtime by a tag: the value of a match whose
||| alternatives yield different static values.
module IdrisMLIR.Simplify.Value

import IdrisMLIR.Code
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Term
import IdrisMLIR.Types

import Control.Monad.Identity
import Control.Monad.State
import Data.List
import Data.Maybe
import Data.SnocList
import Data.SortedSet
import Data.String
import Data.Vect
import Decidable.Equality

%default total

------------------------------------------------------------------------------
-- Statements of first-order code
------------------------------------------------------------------------------

||| One pending statement of the current block: a binding, or a match whose
||| alternatives are blocks and whose values the rest of the block uses.
public export
data Stmt = SLet Loc Param Op
          | SMatch Loc (List Param) Atom (List (Branch (Code Pure))) (Maybe (Code Pure))
          | SMatchLit Loc (List Param) Atom (List (Lit, Code Pure)) (Code Pure)

||| What the prefix of a raised function runs (PROF-HEAP-5): an operation or
||| a crash.
public export
data Moved = MovedOp Op | MovedCrash

------------------------------------------------------------------------------
-- Values and their base functor
------------------------------------------------------------------------------

mutual
  public export
  data SVal : Type -> Type where
    ||| A runtime value: an atom of a value type.
    Dyn : VTy -> a -> SVal a
    ||| An Integer: known at compile time, as every Integer is (SEM-BIG-1).
    Big : Integer -> SVal a
    ||| A known constructor, with its fields.
    Con : ConId -> List (SVal a) -> SVal a
    ||| A closure: its label, its captured values, its parameter and body.
    Lam : {k : Nat} -> Label -> Vect k (SVal a) -> Binder -> Term (S k) -> SVal a
    ||| A suspended computation, closure-converted like a lambda.
    Thunk : {k : Nat} -> Label -> Vect k (SVal a) -> Term k -> SVal a
    ||| A deferred call of a function whose result is static, with the
    ||| eliminations applied to it so far (ELIM-G-5), and how many effects
    ||| had been emitted when it was built (not part of its shape).
    Call : FnId -> Nat -> List (SVal a) -> List (Elim a) -> SVal a
    ||| Literal text.
    Text : String -> SVal a
    ||| A runtime character, as a string.
    Chr : a -> SVal a
    ||| A runtime number (an integer or Double), shown.
    Shown : VTy -> a -> SVal a
    Append : SVal a -> SVal a -> SVal a
    ||| One of several values; the tag, a runtime `Int`, says which.
    Choice : a -> List (SVal a) -> SVal a

  ||| An elimination of a static value.
  public export
  data Elim : Type -> Type where
    Apply : SVal a -> Elim a
    Proj : ConId -> Nat -> Elim a
    ForceIt : Elim a

||| One layer of an elimination.
public export
data ElimF r = ApplyF r | ProjF ConId Nat | ForceF

||| One layer of a static value.
public export
data SValF : Type -> Type -> Type where
  DynF : VTy -> a -> SValF r a
  BigF : Integer -> SValF r a
  ConF : ConId -> List r -> SValF r a
  LamF : {k : Nat} -> Label -> Vect k r -> Binder -> Term (S k) -> SValF r a
  ThunkF : {k : Nat} -> Label -> Vect k r -> Term k -> SValF r a
  CallF : FnId -> Nat -> List r -> List (ElimF r) -> SValF r a
  TextF : String -> SValF r a
  ChrF : a -> SValF r a
  ShownF : VTy -> a -> SValF r a
  AppendF : r -> r -> SValF r a
  ChoiceF : a -> List r -> SValF r a

||| The type of the tag of a `Choice`.
export
tagTy : VTy
tagTy = IntT IdrisInt

elimF : Elim a -> ElimF (SVal a)
elimF (Apply v) = ApplyF v
elimF (Proj c i) = ProjF c i
elimF ForceIt = ForceF

unElimF : ElimF (SVal a) -> Elim a
unElimF (ApplyF v) = Apply v
unElimF (ProjF c i) = Proj c i
unElimF ForceF = ForceIt

export
project : SVal a -> SValF (SVal a) a
project (Dyn t x) = DynF t x
project (Big n) = BigF n
project (Con c fs) = ConF c fs
project (Lam l cs b body) = LamF l cs b body
project (Thunk l cs body) = ThunkF l cs body
project (Call f e as es) = CallF f e as (map elimF es)
project (Text s) = TextF s
project (Chr x) = ChrF x
project (Shown t x) = ShownF t x
project (Append a b) = AppendF a b
project (Choice t vs) = ChoiceF t vs

export
embed : SValF (SVal a) a -> SVal a
embed (DynF t x) = Dyn t x
embed (BigF n) = Big n
embed (ConF c fs) = Con c fs
embed (LamF l cs b body) = Lam l cs b body
embed (ThunkF l cs body) = Thunk l cs body
embed (CallF f e as es) = Call f e as (map unElimF es)
embed (TextF s) = Text s
embed (ChrF x) = Chr x
embed (ShownF t x) = Shown t x
embed (AppendF a b) = Append a b
embed (ChoiceF t vs) = Choice t vs

||| The traversal of one layer: its recursive positions with `f`, its atoms,
||| with their types, with `g`.
export
traverseF : Applicative m => (r -> m s) -> (VTy -> a -> m b) -> SValF r a -> m (SValF s b)
traverseF f g (DynF t x) = DynF t <$> g t x
traverseF f g (BigF n) = pure (BigF n)
traverseF f g (ConF c fs) = ConF c <$> traverse f fs
traverseF f g (LamF l cs b body) = (\cs' => LamF l cs' b body) <$> traverse f cs
traverseF f g (ThunkF l cs body) = (\cs' => ThunkF l cs' body) <$> traverse f cs
traverseF f g (CallF fn e as es) = CallF fn e <$> traverse f as <*> traverse elim es
  where
    elim : ElimF r -> m (ElimF s)
    elim (ApplyF v) = ApplyF <$> f v
    elim (ProjF c i) = pure (ProjF c i)
    elim ForceF = pure ForceF
traverseF f g (TextF s) = pure (TextF s)
traverseF f g (ChrF x) = ChrF <$> g CharT x
traverseF f g (ShownF t x) = ShownF t <$> g t x
traverseF f g (AppendF a b) = AppendF <$> f a <*> f b
traverseF f g (ChoiceF t vs) = ChoiceF <$> g tagTy t <*> traverse f vs

||| The recursive positions of one layer.
export
children : SValF r a -> List r
children layer = execState [<] (traverseF (\x => modify (:< x) $> x) (\_, x => pure x) layer) <>> []

||| The atoms of one layer, with their types.
export
leaves : SValF r a -> List (VTy, a)
leaves layer = execState [<] (traverseF (\x => pure x) (\t, x => modify (:< (t, x)) $> x) layer) <>> []

------------------------------------------------------------------------------
-- The traversal of a value
------------------------------------------------------------------------------

||| Visits the atoms of a value in a fixed order, with their types. Every
||| other operation on atoms is an instance of it.
export covering
traverseV : Applicative m => (VTy -> a -> m b) -> SVal a -> m (SVal b)
traverseV g v = embed <$> traverseF (traverseV g) g (project v)

||| An elimination list as the eliminations of a call, to reuse the value
||| traversal.
elimsOf : SVal a -> List (Elim a)
elimsOf (Call _ _ _ es) = es
elimsOf _ = []

holder : List (Elim a) -> SVal a
holder es = Call (MkFnId "") 0 [] es

export covering
traverseElims : Applicative m => (VTy -> a -> m b) -> List (Elim a) -> m (List (Elim b))
traverseElims g es = elimsOf <$> traverseV g (holder es)

export covering
mapV : (a -> b) -> SVal a -> SVal b
mapV f = runIdentity . traverseV (\_, x => Id (f x))

||| The static structure of a value.
export covering
shape : SVal a -> SVal ()
shape = mapV (const ())

export covering
shapeElims : List (Elim a) -> List (Elim ())
shapeElims = runIdentity . traverseElims (\_, _ => Id ())

||| The atoms of values and eliminations, in traversal order, with types.
export covering
atoms : List (SVal a) -> List (Elim a) -> List (VTy, a)
atoms vs es = execState [<] (traverse (traverseV log) vs *> traverseElims log es) <>> []
  where
    log : VTy -> a -> State (SnocList (VTy, a)) a
    log t x = modify (:< (t, x)) $> x

||| Rebuilds values with new atoms, in traversal order.
export covering
refill : List b -> b -> List (SVal a) -> List (Elim a) -> (List (SVal b), List (Elim b))
refill supply dflt vs es = evalState supply ((,) <$> traverse (traverseV next) vs <*> traverseElims next es)
  where
    next : VTy -> a -> State (List b) b
    next _ _ = do
      xs <- get
      case xs of
        (y :: ys) => put ys $> y
        [] => pure dflt

||| The number of nodes of a value.
export covering
size : SVal a -> Nat
size v = S (sum (map size (children (project v))))

||| The values an elimination sequence applies.
export
applied : List (Elim a) -> List (SVal a)
applied [] = []
applied (Apply v :: es) = v :: applied es
applied (_ :: es) = applied es

------------------------------------------------------------------------------
-- zipMatch and the structural order
------------------------------------------------------------------------------

||| Two layers with the same head, zipped; `Nothing` when the heads differ.
||| Data in a head (an Integer, a text, a label, a constructor) must be equal.
export
zipMatch : SValF r a -> SValF s b -> Maybe (SValF (r, s) (a, b))
zipMatch (DynF t x) (DynF u y) = if t == u then Just (DynF t (x, y)) else Nothing
zipMatch (BigF m) (BigF n) = if m == n then Just (BigF m) else Nothing
zipMatch (ConF c fs) (ConF d gs) =
  if c == d && length fs == length gs then Just (ConF c (zip fs gs)) else Nothing
zipMatch (LamF l {k} cs b body) (LamF m {k = j} ds _ _) =
  if l /= m then Nothing else case decEq j k of
    Yes Refl => Just (LamF l (zip cs ds) b body)
    No _ => Nothing
zipMatch (ThunkF l {k} cs body) (ThunkF m {k = j} ds _) =
  if l /= m then Nothing else case decEq j k of
    Yes Refl => Just (ThunkF l (zip cs ds) body)
    No _ => Nothing
zipMatch (CallF f e as es) (CallF g _ bs fs) =
  if f == g && length as == length bs && length es == length fs
    then CallF f e (zip as bs) <$> traverse elims (zip es fs)
    else Nothing
  where
    elims : (ElimF r, ElimF s) -> Maybe (ElimF (r, s))
    elims (ApplyF x, ApplyF y) = Just (ApplyF (x, y))
    elims (ProjF c i, ProjF d j) = if c == d && i == j then Just (ProjF c i) else Nothing
    elims (ForceF, ForceF) = Just ForceF
    elims _ = Nothing
zipMatch (TextF s) (TextF t) = if s == t then Just (TextF s) else Nothing
zipMatch (ChrF x) (ChrF y) = Just (ChrF (x, y))
zipMatch (ShownF t x) (ShownF u y) = if t == u then Just (ShownF t (x, y)) else Nothing
zipMatch (AppendF a b) (AppendF c d) = Just (AppendF (a, c) (b, d))
zipMatch (ChoiceF x vs) (ChoiceF y ws) =
  if length vs == length ws then Just (ChoiceF (x, y) (zip vs ws)) else Nothing
zipMatch _ _ = Nothing

||| The order of heads, for layers that do not zip.
rank : SValF r a -> Nat
rank (DynF _ _) = 0
rank (BigF _) = 1
rank (ConF _ _) = 2
rank (LamF _ _ _ _) = 3
rank (ThunkF _ _ _) = 4
rank (CallF _ _ _ _) = 5
rank (TextF _) = 6
rank (ChrF _) = 7
rank (ShownF _ _) = 8
rank (AppendF _ _) = 9
rank (ChoiceF _ _) = 10

elimRank : ElimF x -> (Nat, String, Nat)
elimRank (ApplyF _) = (0, "", 0)
elimRank (ProjF c i) = (1, show c.dataId ++ "::" ++ c.name, i)
elimRank ForceF = (2, "", 0)

||| Orders two layers that do not zip by their heads.
headOrder : SValF r a -> SValF s b -> Ordering
headOrder (DynF t _) (DynF u _) = compare t u
headOrder (BigF m) (BigF n) = compare m n
headOrder (ConF c fs) (ConF d gs) = compare c d <+> compare (length fs) (length gs)
headOrder (LamF l {k} _ _ _) (LamF m {k = j} _ _ _) = compare l m <+> compare k j
headOrder (ThunkF l {k} _ _) (ThunkF m {k = j} _ _) = compare l m <+> compare k j
headOrder (CallF f _ as es) (CallF g _ bs fs) =
  compare f g <+> compare (length as) (length bs) <+> compare (map elimRank es) (map elimRank fs)
headOrder (TextF s) (TextF t) = compare s t
headOrder (ShownF t _) (ShownF u _) = compare t u
headOrder (ChoiceF _ vs) (ChoiceF _ ws) = compare (length vs) (length ws)
headOrder x y = compare (rank x) (rank y)

mutual
  ||| The structural order: heads, then atoms and children in order.
  export covering
  cmpV : Ord a => SVal a -> SVal a -> Ordering
  cmpV x y = case zipMatch (project x) (project y) of
    Nothing => headOrder (project x) (project y)
    Just layer => cmpLeaves (map snd (leaves layer)) <+> cmpAll (children layer)

  covering
  cmpLeaves : Ord a => List (a, a) -> Ordering
  cmpLeaves [] = EQ
  cmpLeaves ((a, b) :: rest) = compare a b <+> cmpLeaves rest

  covering
  cmpAll : Ord a => List (SVal a, SVal a) -> Ordering
  cmpAll [] = EQ
  cmpAll ((a, b) :: rest) = cmpV a b <+> cmpAll rest

export covering
Ord a => Eq (SVal a) where
  a == b = cmpV a b == EQ

export covering
Ord a => Ord (SVal a) where
  compare = cmpV

export covering
cmpElims : Ord a => List (Elim a) -> List (Elim a) -> Ordering
cmpElims es fs = cmpV (holder es) (holder fs)

------------------------------------------------------------------------------
-- Configurations: values with their literals
------------------------------------------------------------------------------

||| A leaf of a configuration or key: a literal the value is known to be, or
||| a runtime value (`Nothing`).
public export
Leaf : Type
Leaf = Maybe Lit

litRank : Lit -> Nat
litRank (LInt _ _) = 0
litRank (LChar _) = 1
litRank (LStr _) = 2
litRank (LDouble _) = 3
litRank (LBig _) = 4

export
Ord Lit where
  compare (LInt s a) (LInt t b) = compare s t <+> compare a b
  compare (LChar a) (LChar b) = compare a b
  compare (LStr a) (LStr b) = compare a b
  compare (LDouble a) (LDouble b) = compare a b
  compare (LBig a) (LBig b) = compare a b
  compare a b = compare (litRank a) (litRank b)

literal : Atom -> Leaf
literal (ALit l) = Just l
literal _ = Nothing

||| The configuration of a value: its shape, with the literals among its
||| atoms kept.
export covering
config : SVal Atom -> SVal Leaf
config = mapV literal

export covering
configElims : List (Elim Atom) -> List (Elim Leaf)
configElims = runIdentity . traverseElims (\_, a => Id (literal a))

||| A key with every atom a runtime value: the generic key.
export covering
generic : SVal a -> SVal Leaf
generic = mapV (const Nothing)

export covering
genericElims : List (Elim a) -> List (Elim Leaf)
genericElims = runIdentity . traverseElims (\_, _ => Id Nothing)

------------------------------------------------------------------------------
-- The whistle: homeomorphic embedding (ELIM-G-19)
------------------------------------------------------------------------------

||| Does the first string embed in the second as a subsequence (Higman)?
subsequence : List Char -> List Char -> Bool
subsequence [] _ = True
subsequence _ [] = False
subsequence (x :: xs) (y :: ys) = if x == y then subsequence xs ys else subsequence (x :: xs) ys

||| The well-quasi-order on literals: integers by absolute value, strings by
||| subsequence (Higman), equal characters, and any two doubles. Equality is
||| a well-quasi-order only on a small alphabet: a loop that computes a new
||| double each time (n-body's positions) would never repeat one, so doubles
||| all embed one another and the whistle generalizes them.
litEmbeds : Lit -> Lit -> Bool
litEmbeds (LInt s a) (LInt t b) = s == t && abs a <= abs b
litEmbeds (LBig a) (LBig b) = abs a <= abs b
litEmbeds (LChar a) (LChar b) = a == b
litEmbeds (LDouble _) (LDouble _) = True
litEmbeds (LStr a) (LStr b) = subsequence (unpack a) (unpack b)
litEmbeds _ _ = False

leafEmbeds : Leaf -> Leaf -> Bool
leafEmbeds Nothing Nothing = True
leafEmbeds (Just a) (Just b) = litEmbeds a b
leafEmbeds _ _ = False

||| The subterms of a value, children before their parents, numbered, each
||| layer with its children as their numbers; and the root's number.
covering
subterms : SVal a -> (Nat, List (Nat, SValF Nat a))
subterms v = let ((_, s), root) = runState (0, [<]) (go v) in (root, s <>> [])
  where
    go : SVal a -> State (Nat, SnocList (Nat, SValF Nat a)) Nat
    go w = do
      layer <- traverseF go (\_, x => pure x) (project w)
      (n, s) <- get
      put (S n, s :< (n, layer))
      pure n

||| Does a subterm of `x`, with its children's positions, couple with a layer
||| of `y` whose children are the sets of positions of the subterms of `x`
||| that embed in them? Heads match, leaves embed, children embed pairwise.
couples : SValF Nat Leaf -> SValF (SortedSet Nat) Leaf -> Bool
couples (BigF m) (BigF n) = abs m <= abs n
couples (TextF s) (TextF t) = subsequence (unpack s) (unpack t)
couples k layer = case zipMatch k layer of
  Nothing => False
  Just z => all (uncurry leafEmbeds) (map snd (leaves z)) && all (uncurry contains) (children z)

||| Homeomorphic embedding (Kruskal): `x` embeds in `y` when `y` is `x`
||| with more structure around or inside it. With finitely many heads and
||| well-quasi-ordered leaves, every infinite sequence of configurations has
||| one that embeds in a later one, so a path of unfoldings that stops when
||| an ancestor embeds is finite (Leuschel, SAS 1998).
|||
||| The recursive definition (couple, or embed in a child) visits a pair of
||| subterms once per path to it, exponentially many for `S (S (... Z))`.
||| This is its dynamic program: bottom-up over `y`, the set of subterms of
||| `x` that embed in each subterm of `y`, in time |x| * |y|.
export covering
embeds : SVal Leaf -> SVal Leaf -> Bool
embeds x y =
  let (root, xs) = subterms x in contains root (within xs y)
  where
    within : List (Nat, SValF Nat Leaf) -> SVal Leaf -> SortedSet Nat
    within xs w =
      let layer = runIdentity (traverseF (Id . within xs) (\_, a => Id a) (project w))
      in fromList [i | (i, k) <- xs, couples k layer || any (contains i) (children layer)]

||| Pointwise embedding of argument lists of the same length.
export covering
embedsAll : List (SVal Leaf) -> List (SVal Leaf) -> Bool
embedsAll xs ys = length xs == length ys && all (uncurry embeds) (zip xs ys)

------------------------------------------------------------------------------
-- Generalization (ELIM-G-19)
------------------------------------------------------------------------------

||| The most specific generalization of two configurations: equal literals
||| stay, different atoms become runtime values. `Nothing` when a static
||| part differs, which no runtime value can stand for.
export covering
msg : SVal Leaf -> SVal Leaf -> Maybe (SVal Leaf)
msg x y = case zipMatch (project x) (project y) of
  Nothing => Nothing
  Just layer => embed <$> traverseF (uncurry msg) (\_, (a, b) => Just (if a == b then a else Nothing)) layer

export covering
msgAll : List (SVal Leaf) -> List (SVal Leaf) -> Maybe (List (SVal Leaf))
msgAll xs ys = if length xs == length ys then traverse (uncurry msg) (zip xs ys) else Nothing

export covering
msgElims : List (Elim Leaf) -> List (Elim Leaf) -> Maybe (List (Elim Leaf))
msgElims es fs = elimsOf <$> msg (holder es) (holder fs)

------------------------------------------------------------------------------
-- Joins (ELIM-G-20)
------------------------------------------------------------------------------

mutual
  ||| The least upper bound of two shapes: equal heads join their parts, and
  ||| different heads become a choice between them. A choice is flat: its
  ||| alternatives have different heads.
  export covering
  lub : SVal () -> SVal () -> SVal ()
  lub (Choice _ xs) (Choice _ ys) = Choice () (foldl add xs ys)
  lub (Choice _ xs) y = Choice () (add xs y)
  lub x (Choice _ ys) = Choice () (foldl add [x] ys)
  lub x y = case zipMatch (project x) (project y) of
    Just layer => embed (runIdentity (traverseF (\(a, b) => Id (lub a b)) (\_, _ => Id ()) layer))
    Nothing => Choice () [x, y]

  ||| Adds a shape to the alternatives of a choice.
  covering
  add : List (SVal ()) -> SVal () -> List (SVal ())
  add [] y = [y]
  add (x :: xs) y = case zipMatch (project x) (project y) of
    Just _ => lub x y :: xs
    Nothing => x :: add xs y

------------------------------------------------------------------------------
-- Printing configurations (ELIM-G-3 legends, diagnostics)
------------------------------------------------------------------------------

showLeaf : VTy -> Leaf -> String
showLeaf t Nothing = "_:" ++ show t
showLeaf t (Just l) = show l

mutual
  ||| A configuration, printed.
  export covering
  showShape : SVal Leaf -> String
  showShape (Dyn t x) = showLeaf t x
  showShape (Big n) = show n
  showShape (Con c fs) = show c ++ "(" ++ showList fs ++ ")"
  showShape (Lam l cs _ _) = show l ++ "[" ++ showList (toList cs) ++ "]"
  showShape (Thunk l cs _) = "delay" ++ show l.index ++ "[" ++ showList (toList cs) ++ "]"
  showShape (Call f _ as es) = show f ++ "(" ++ showList as ++ ")" ++ showElims es
  showShape (Text s) = show s
  showShape (Chr x) = "str(" ++ showLeaf CharT x ++ ")"
  showShape (Shown t x) = "show(" ++ showLeaf t x ++ ")"
  showShape (Append a b) = "(" ++ showShape a ++ " ++ " ++ showShape b ++ ")"
  showShape (Choice t vs) = "choice(" ++ showList vs ++ ")"

  covering
  showList : List (SVal Leaf) -> String
  showList [] = ""
  showList [v] = showShape v
  showList (v :: vs) = showShape v ++ "; " ++ showList vs

  export covering
  showElims : List (Elim Leaf) -> String
  showElims [] = ""
  showElims (Apply v :: es) = " @(" ++ showShape v ++ ")" ++ showElims es
  showElims (Proj c i :: es) = " ." ++ show c ++ "#" ++ show i ++ showElims es
  showElims (ForceIt :: es) = " !" ++ showElims es
