||| Full Core: the higher-order language
||| that `Frontend.Translate` produces from checked TT and `Emit` writes as
||| MLIR.
|||
||| `Term a` is a nested datatype (Bird and Paterson, "de Bruijn notation as
||| a nested datatype", JFP 1999): its free variables have type `a`, and a
||| binder of `k` variables holds a `Term (Under k a)`. A closed term is a
||| `Term Void`; a function's body is a `Term (Fin arity)`, parameter `i`
||| being `i`, as in Idris's case trees. An unbound variable is a type error.
|||
||| Renaming is the derived `Functor`, the free variables are the derived
||| `Foldable`, and strengthening is the derived `Traversable` (base's
||| `Deriving.*`). Every other traversal is a fold over the base functor
||| `TermF`: `cata`, or `para` where the algebra needs a part as it was.
|||
||| A lambda's or a `Delay`'s body stays in the scope it is written in, as a
||| `let`'s does: renaming enters it, and the variables of that scope it
||| uses are its captures. `Emit` writes it as a region, and `idr-isolate`
||| makes that region a function of its own.
module IdrisMLIR.Term

import IdrisMLIR.Dialect.Idr
import IdrisMLIR.Facts
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Types

import Data.Fin
import Data.List
import Data.String
import Data.Vect
import Deriving.Foldable
import Deriving.Functor
import Deriving.Show
import Deriving.Traversable

%language ElabReflection
%default total

------------------------------------------------------------------------------
-- Scopes
------------------------------------------------------------------------------

||| A variable under a binder of `k` variables: one of them, or one of the
||| scope outside.
public export
data Under : Nat -> Type -> Type where
  Bound : Fin k -> Under k a
  Free : a -> Under k a

%hint export
underFunctor : Functor (Under k)
underFunctor = %runElab derive

%hint export
underFoldable : Foldable (Under k)
underFoldable = %runElab derive

%hint export
underTraversable : Traversable (Under k)
underTraversable = %runElab derive

export
Eq a => Eq (Under k a) where
  Bound i == Bound j = i == j
  Free x == Free y = x == y
  _ == _ = False

||| The binder's own variables first, as de Bruijn indices are ordered.
export
Ord a => Ord (Under k a) where
  compare (Bound i) (Bound j) = compare i j
  compare (Bound _) (Free _) = LT
  compare (Free _) (Bound _) = GT
  compare (Free x) (Free y) = compare x y

------------------------------------------------------------------------------
-- Terms
------------------------------------------------------------------------------

mutual
  public export
  data Term : Type -> Type where
    Var : Loc -> a -> Term a
    Literal : Loc -> Lit -> Term a
    Erased : Loc -> Term a
    ||| A primitive, and the library definition it stands for when the
    ||| registry lowered that definition's call to it: the dump writes it,
    ||| so that what a program uses can be read off its Core, and nothing
    ||| computes with it.
    PrimApp : Loc -> Prim -> (standsFor : Maybe Shown) -> List (Term a) -> Term a
    ||| An IO primitive at the types its call fixes (an array's element, a
    ||| buffer word's type); its arguments end with the world, and it
    ||| returns the `IORes` instance named here.
    Effect : Loc -> IdrPrim -> List Ty -> List (Term a) -> DataId -> Term a
    ||| A saturated call, and the library definition it stands for when the
    ||| registry lowered that definition's call to it, as for a primitive.
    Call : Loc -> FnId -> (standsFor : Maybe Shown) -> List (Term a) -> Term a
    ||| A saturated constructor application; parameters are not fields.
    ConApp : Loc -> ConId -> List (Term a) -> Term a
    ||| `let`, with how its variable is used; an erased `let` binds the
    ||| erased value. TTC does not keep let types: `Emit` synthesizes them.
    Let : Loc -> Use -> Term a -> Term (Under 1 a) -> Term a
    Case : Loc -> a -> List (Alt a) -> Maybe (Term a) -> Term a
    CaseLit : Loc -> a -> List (Lit, Term a) -> Term a -> Term a
    ||| A match on a `Nat`-like value: zero, or a successor, whose
    ||| predecessor the second branch binds. The predecessor exists only
    ||| there, where the value is not zero.
    CaseNat : Loc -> a -> Term a -> Term (Under 1 a) -> Term a
    ||| A lambda; its body binds the parameter (`Bound 0`).
    Lam : Loc -> Binder -> Term (Under 1 a) -> Term a
    App : Loc -> Term a -> Term a -> Term a
    ||| A suspended computation.
    Suspend : Loc -> Term a -> Term a
    Resume : Loc -> Term a -> Term a
    ||| A branch Idris proved impossible.
    Unreachable : Loc -> Term a
    ||| A case the definition does not cover: a crash.
    Crash : Loc -> String -> Term a
    ||| A world forged where a trusted library runs an IO action for a pure
    ||| value (`unsafePerformIO`): the first world of a chain of its own.
    NewWorld : Loc -> Term a
    ||| The operating system the target triple names, `System.Info.os`.
    SystemOs : Loc -> Term a
    ||| A region op of the dialect (an `IdrRegionPrim`) applied to operands,
    ||| its body binding the block arguments the primitive declares, and
    ||| its results the `IORes` instance named. `k` is `regionArity prim`,
    ||| and `types` are the types its call fixes: an array's element, and
    ||| a fold's accumulator.
    Region : {k : Nat} -> Loc -> (prim : IdrRegionPrim) -> (types : List Ty)
          -> List (Term a) -> Term (Under k a) -> DataId -> Term a

  ||| A constructor alternative binds the constructor's fields (not its
  ||| parameters): field `i` is `Bound i`.
  public export
  data Alt : Type -> Type where
    MkAlt : {k : Nat} -> ConId -> Vect k Binder -> Term (Under k a) -> Alt a

-- `Term` and `Alt` are mutually recursive, so each derivation names the
-- other: base's deriving then marks the calls between them as total, which
-- its termination checker cannot see through the other's instance.
mutual
  %hint export
  altFunctor : Functor Alt
  altFunctor = %runElab derive {mutualWith = [`{Term}]}

  %hint export
  termFunctor : Functor Term
  termFunctor = %runElab derive {mutualWith = [`{Alt}]}

mutual
  %hint export
  altFoldable : Foldable Alt
  altFoldable = %runElab derive {mutualWith = [`{Term}]}

  %hint export
  termFoldable : Foldable Term
  termFoldable = %runElab derive {mutualWith = [`{Alt}]}

mutual
  %hint export
  altTraversable : Traversable Alt
  altTraversable = %runElab derive {mutualWith = [`{Term}]}

  %hint export
  termTraversable : Traversable Term
  termTraversable = %runElab derive {mutualWith = [`{Alt}]}

------------------------------------------------------------------------------
-- The base functor and its folds
------------------------------------------------------------------------------

mutual
  ||| One layer of `Term`, its subterms replaced by `f` at their scopes: a
  ||| higher-order base functor, since a nested datatype's subterms live in
  ||| other scopes than the term itself.
  public export
  data TermF : (Type -> Type) -> Type -> Type where
    VarF : Loc -> a -> TermF f a
    LiteralF : Loc -> Lit -> TermF f a
    ErasedF : Loc -> TermF f a
    PrimAppF : Loc -> Prim -> Maybe Shown -> List (f a) -> TermF f a
    EffectF : Loc -> IdrPrim -> List Ty -> List (f a) -> DataId -> TermF f a
    CallF : Loc -> FnId -> Maybe Shown -> List (f a) -> TermF f a
    ConAppF : Loc -> ConId -> List (f a) -> TermF f a
    LetF : Loc -> Use -> f a -> f (Under 1 a) -> TermF f a
    CaseF : Loc -> a -> List (AltF f a) -> Maybe (f a) -> TermF f a
    CaseLitF : Loc -> a -> List (Lit, f a) -> f a -> TermF f a
    CaseNatF : Loc -> a -> f a -> f (Under 1 a) -> TermF f a
    LamF : Loc -> Binder -> f (Under 1 a) -> TermF f a
    AppF : Loc -> f a -> f a -> TermF f a
    SuspendF : Loc -> f a -> TermF f a
    ResumeF : Loc -> f a -> TermF f a
    UnreachableF : Loc -> TermF f a
    CrashF : Loc -> String -> TermF f a
    NewWorldF : Loc -> TermF f a
    SystemOsF : Loc -> TermF f a
    RegionF : {k : Nat} -> Loc -> IdrRegionPrim -> List Ty -> List (f a) -> f (Under k a) -> DataId -> TermF f a

  public export
  data AltF : (Type -> Type) -> Type -> Type where
    MkAltF : {k : Nat} -> ConId -> Vect k Binder -> f (Under k a) -> AltF f a

||| A subterm as it was, with what the fold made of it (for `para`).
public export
record Sub (f : Type -> Type) (a : Type) where
  constructor MkSub
  term : Term a
  result : f a

||| The action of `TermF` on a natural transformation.
export
hmap : ({0 c : Type} -> f c -> g c) -> TermF f a -> TermF g a
hmap h (VarF l x) = VarF l x
hmap h (LiteralF l x) = LiteralF l x
hmap h (ErasedF l) = ErasedF l
hmap h (PrimAppF l p stands as) = PrimAppF l p stands (map h as)
hmap h (EffectF l p tys as res) = EffectF l p tys (map h as) res
hmap h (CallF l fn stands as) = CallF l fn stands (map h as)
hmap h (ConAppF l c as) = ConAppF l c (map h as)
hmap h (LetF l q v b) = LetF l q (h v) (h b)
hmap h (CaseF l x alts d) = CaseF l x (map (\(MkAltF c fs b) => MkAltF c fs (h b)) alts) (map h d)
hmap h (CaseLitF l x alts d) = CaseLitF l x (map (\(k, e) => (k, h e)) alts) (h d)
hmap h (CaseNatF l x z s) = CaseNatF l x (h z) (h s)
hmap h (LamF l b body) = LamF l b (h body)
hmap h (AppF l f x) = AppF l (h f) (h x)
hmap h (SuspendF l body) = SuspendF l (h body)
hmap h (ResumeF l e) = ResumeF l (h e)
hmap h (UnreachableF l) = UnreachableF l
hmap h (CrashF l m) = CrashF l m
hmap h (NewWorldF l) = NewWorldF l
hmap h (SystemOsF l) = SystemOsF l
hmap h (RegionF l p tys as body res) = RegionF l p tys (map h as) (h body) res

mutual
  ||| The paramorphism: each layer with its subterms as they were and as the
  ||| algebra made them.
  export
  para : {0 f : Type -> Type} -> ({0 b : Type} -> TermF (Sub f) b -> f b) -> Term a -> f a
  para alg (Var l x) = alg (VarF l x)
  para alg (Literal l x) = alg (LiteralF l x)
  para alg (Erased l) = alg (ErasedF l)
  para alg (PrimApp l p stands as) = alg (PrimAppF l p stands (paraAll alg as))
  para alg (Effect l p tys as res) = alg (EffectF l p tys (paraAll alg as) res)
  para alg (Call l fn stands as) = alg (CallF l fn stands (paraAll alg as))
  para alg (ConApp l c as) = alg (ConAppF l c (paraAll alg as))
  para alg (Let l q v b) = alg (LetF l q (sub alg v) (sub alg b))
  para alg (Case l x alts d) = alg (CaseF l x (paraAlts alg alts) (paraMaybe alg d))
  para alg (CaseLit l x alts d) = alg (CaseLitF l x (paraLits alg alts) (sub alg d))
  para alg (CaseNat l x z s) = alg (CaseNatF l x (sub alg z) (sub alg s))
  para alg (Lam l b body) = alg (LamF l b (sub alg body))
  para alg (App l f x) = alg (AppF l (sub alg f) (sub alg x))
  para alg (Suspend l body) = alg (SuspendF l (sub alg body))
  para alg (Resume l e) = alg (ResumeF l (sub alg e))
  para alg (Unreachable l) = alg (UnreachableF l)
  para alg (Crash l m) = alg (CrashF l m)
  para alg (NewWorld l) = alg (NewWorldF l)
  para alg (SystemOs l) = alg (SystemOsF l)
  para alg (Region l p tys as body res) = alg (RegionF l p tys (paraAll alg as) (sub alg body) res)

  sub : {0 f : Type -> Type} -> ({0 b : Type} -> TermF (Sub f) b -> f b) -> Term a -> Sub f a
  sub alg t = MkSub t (para alg t)

  paraAll : {0 f : Type -> Type} -> ({0 b : Type} -> TermF (Sub f) b -> f b) ->
            List (Term a) -> List (Sub f a)
  paraAll alg [] = []
  paraAll alg (t :: ts) = sub alg t :: paraAll alg ts

  paraMaybe : {0 f : Type -> Type} -> ({0 b : Type} -> TermF (Sub f) b -> f b) ->
              Maybe (Term a) -> Maybe (Sub f a)
  paraMaybe alg Nothing = Nothing
  paraMaybe alg (Just t) = Just (sub alg t)

  paraLits : {0 f : Type -> Type} -> ({0 b : Type} -> TermF (Sub f) b -> f b) ->
             List (Lit, Term a) -> List (Lit, Sub f a)
  paraLits alg [] = []
  paraLits alg ((k, t) :: rest) = (k, sub alg t) :: paraLits alg rest

  paraAlts : {0 f : Type -> Type} -> ({0 b : Type} -> TermF (Sub f) b -> f b) ->
             List (Alt a) -> List (AltF (Sub f) a)
  paraAlts alg [] = []
  paraAlts alg (MkAlt c fs body :: rest) = MkAltF c fs (sub alg body) :: paraAlts alg rest

||| The catamorphism: each layer with what the algebra made of its subterms.
export
cata : {0 f : Type -> Type} -> ({0 b : Type} -> TermF f b -> f b) -> Term a -> f a
cata alg = para (\layer => alg (hmap (.result) layer))

------------------------------------------------------------------------------
-- Programs
------------------------------------------------------------------------------

public export
record Con where
  constructor MkCon
  id : ConId
  ||| The Idris full name, for the constructor's location.
  idrisName : Shown
  tag : Nat
  fields : List Binder
  loc : Loc

||| How a data instance is represented: an unboxed sum, or a box when its
||| containment is recursive (every cycle passes through a box). Data holding closures is a sum like any other.
||| This is the Idris side's decision, and recursion its only reason: a
||| single-constructor Sop may still become a box in idr-defunctionalize, when
||| a cell holding its values would count more references than a header can,
||| which only idr.layout measures.
public export
data Repr = Sop | Box

public export
record Data where
  constructor MkData
  id : DataId
  idrisName : Shown
  cons : List Con
  loc : Loc
  repr : Repr

||| A function instance of full Core.
public export
record TFn where
  constructor MkTFn
  id : FnId
  idrisName : Shown
  arity : Nat
  params : Vect arity Binder
  result : Ty
  body : Term (Fin arity)
  loc : Loc
  facts : Facts

||| A whole program in full Core. Its root is the only function the module
||| exports, and its type says what kind of program it is (`main : Int`,
||| or world-passing IO).
public export
record Source where
  constructor MkSource
  datas : List IdrisMLIR.Term.Data
  fns : List TFn
  root : FnId

------------------------------------------------------------------------------
-- Printing
------------------------------------------------------------------------------

indent : Nat -> String
indent d = replicate (2 * d) ' '

||| What the printer makes of a term in scope `b`: given each variable's de
||| Bruijn index (`#0` is the innermost) and the indentation depth.
Printed : Type -> Type
Printed b = (b -> Nat) -> Nat -> String

||| The indices under a binder of `k` variables.
under : {k : Nat} -> (b -> Nat) -> Under k b -> Nat
under ix (Bound i) = finToNat i
under ix (Free x) = k + ix x

||| The library definition a lowered primitive or call stands for, in braces
||| after its head, as an implementation is written after its method.
standing : Maybe Shown -> String
standing Nothing = ""
standing (Just q) = "{" ++ show q ++ "}"

||| The types a primitive's call fixes, in angle brackets after its head.
typeArgs : List Ty -> String
typeArgs [] = ""
typeArgs ts = "<" ++ joinBy ", " (map show ts) ++ ">"

||| A region primitive by its constructor's name. Not a hint: the dump is
||| its one reader.
regionShow : Show IdrRegionPrim
regionShow = %runElab derive

printer : TermF Printed b -> Printed b
printer (VarF _ x) ix d = "#" ++ show (ix x)
printer (LiteralF _ x) ix d = show x
printer (ErasedF _) ix d = "erased"
printer (PrimAppF _ p stands as) ix d = show p ++ standing stands ++ "(" ++ joinBy ", " (map (\a => a ix d) as) ++ ")"
printer (EffectF _ p tys as _) ix d =
  "io." ++ show (Op p) ++ typeArgs tys ++ "(" ++ joinBy ", " (map (\a => a ix d) as) ++ ")"
printer (CallF _ fn stands as) ix d = show fn ++ standing stands ++ "(" ++ joinBy ", " (map (\a => a ix d) as) ++ ")"
printer (ConAppF _ c as) ix d =
  show c.dataId ++ "::" ++ show c ++ "(" ++ joinBy ", " (map (\a => a ix d) as) ++ ")"
printer (LetF _ q v b) ix d =
  "let " ++ show q ++ " = " ++ v ix (S d) ++ "\n" ++ indent d ++ b (under ix) d
printer (CaseF _ x alts def) ix d =
  "case #" ++ show (ix x) ++ " of" ++ concatMap alt alts ++
  maybe "" (\e => "\n" ++ indent (S d) ++ "_ => " ++ e ix (S (S d))) def
  where
    alt : AltF Printed b -> String
    alt (MkAltF c fs body) =
      "\n" ++ indent (S d) ++ show c ++ "/" ++ show (length fs) ++ " => " ++ body (under ix) (S (S d))
printer (CaseLitF _ x alts def) ix d =
  "case #" ++ show (ix x) ++ " of" ++
  concatMap (\(k, e) => "\n" ++ indent (S d) ++ show k ++ " => " ++ e ix (S (S d))) alts ++
  "\n" ++ indent (S d) ++ "_ => " ++ def ix (S (S d))
printer (CaseNatF _ x z s) ix d =
  "case #" ++ show (ix x) ++ " of" ++
  "\n" ++ indent (S d) ++ "0 => " ++ z ix (S (S d)) ++
  "\n" ++ indent (S d) ++ "S _ => " ++ s (under ix) (S (S d))
printer (LamF _ b body) ix d = "\\(" ++ show b ++ ") => " ++ body (under ix) d
printer (AppF _ f x) ix d = "(" ++ f ix d ++ " " ++ x ix d ++ ")"
printer (SuspendF _ body) ix d = "delay (" ++ body ix d ++ ")"
printer (ResumeF _ e) ix d = "force (" ++ e ix d ++ ")"
printer (UnreachableF _) ix d = "unreachable"
printer (CrashF _ m) ix d = "crash " ++ show m
printer (NewWorldF _) ix d = "new-world"
printer (SystemOsF _) ix d = "os"
printer (RegionF {k} _ p tys as body _) ix d =
  "io." ++ show @{regionShow} p ++ typeArgs tys ++ "(" ++ joinBy ", " (map (\a => a ix d) as) ++ ")/" ++
  show k ++ " => " ++ body (under ix) d

||| A function body, parameter `i` being `#i`.
export
showBody : Term (Fin n) -> Nat -> String
showBody t = cata printer t finToNat

export
showSource : Source -> String
showSource p = unlines (map dataDecl p.datas ++ map fnDecl p.fns ++ ["root " ++ show p.root])
  where
    repr : Repr -> String
    repr Sop = ""
    repr Box = " (box)"
    dataDecl : IdrisMLIR.Term.Data -> String
    dataDecl d = "data " ++ show d.id ++ repr d.repr ++
                 concatMap (\c => "\n  " ++ show c.id ++ " tag " ++ show c.tag ++ " (" ++
                   joinBy ", " (map show c.fields) ++ ")") d.cons ++ "\n"
    fnDecl : TFn -> String
    fnDecl f = show f.id ++ " " ++
               concatMap (\b => "(" ++ show b ++ ") ") (toList f.params) ++
               ": " ++ show f.result ++ " =\n  " ++ showBody f.body 1 ++ "\n"
