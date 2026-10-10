||| Full Core: the higher-order language
||| that `Frontend.Translate` produces from checked TT and `Emit` writes as
||| MLIR.
|||
||| `Term n` is a term in a scope of `n` variables, each a de Bruijn index
||| (`Fin n`, `0` the innermost): a binder of `k` variables holds a
||| `Term (Under k n)`, its own variables first, then the scope's outside
||| it. A closed term is a `Term 0`; a function's body is a `Term arity`,
||| parameter `i` being `i`, as in Idris's case trees. An unbound variable
||| is a type error. The scope is counted by a number, not named by a type
||| of variables, so that a traversal under a binder recurses at the same
||| types, only at another number.
|||
||| Renaming is `rename`, under a binder by `liftRen`. Every other traversal
||| is a fold over the base functor `TermF`: `cata`, or `para` where the
||| algebra needs a part as it was.
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
import Data.Fin.Split
import Data.List
import Data.String
import Data.Vect

%default total

------------------------------------------------------------------------------
-- Scopes
------------------------------------------------------------------------------

||| The scope under a binder of `k` variables, in a scope of `n`.
public export
Under : Nat -> Nat -> Nat
Under k n = k + n

||| One of a binder's own variables.
public export
Bound : {0 n : Nat} -> Fin k -> Fin (Under k n)
Bound i = weakenN n i

||| One of the variables of the scope outside a binder of `k`.
public export
Free : {k : Nat} -> Fin n -> Fin (Under k n)
Free x = shift k x

||| A variable under a binder of `k` variables: one of the binder's, or one
||| of the scope's outside it.
public export
splitUnder : {k : Nat} -> Fin (Under k n) -> Either (Fin k) (Fin n)
splitUnder v = splitSum v

||| A renaming under a binder of `k` variables: the binder's own stay, the
||| others are renamed.
export
liftRen : {k : Nat} -> (Fin n -> Fin m) -> Fin (Under k n) -> Fin (Under k m)
liftRen f v = case splitUnder {k} v of
  Left i => Bound {n = m} i
  Right x => Free {k} (f x)

------------------------------------------------------------------------------
-- Terms
------------------------------------------------------------------------------

mutual
  public export
  data Term : Nat -> Type where
    Var : Loc -> Fin n -> Term n
    Literal : Loc -> Lit -> Term n
    Erased : Loc -> Term n
    ||| A primitive, and the library definition it stands for when the
    ||| registry lowered that definition's call to it: the dump writes it,
    ||| so that what a program uses can be read off its Core, and nothing
    ||| computes with it.
    PrimApp : Loc -> Prim -> (standsFor : Maybe Shown) -> List (Term n) -> Term n
    ||| An IO primitive at the types its call fixes (an array's element, a
    ||| buffer word's type); its arguments end with the world, and it
    ||| returns the `IORes` instance named here.
    Effect : Loc -> IdrPrim -> List Ty -> List (Term n) -> DataId -> Term n
    ||| A saturated call, and the library definition it stands for when the
    ||| registry lowered that definition's call to it, as for a primitive.
    Call : Loc -> FnId -> (standsFor : Maybe Shown) -> List (Term n) -> Term n
    ||| A saturated constructor application; parameters are not fields.
    ConApp : Loc -> ConId -> List (Term n) -> Term n
    ||| `let`, with how its variable is used; an erased `let` binds the
    ||| erased value. TTC does not keep let types: `Emit` synthesizes them.
    Let : Loc -> Use -> Term n -> Term (Under 1 n) -> Term n
    Case : Loc -> Fin n -> List (Alt n) -> Maybe (Term n) -> Term n
    CaseLit : Loc -> Fin n -> List (Lit, Term n) -> Term n -> Term n
    ||| A match on a `Nat`-like value: zero, or a successor, whose
    ||| predecessor the second branch binds. The predecessor exists only
    ||| there, where the value is not zero.
    CaseNat : Loc -> Fin n -> Term n -> Term (Under 1 n) -> Term n
    ||| A lambda; its body binds the parameter (`Bound 0`).
    Lam : Loc -> Binder -> Term (Under 1 n) -> Term n
    App : Loc -> Term n -> Term n -> Term n
    ||| A suspended computation.
    Suspend : Loc -> Term n -> Term n
    Resume : Loc -> Term n -> Term n
    ||| A branch Idris proved impossible.
    Unreachable : Loc -> Term n
    ||| A case the definition does not cover: a crash.
    Crash : Loc -> String -> Term n
    ||| A world forged where a trusted library runs an IO action for a pure
    ||| value (`unsafePerformIO`): the first world of a chain of its own.
    NewWorld : Loc -> Term n
    ||| The operating system the target triple names, `System.Info.os`.
    SystemOs : Loc -> Term n
    ||| A region op of the dialect (an `IdrRegionPrim`) applied to operands,
    ||| its body binding the block arguments the primitive declares, and
    ||| its results the `IORes` instance named. `k` is `regionArity prim`,
    ||| and `types` are the types its call fixes: an array's element, and
    ||| a fold's accumulator.
    Region : {k : Nat} -> Loc -> (prim : IdrRegionPrim) -> (types : List Ty)
          -> List (Term n) -> Term (Under k n) -> DataId -> Term n

  ||| A constructor alternative binds the constructor's fields (not its
  ||| parameters): field `i` is `Bound i`.
  public export
  data Alt : Nat -> Type where
    MkAlt : {k : Nat} -> ConId -> Vect k Binder -> Term (Under k n) -> Alt n

