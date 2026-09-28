||| Full Core (docs/architecture/05-middle-ir.md): the higher-order language
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
||| Lambdas and `Delay` are closure-converted when they are built (Futhark's
||| defunctionalisation, Hovgaard et al. TFP 2018): each carries a `Label`
||| (its program point), the variables it captures, and a body closed over
||| exactly those. The body's type does not mention `a`, so renaming never
||| enters it, and a closure's free variables are its captures.
module IdrisMLIR.Term

import IdrisMLIR.Facts
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Types

import Data.Fin
import Data.List
import Data.SortedSet
import Data.String
import Data.Vect
import Deriving.Foldable
import Deriving.Functor
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

||| What a lambda or a constructor field binds: its quantity and type.
public export
record Binder where
  constructor MkBinder
  quantity : Quantity
  type : Ty

mutual
  public export
  data Term : Type -> Type where
    Var : Loc -> a -> Term a
    Literal : Loc -> Lit -> Term a
    Erased : Loc -> Term a
    PrimApp : Loc -> Prim -> List (Term a) -> Term a
    ||| An IO primitive; its arguments end with the world, and it returns the
    ||| `IORes` instance named here.
    Effect : Loc -> IOOp -> List (Term a) -> DataId -> Term a
    ||| A saturated call.
    Call : Loc -> FnId -> List (Term a) -> Term a
    ||| A saturated constructor application; parameters are not fields.
    ConApp : Loc -> ConId -> List (Term a) -> Term a
    ||| `let`, with its quantity. TTC does not keep let types (FE-TR-1):
    ||| `Emit` synthesizes them.
    Let : Loc -> Quantity -> Term a -> Term (Under 1 a) -> Term a
    Case : Loc -> a -> List (Alt a) -> Maybe (Term a) -> Term a
    CaseLit : Loc -> a -> List (Lit, Term a) -> Term a -> Term a
    ||| A closure: its label, the captured variables, and a body closed over
    ||| them (`Free i` is capture `i`, `Bound 0` the parameter).
    Lam : {k : Nat} -> Loc -> Label -> Vect k a -> Binder -> Term (Under 1 (Fin k)) -> Term a
    App : Loc -> Term a -> Term a -> Term a
    ||| A suspended computation, closure-converted like a lambda.
    Suspend : {k : Nat} -> Loc -> Label -> Vect k a -> Term (Fin k) -> Term a
    Resume : Loc -> Term a -> Term a
    ||| A branch Idris proved impossible (`FE-TR-4`, `SEM-DATA-2`).
    Unreachable : Loc -> Term a
    ||| A case the definition does not cover: a crash (`SEM-CRASH-2`).
    Crash : Loc -> String -> Term a

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

export
locOf : Term a -> Loc
locOf (Var l _) = l
locOf (Literal l _) = l
locOf (Erased l) = l
locOf (PrimApp l _ _) = l
locOf (Effect l _ _ _) = l
locOf (Call l _ _) = l
locOf (ConApp l _ _) = l
locOf (Let l _ _ _) = l
locOf (Case l _ _ _) = l
locOf (CaseLit l _ _ _) = l
locOf (Lam l _ _ _ _) = l
locOf (App l _ _) = l
locOf (Suspend l _ _ _) = l
locOf (Resume l _) = l
locOf (Unreachable l) = l
locOf (Crash l _) = l

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
    PrimAppF : Loc -> Prim -> List (f a) -> TermF f a
    EffectF : Loc -> IOOp -> List (f a) -> DataId -> TermF f a
    CallF : Loc -> FnId -> List (f a) -> TermF f a
    ConAppF : Loc -> ConId -> List (f a) -> TermF f a
    LetF : Loc -> Quantity -> f a -> f (Under 1 a) -> TermF f a
    CaseF : Loc -> a -> List (AltF f a) -> Maybe (f a) -> TermF f a
    CaseLitF : Loc -> a -> List (Lit, f a) -> f a -> TermF f a
    LamF : {k : Nat} -> Loc -> Label -> Vect k a -> Binder -> f (Under 1 (Fin k)) -> TermF f a
    AppF : Loc -> f a -> f a -> TermF f a
    SuspendF : {k : Nat} -> Loc -> Label -> Vect k a -> f (Fin k) -> TermF f a
    ResumeF : Loc -> f a -> TermF f a
    UnreachableF : Loc -> TermF f a
    CrashF : Loc -> String -> TermF f a

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
hmap h (PrimAppF l p as) = PrimAppF l p (map h as)
hmap h (EffectF l op as res) = EffectF l op (map h as) res
hmap h (CallF l fn as) = CallF l fn (map h as)
hmap h (ConAppF l c as) = ConAppF l c (map h as)
hmap h (LetF l q v b) = LetF l q (h v) (h b)
hmap h (CaseF l x alts d) = CaseF l x (map (\(MkAltF c fs b) => MkAltF c fs (h b)) alts) (map h d)
hmap h (CaseLitF l x alts d) = CaseLitF l x (map (\(k, e) => (k, h e)) alts) (h d)
hmap h (LamF l lbl caps b body) = LamF l lbl caps b (h body)
hmap h (AppF l f x) = AppF l (h f) (h x)
hmap h (SuspendF l lbl caps body) = SuspendF l lbl caps (h body)
hmap h (ResumeF l e) = ResumeF l (h e)
hmap h (UnreachableF l) = UnreachableF l
hmap h (CrashF l m) = CrashF l m

