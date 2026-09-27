||| Static values (Futhark's defunctionalisation, Hovgaard et al. TFP 2018):
||| what `Simplify` knows about a value at compile time.
|||
||| A static value is parameterised over its runtime atoms. `SVal Atom` is a
||| value during evaluation; `SVal ()` is its *shape*, the static structure
||| alone, and the key of a specialization (ELIM-G-3). The atoms of a value
||| are what a specialization takes as parameters (Futhark's ⟦sv⟧), and
||| rebuilding a value from new atoms is a traversal. Shapes are compared
||| structurally: two closures are the same when their labels (program
||| points) and captured values are, never by printed text.
module IdrisMLIR.Simplify.Value

import IdrisMLIR.Code
import IdrisMLIR.Ids
import IdrisMLIR.Term
import IdrisMLIR.Types

import Control.Monad.Identity
import Control.Monad.State
import Data.List
import Data.SnocList
import Data.String
import Data.Vect

%default total

------------------------------------------------------------------------------
-- Values
------------------------------------------------------------------------------

||| A string known at compile time up to runtime pieces (ELIM-G-6, ELIM-G-7):
||| runtime strings, characters and decimal numbers.
public export
data SStr a = SLit String
            | SRun a                  -- a runtime string
            | SAppend (SStr a) (SStr a)
            | SCons a (SStr a)        -- a runtime character in front
            | SShow IntTy a           -- a runtime number in decimal
            | SChr a                  -- a runtime character

mutual
  public export
  data SVal : Type -> Type where
    ||| A runtime value: an atom of a value type.
    Dyn : VTy -> a -> SVal a
    ||| A closure: its label, its captured values, its parameter and body.
    SLam : Label -> Vect k (SVal a) -> Binder -> Term (S k) -> SVal a
    ||| A suspended computation, closure-converted like a lambda.
    SDelay : Label -> Vect k (SVal a) -> Term k -> SVal a
    ||| A constructor of static data, with its fields.
    SCon : ConId -> List (SVal a) -> SVal a
    ||| A deferred call of a function whose result is static, with the
    ||| eliminations applied to it so far (ELIM-G-5), and how many effects
    ||| had been emitted when it was built (not part of its shape).
    SCall : FnId -> Nat -> List (SVal a) -> List (Elim a) -> SVal a
    SString : SStr a -> SVal a

  ||| An elimination of a static value.
  public export
  data Elim : Type -> Type where
    Apply : SVal a -> Elim a
    Proj : ConId -> Nat -> Elim a
    ForceIt : Elim a

------------------------------------------------------------------------------
-- The typed traversal
------------------------------------------------------------------------------

traverseS : Applicative f => (VTy -> a -> f b) -> SStr a -> f (SStr b)
traverseS g (SLit s) = pure (SLit s)
traverseS g (SRun x) = SRun <$> g StrT x
traverseS g (SAppend a b) = SAppend <$> traverseS g a <*> traverseS g b
traverseS g (SCons c s) = SCons <$> g CharT c <*> traverseS g s
traverseS g (SShow t n) = SShow t <$> g (IntT t) n
traverseS g (SChr c) = SChr <$> g CharT c

mutual
  ||| Visits the atoms of a value in a fixed order, with their types. Every
  ||| other operation on atoms is an instance of it.
  export
  traverseT : Applicative f => (VTy -> a -> f b) -> SVal a -> f (SVal b)
  traverseT g (Dyn t x) = Dyn t <$> g t x
  traverseT g (SLam l caps b body) = (\cs => SLam l cs b body) <$> traverseVect g caps
  traverseT g (SDelay l caps body) = (\cs => SDelay l cs body) <$> traverseVect g caps
  traverseT g (SCon c fs) = SCon c <$> traverseList g fs
  traverseT g (SCall f e as es) = SCall f e <$> traverseList g as <*> traverseElims g es
  traverseT g (SString s) = SString <$> traverseS g s

  traverseVect : Applicative f => (VTy -> a -> f b) -> Vect k (SVal a) -> f (Vect k (SVal b))
  traverseVect g [] = pure []
  traverseVect g (v :: vs) = (::) <$> traverseT g v <*> traverseVect g vs

  traverseList : Applicative f => (VTy -> a -> f b) -> List (SVal a) -> f (List (SVal b))
  traverseList g [] = pure []
  traverseList g (v :: vs) = (::) <$> traverseT g v <*> traverseList g vs

  export
  traverseElims : Applicative f => (VTy -> a -> f b) -> List (Elim a) -> f (List (Elim b))
  traverseElims g [] = pure []
  traverseElims g (Apply v :: es) = (::) . Apply <$> traverseT g v <*> traverseElims g es
  traverseElims g (Proj c i :: es) = (Proj c i ::) <$> traverseElims g es
  traverseElims g (ForceIt :: es) = (ForceIt ::) <$> traverseElims g es

||| The static structure of a value.
export
shape : SVal a -> SVal ()
shape = runIdentity . traverseT (\_, _ => Id ())

export
shapeElims : List (Elim a) -> List (Elim ())
shapeElims = runIdentity . traverseElims (\_, _ => Id ())

||| The atoms of values and eliminations, in traversal order, with types.
export
atoms : List (SVal a) -> List (Elim a) -> List (VTy, a)
atoms vs es = execState [<] (traverseList log vs *> traverseElims log es) <>> []
  where
    log : VTy -> a -> State (SnocList (VTy, a)) ()
    log t x = modify (:< (t, x))

||| Rebuilds values with new atoms, in traversal order.
export
refill : List b -> b -> List (SVal a) -> List (Elim a) -> (List (SVal b), List (Elim b))
refill supply dflt vs es = evalState supply ((,) <$> traverseList next vs <*> traverseElims next es)
  where
    next : VTy -> a -> State (List b) b
    next _ _ = do
      xs <- get
      case xs of
        (y :: ys) => put ys $> y
        [] => pure dflt

------------------------------------------------------------------------------
-- Structural order on shapes
------------------------------------------------------------------------------

rankS : SStr a -> Nat
rankS (SLit _) = 0
rankS (SRun _) = 1
rankS (SAppend _ _) = 2
rankS (SCons _ _) = 3
rankS (SShow _ _) = 4
rankS (SChr _) = 5

cmpS : Ord a => SStr a -> SStr a -> Ordering
cmpS (SLit a) (SLit b) = compare a b
cmpS (SRun a) (SRun b) = compare a b
cmpS (SAppend a b) (SAppend c d) = cmpS a c <+> cmpS b d
cmpS (SCons a s) (SCons b t) = compare a b <+> cmpS s t
cmpS (SShow t a) (SShow u b) = compare t u <+> compare a b
cmpS (SChr a) (SChr b) = compare a b
cmpS a b = compare (rankS a) (rankS b)

rank : SVal a -> Nat
rank (Dyn _ _) = 0
rank (SLam {}) = 1
rank (SDelay {}) = 2
rank (SCon _ _) = 3
rank (SCall {}) = 4
rank (SString _) = 5

mutual
  ||| Closures compare by label: a label is one program point, so it fixes
  ||| the parameter and the body.
  cmpV : Ord a => SVal a -> SVal a -> Ordering
  cmpV (Dyn t x) (Dyn u y) = compare t u <+> compare x y
  cmpV (SLam l cs _ _) (SLam m ds _ _) = compare l m <+> cmpVect cs ds
  cmpV (SDelay l cs _) (SDelay m ds _) = compare l m <+> cmpVect cs ds
  cmpV (SCon c fs) (SCon d gs) = compare c d <+> cmpList fs gs
  cmpV (SCall f _ as es) (SCall g _ bs ds) = compare f g <+> cmpList as bs <+> cmpElims es ds
  cmpV (SString s) (SString t) = cmpS s t
  cmpV a b = compare (rank a) (rank b)

  cmpVect : Ord a => Vect k (SVal a) -> Vect j (SVal a) -> Ordering
  cmpVect [] [] = EQ
  cmpVect [] _ = LT
  cmpVect _ [] = GT
  cmpVect (x :: xs) (y :: ys) = cmpV x y <+> cmpVect xs ys

  cmpList : Ord a => List (SVal a) -> List (SVal a) -> Ordering
  cmpList [] [] = EQ
  cmpList [] _ = LT
  cmpList _ [] = GT
  cmpList (x :: xs) (y :: ys) = cmpV x y <+> cmpList xs ys

  export
  cmpElims : Ord a => List (Elim a) -> List (Elim a) -> Ordering
  cmpElims [] [] = EQ
  cmpElims [] _ = LT
  cmpElims _ [] = GT
  cmpElims (Apply x :: xs) (Apply y :: ys) = cmpV x y <+> cmpElims xs ys
  cmpElims (Proj c i :: xs) (Proj d j :: ys) = compare c d <+> compare i j <+> cmpElims xs ys
  cmpElims (ForceIt :: xs) (ForceIt :: ys) = cmpElims xs ys
  cmpElims (x :: _) (y :: _) = compare (erank x) (erank y)
    where
      erank : Elim a -> Nat
      erank (Apply _) = 0
      erank (Proj _ _) = 1
      erank ForceIt = 2

export
Ord a => Eq (SVal a) where
  a == b = cmpV a b == EQ

export
Ord a => Ord (SVal a) where
  compare = cmpV

------------------------------------------------------------------------------
-- Printing shapes (ELIM-G-3 legends, diagnostics)
------------------------------------------------------------------------------

showS : SStr () -> String
showS (SLit s) = show s
showS (SRun _) = "_:String"
showS (SAppend a b) = "(" ++ showS a ++ " ++ " ++ showS b ++ ")"
showS (SCons _ s) = "(_:Char :: " ++ showS s ++ ")"
showS (SShow t _) = "show(_:" ++ show t ++ ")"
showS (SChr _) = "str(_:Char)"

mutual
  export covering
  showShape : SVal () -> String
  showShape (Dyn t _) = "_:" ++ show t
  showShape (SLam l cs _ _) = show l ++ "[" ++ showList (toList cs) ++ "]"
  showShape (SDelay l cs _) = "delay" ++ show l.index ++ "[" ++ showList (toList cs) ++ "]"
  showShape (SCon c fs) = show c ++ "(" ++ showList fs ++ ")"
  showShape (SCall f _ as es) = show f ++ "(" ++ showList as ++ ")" ++ showElims es
  showShape (SString s) = showS s

  covering
  showList : List (SVal ()) -> String
  showList [] = ""
  showList [v] = showShape v
  showList (v :: vs) = showShape v ++ "; " ++ showList vs

  export covering
  showElims : List (Elim ()) -> String
  showElims [] = ""
  showElims (Apply v :: es) = " @(" ++ showShape v ++ ")" ++ showElims es
  showElims (Proj c i :: es) = " ." ++ show c ++ "#" ++ show i ++ showElims es
  showElims (ForceIt :: es) = " !" ++ showElims es

------------------------------------------------------------------------------
-- Growth (PROF-HEAP-4)
------------------------------------------------------------------------------

mutual
  ||| The shapes directly inside a shape.
  children : SVal () -> List (SVal ())
  children (SLam _ cs _ _) = toList cs
  children (SDelay _ cs _) = toList cs
  children (SCon _ fs) = fs
  children (SCall _ _ as es) = as ++ applied es
  children _ = []

  applied : List (Elim ()) -> List (SVal ())
  applied [] = []
  applied (Apply v :: es) = v :: applied es
  applied (_ :: es) = applied es

mutual
  ||| Homeomorphic embedding: `a` embeds in `b` when `b` is `a` with more
  ||| structure around or inside it. A recursive function whose static
  ||| arguments embed the ones it received, and differ, grows them without
  ||| bound, so specializing it would not terminate.
  export covering
  embeds : SVal () -> SVal () -> Bool
  embeds a b = couple a b || any (embeds a) (children b)

  covering
  couple : SVal () -> SVal () -> Bool
  couple (Dyn t _) (Dyn u _) = t == u
  couple (SLam l cs _ _) (SLam m ds _ _) = l == m && pairs (toList cs) (toList ds)
  couple (SDelay l cs _) (SDelay m ds _) = l == m && pairs (toList cs) (toList ds)
  couple (SCon c fs) (SCon d gs) = c == d && pairs fs gs
  couple (SCall f _ as es) (SCall g _ bs ds) = f == g && pairs as bs && cmpElims es ds == EQ
  couple (SString s) (SString t) = cmpS s t == EQ
  couple _ _ = False

  ||| Pointwise embedding of argument lists of the same length.
  export covering
  pairs : List (SVal ()) -> List (SVal ()) -> Bool
  pairs [] [] = True
  pairs (a :: as) (b :: bs) = embeds a b && pairs as bs
  pairs _ _ = False

mutual
  ||| The number of nodes of a shape: a backstop against keys that grow.
  export
  size : SVal a -> Nat
  size (SLam _ cs _ _) = S (sizeVect cs)
  size (SDelay _ cs _) = S (sizeVect cs)
  size (SCon _ fs) = S (sizeList fs)
  size (SCall _ _ as es) = S (sizeList as + sizeElims es)
  size _ = 1

  sizeVect : Vect k (SVal a) -> Nat
  sizeVect [] = 0
  sizeVect (v :: vs) = size v + sizeVect vs

  sizeList : List (SVal a) -> Nat
  sizeList [] = 0
  sizeList (v :: vs) = size v + sizeList vs

  sizeElims : List (Elim a) -> Nat
  sizeElims [] = 0
  sizeElims (Apply v :: es) = size v + sizeElims es
  sizeElims (_ :: es) = S (sizeElims es)