-- Renaming, by structural recursion through `Term` and `Alt` together.

mutual
  ||| The term with each variable renamed.
  export
  rename : (Fin n -> Fin m) -> Term n -> Term m
  rename f (Var l x) = Var l (f x)
  rename f (Literal l x) = Literal l x
  rename f (Erased l) = Erased l
  rename f (PrimApp l p stands as) = PrimApp l p stands (renameAll f as)
  rename f (Effect l p tys as res) = Effect l p tys (renameAll f as) res
  rename f (Call l fn stands as) = Call l fn stands (renameAll f as)
  rename f (ConApp l c as) = ConApp l c (renameAll f as)
  rename f (Let l q v b) = Let l q (rename f v) (rename (liftRen {k = 1} f) b)
  rename f (Case l x alts d) = Case l (f x) (renameAlts f alts) (renameDefault f d)
  rename f (CaseLit l x alts d) = CaseLit l (f x) (renameLits f alts) (rename f d)
  rename f (CaseNat l x z s) = CaseNat l (f x) (rename f z) (rename (liftRen {k = 1} f) s)
  rename f (Lam l b body) = Lam l b (rename (liftRen {k = 1} f) body)
  rename f (App l g x) = App l (rename f g) (rename f x)
  rename f (Suspend l body) = Suspend l (rename f body)
  rename f (Resume l e) = Resume l (rename f e)
  rename f (Unreachable l) = Unreachable l
  rename f (Crash l m) = Crash l m
  rename f (NewWorld l) = NewWorld l
  rename f (SystemOs l) = SystemOs l
  rename f (Region {k} l p tys as body res) = Region l p tys (renameAll f as) (rename (liftRen {k} f) body) res

  renameAll : (Fin n -> Fin m) -> List (Term n) -> List (Term m)
  renameAll f [] = []
  renameAll f (t :: ts) = rename f t :: renameAll f ts

  renameDefault : (Fin n -> Fin m) -> Maybe (Term n) -> Maybe (Term m)
  renameDefault f Nothing = Nothing
  renameDefault f (Just t) = Just (rename f t)

  renameLits : (Fin n -> Fin m) -> List (Lit, Term n) -> List (Lit, Term m)
  renameLits f [] = []
  renameLits f ((k, t) :: rest) = (k, rename f t) :: renameLits f rest

  renameAlt : (Fin n -> Fin m) -> Alt n -> Alt m
  renameAlt f (MkAlt {k} c fs body) = MkAlt c fs (rename (liftRen {k} f) body)

  renameAlts : (Fin n -> Fin m) -> List (Alt n) -> List (Alt m)
  renameAlts f [] = []
  renameAlts f (alt :: alts) = renameAlt f alt :: renameAlts f alts