mutual
  ||| The paramorphism: each layer with its subterms as they were and as the
  ||| algebra made them.
  export
  para : {0 f : Type -> Type} -> ({0 b : Type} -> TermF (Sub f) b -> f b) -> Term a -> f a
  para alg (Var l x) = alg (VarF l x)
  para alg (Literal l x) = alg (LiteralF l x)
  para alg (Erased l) = alg (ErasedF l)
  para alg (PrimApp l p as) = alg (PrimAppF l p (paraAll alg as))
  para alg (Effect l op as res) = alg (EffectF l op (paraAll alg as) res)
  para alg (Call l fn as) = alg (CallF l fn (paraAll alg as))
  para alg (ConApp l c as) = alg (ConAppF l c (paraAll alg as))
  para alg (Let l q v b) = alg (LetF l q (sub alg v) (sub alg b))
  para alg (Case l x alts d) = alg (CaseF l x (paraAlts alg alts) (paraMaybe alg d))
  para alg (CaseLit l x alts d) = alg (CaseLitF l x (paraLits alg alts) (sub alg d))
  para alg (Lam l lbl caps b body) = alg (LamF l lbl caps b (sub alg body))
  para alg (App l f x) = alg (AppF l (sub alg f) (sub alg x))
  para alg (Suspend l lbl caps body) = alg (SuspendF l lbl caps (sub alg body))
  para alg (Resume l e) = alg (ResumeF l (sub alg e))
  para alg (Unreachable l) = alg (UnreachableF l)
  para alg (Crash l m) = alg (CrashF l m)

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
-- Closure conversion
------------------------------------------------------------------------------

||| The free variables of a term, each once, in scope order.
export
freeVars : Ord a => Term a -> List a
freeVars t = Prelude.toList (SortedSet.fromList (toList t))

||| Closure conversion of a lambda body: it captures the body's free
||| variables and is closed over them, by strengthening. `Nothing` cannot
||| happen, since every free variable is captured.
export
lam : Ord a => Loc -> Label -> Binder -> Term (Under 1 a) -> Maybe (Term a)
lam l lbl b body =
  let caps = fromList (mapMaybe outside (freeVars body)) in
  Lam l lbl caps b <$> traverse (close caps) body
  where
    outside : Under 1 a -> Maybe a
    outside (Bound _) = Nothing
    outside (Free x) = Just x
    close : Vect k a -> Under 1 a -> Maybe (Under 1 (Fin k))
    close caps (Bound i) = Just (Bound i)
    close caps (Free x) = Free <$> elemIndex x caps

||| Closure conversion of a delayed term.
export
delay : Ord a => Loc -> Label -> Term a -> Maybe (Term a)
delay l lbl body =
  let caps = fromList (freeVars body) in
  Suspend l lbl caps <$> traverse (\x => elemIndex x caps) body

------------------------------------------------------------------------------
-- Programs
------------------------------------------------------------------------------

||| A constructor field: its quantity and type.
public export
record Field where
  constructor MkField
  quantity : Quantity
  type : Ty

public export
record Con where
  constructor MkCon
  id : ConId
  ||| The Idris full name, for the constructor's location (IDR-DATA-5).
  idrisName : Shown
  tag : Nat
  fields : List Field
  loc : Loc

||| How a data instance is represented: an unboxed sum, or a box when its
||| containment is recursive (`IDR-DATA-4`: every cycle passes through a
||| box). Data holding closures is a sum like any other.
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
-- Printing (CORE-DUMP-1)
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

printer : TermF Printed b -> Printed b
printer (VarF _ x) ix d = "#" ++ show (ix x)
printer (LiteralF _ x) ix d = show x
printer (ErasedF _) ix d = "erased"
printer (PrimAppF _ p as) ix d = show p ++ args as ix d
  where
    args : List (Printed b) -> Printed b
    args as ix d = "(" ++ joinBy ", " (map (\a => a ix d) as) ++ ")"
printer (EffectF _ op as _) ix d = "io." ++ show op ++ "(" ++ joinBy ", " (map (\a => a ix d) as) ++ ")"
printer (CallF _ fn as) ix d = show fn ++ "(" ++ joinBy ", " (map (\a => a ix d) as) ++ ")"
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
printer (LamF _ lbl caps b body) ix d =
  "\\" ++ show lbl ++ "[" ++ joinBy ", " (map (\c => "#" ++ show (ix c)) (toList caps)) ++ "](" ++
  show b.quantity ++ " " ++ show b.type ++ ") => " ++ body (under finToNat) d
printer (AppF _ f x) ix d = "(" ++ f ix d ++ " " ++ x ix d ++ ")"
printer (SuspendF _ lbl caps body) ix d =
  "delay " ++ show lbl ++ "[" ++ joinBy ", " (map (\c => "#" ++ show (ix c)) (toList caps)) ++ "] (" ++
  body finToNat d ++ ")"
printer (ResumeF _ e) ix d = "force (" ++ e ix d ++ ")"
printer (UnreachableF _) ix d = "unreachable"
printer (CrashF _ m) ix d = "crash " ++ show m

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
                   joinBy ", " (map (\f => show f.quantity ++ " " ++ show f.type) c.fields) ++ ")") d.cons ++ "\n"
    fnDecl : TFn -> String
    fnDecl f = show f.id ++ " " ++
               concatMap (\b => "(" ++ show b.quantity ++ " " ++ show b.type ++ ") ") (toList f.params) ++
               ": " ++ show f.result ++ " =\n  " ++ showBody f.body 1 ++ "\n"