||| The term under a binder of `k` variables it does not use.
export
weakenUnder : (k : Nat) -> Term n -> Term (Under k n)
weakenUnder k = rename (Free {k})

------------------------------------------------------------------------------
-- The base functor and its folds
------------------------------------------------------------------------------

mutual
  ||| One layer of `Term`, its subterms replaced by `f` at their scopes: a
  ||| higher-order base functor, since a subterm under a binder is in a
  ||| larger scope than the term itself.
  public export
  data TermF : (Nat -> Type) -> Nat -> Type where
    VarF : Loc -> Fin n -> TermF f n
    LiteralF : Loc -> Lit -> TermF f n
    ErasedF : Loc -> TermF f n
    PrimAppF : Loc -> Prim -> Maybe Shown -> List (f n) -> TermF f n
    EffectF : Loc -> IdrPrim -> List Ty -> List (f n) -> DataId -> TermF f n
    CallF : Loc -> FnId -> Maybe Shown -> List (f n) -> TermF f n
    ConAppF : Loc -> ConId -> List (f n) -> TermF f n
    LetF : Loc -> Use -> f n -> f (Under 1 n) -> TermF f n
    CaseF : Loc -> Fin n -> List (AltF f n) -> Maybe (f n) -> TermF f n
    CaseLitF : Loc -> Fin n -> List (Lit, f n) -> f n -> TermF f n
    CaseNatF : Loc -> Fin n -> f n -> f (Under 1 n) -> TermF f n
    LamF : Loc -> Binder -> f (Under 1 n) -> TermF f n
    AppF : Loc -> f n -> f n -> TermF f n
    SuspendF : Loc -> f n -> TermF f n
    ResumeF : Loc -> f n -> TermF f n
    UnreachableF : Loc -> TermF f n
    CrashF : Loc -> String -> TermF f n
    NewWorldF : Loc -> TermF f n
    SystemOsF : Loc -> TermF f n
    RegionF : {k : Nat} -> Loc -> IdrRegionPrim -> List Ty -> List (f n) -> f (Under k n) -> DataId -> TermF f n

  public export
  data AltF : (Nat -> Type) -> Nat -> Type where
    MkAltF : {k : Nat} -> ConId -> Vect k Binder -> f (Under k n) -> AltF f n

||| A subterm as it was, with what the fold made of it (for `para`).
public export
record Sub (f : Nat -> Type) (n : Nat) where
  constructor MkSub
  term : Term n
  result : f n

||| The action of `TermF` on a natural transformation.
export
hmap : ({0 m : Nat} -> f m -> g m) -> TermF f n -> TermF g n
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
  para : {0 f : Nat -> Type} -> ({0 m : Nat} -> TermF (Sub f) m -> f m) -> Term n -> f n
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

  sub : {0 f : Nat -> Type} -> ({0 m : Nat} -> TermF (Sub f) m -> f m) -> Term n -> Sub f n
  sub alg t = MkSub t (para alg t)

  paraAll : {0 f : Nat -> Type} -> ({0 m : Nat} -> TermF (Sub f) m -> f m) ->
            List (Term n) -> List (Sub f n)
  paraAll alg [] = []
  paraAll alg (t :: ts) = sub alg t :: paraAll alg ts

  paraMaybe : {0 f : Nat -> Type} -> ({0 m : Nat} -> TermF (Sub f) m -> f m) ->
              Maybe (Term n) -> Maybe (Sub f n)
  paraMaybe alg Nothing = Nothing
  paraMaybe alg (Just t) = Just (sub alg t)

  paraLits : {0 f : Nat -> Type} -> ({0 m : Nat} -> TermF (Sub f) m -> f m) ->
             List (Lit, Term n) -> List (Lit, Sub f n)
  paraLits alg [] = []
  paraLits alg ((k, t) :: rest) = (k, sub alg t) :: paraLits alg rest

  paraAlts : {0 f : Nat -> Type} -> ({0 m : Nat} -> TermF (Sub f) m -> f m) ->
             List (Alt n) -> List (AltF (Sub f) n)
  paraAlts alg [] = []
  paraAlts alg (MkAlt c fs body :: rest) = MkAltF c fs (sub alg body) :: paraAlts alg rest

||| The catamorphism: each layer with what the algebra made of its subterms.
export
cata : {0 f : Nat -> Type} -> ({0 m : Nat} -> TermF f m -> f m) -> Term n -> f n
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
  body : Term arity
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

||| What the printer makes of a term in scope `n`: given each variable's de
||| Bruijn index (`#0` is the innermost) and the indentation depth.
Printed : Nat -> Type
Printed n = (Fin n -> Nat) -> Nat -> String

||| The indices under a binder of `k` variables.
under : {k : Nat} -> (Fin n -> Nat) -> Fin (Under k n) -> Nat
under ix v = case splitUnder {k} v of
  Left i => finToNat i
  Right x => k + ix x

||| The library definition a lowered primitive or call stands for, in braces
||| after its head, as an implementation is written after its method.
standing : Maybe Shown -> String
standing Nothing = ""
standing (Just q) = "{" ++ show q ++ "}"

||| The types a primitive's call fixes, in angle brackets after its head.
typeArgs : List Ty -> String
typeArgs [] = ""
typeArgs ts = "<" ++ joinBy ", " (map show ts) ++ ">"

||| A region primitive by its constructor's name, as the dump writes it.
regionName : IdrRegionPrim -> String
regionName ArrayGenerate = "ArrayGenerate"
regionName ArrayFold = "ArrayFold"

printer : TermF Printed n -> Printed n
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
  "let " ++ show q ++ " = " ++ v ix (S d) ++ "\n" ++ indent d ++ b (under {k = 1} ix) d
printer (CaseF _ x alts def) ix d =
  "case #" ++ show (ix x) ++ " of" ++ concatMap alt alts ++
  maybe "" (\e => "\n" ++ indent (S d) ++ "_ => " ++ e ix (S (S d))) def
  where
    alt : AltF Printed n -> String
    alt (MkAltF {k} c fs body) =
      "\n" ++ indent (S d) ++ show c ++ "/" ++ show (length fs) ++ " => " ++ body (under {k} ix) (S (S d))
printer (CaseLitF _ x alts def) ix d =
  "case #" ++ show (ix x) ++ " of" ++
  concatMap (\(k, e) => "\n" ++ indent (S d) ++ show k ++ " => " ++ e ix (S (S d))) alts ++
  "\n" ++ indent (S d) ++ "_ => " ++ def ix (S (S d))
printer (CaseNatF _ x z s) ix d =
  "case #" ++ show (ix x) ++ " of" ++
  "\n" ++ indent (S d) ++ "0 => " ++ z ix (S (S d)) ++
  "\n" ++ indent (S d) ++ "S _ => " ++ s (under {k = 1} ix) (S (S d))
printer (LamF _ b body) ix d = "\\(" ++ show b ++ ") => " ++ body (under {k = 1} ix) d
printer (AppF _ f x) ix d = "(" ++ f ix d ++ " " ++ x ix d ++ ")"
printer (SuspendF _ body) ix d = "delay (" ++ body ix d ++ ")"
printer (ResumeF _ e) ix d = "force (" ++ e ix d ++ ")"
printer (UnreachableF _) ix d = "unreachable"
printer (CrashF _ m) ix d = "crash " ++ show m
printer (NewWorldF _) ix d = "new-world"
printer (SystemOsF _) ix d = "os"
printer (RegionF {k} _ p tys as body _) ix d =
  "io." ++ regionName p ++ typeArgs tys ++ "(" ++ joinBy ", " (map (\a => a ix d) as) ++ ")/" ++
  show k ++ " => " ++ body (under {k} ix) d

||| A function body, parameter `i` being `#i`.
export
showBody : Term n -> Nat -> String
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
