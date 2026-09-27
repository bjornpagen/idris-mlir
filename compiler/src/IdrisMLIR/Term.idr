||| Full Core (docs/architecture/05-middle-ir.md): the higher-order language
||| that `Frontend.Translate` produces from checked TT and `Simplify`
||| evaluates away.
|||
||| Terms are well scoped: `Term n` has `n` variables in scope, as de Bruijn
||| indices (`Fin n`), like Idris's own `Term vars`. Index 0 is the innermost
||| binder. A function's body is in scope of its arity, and parameter `i` is
||| variable `i`, as in Idris's case trees. An unbound variable is a type
||| error, so CORE-INV-1 holds by construction.
|||
||| Lambdas and `Delay` are closure-converted when they are built (Futhark's
||| defunctionalisation, Hovgaard et al. TFP 2018): each carries a `Label`
||| (its program point) and the list of variables it captures, and its body is
||| closed over exactly those. A closure is therefore a label and a record of
||| captured values, and renaming never enters a closure body.
module IdrisMLIR.Term

import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Types

import Control.Monad.Identity
import Data.Fin
import Data.Fin.Split
import Data.List
import Data.SortedMap
import Data.SortedSet
import Data.String
import Data.Vect

%default total

------------------------------------------------------------------------------
-- Terms
------------------------------------------------------------------------------

||| What a lambda binds: its quantity and type.
public export
record Binder where
  constructor MkBinder
  quantity : Quantity
  type : Ty

mutual
  public export
  data Term : Nat -> Type where
    Var : Loc -> Fin n -> Term n
    Literal : Loc -> Lit -> Term n
    Erased : Loc -> Term n
    PrimApp : Loc -> PrimOp -> List (Term n) -> Term n
    ||| An IO primitive; its arguments end with the world, and it returns the
    ||| `IORes` instance named here.
    Effect : Loc -> IOOp -> List (Term n) -> DataId -> Term n
    ||| A saturated call.
    Call : Loc -> FnId -> List (Term n) -> Term n
    ||| A saturated constructor application; parameters are not fields.
    ConApp : Loc -> ConId -> List (Term n) -> Term n
    ||| `let`. TTC does not keep let types, and nothing needs them: the
    ||| value's type is known when it is evaluated.
    Let : Loc -> Quantity -> Term n -> Term (S n) -> Term n
    Case : Loc -> Fin n -> List (Alt n) -> Maybe (Term n) -> Term n
    CaseLit : Loc -> Fin n -> List (Lit, Term n) -> Term n -> Term n
    ||| A closure: its label, the captured variables, and a body closed over
    ||| the captures (index 0 is the parameter).
    Lam : Loc -> Label -> (caps : Vect k (Fin n)) -> Binder -> Term (S k) -> Term n
    App : Loc -> Term n -> Term n -> Term n
    ||| A suspended computation, closure-converted like a lambda.
    Suspend : Loc -> Label -> (caps : Vect k (Fin n)) -> Term k -> Term n
    Resume : Loc -> Term n -> Term n
    ||| A branch Idris proved impossible (`FE-TR-4`, `SEM-DATA-2`).
    Unreachable : Loc -> Term n
    ||| A case the definition does not cover: a crash (`SEM-CRASH-2`).
    Crash : Loc -> String -> Term n

  ||| A constructor alternative binds the constructor's fields (not its
  ||| parameters), the first field at index 0.
  public export
  data Alt : Nat -> Type where
    MkAlt : ConId -> (fields : List Binder) -> Term (length fields + n) -> Alt n

export
locOf : Term n -> Loc
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
-- Renaming
------------------------------------------------------------------------------

||| A renaming under one more binder.
lift : Applicative f => (Fin n -> f (Fin m)) -> Fin (S n) -> f (Fin (S m))
lift r FZ = pure FZ
lift r (FS i) = FS <$> r i

||| A renaming under `k` more binders.
liftN : Applicative f => (k : Nat) -> (Fin n -> f (Fin m)) -> Fin (k + n) -> f (Fin (k + m))
liftN k r i = case splitSum {m = k} i of
  Left j => pure (indexSum (Left j))
  Right j => indexSum . Right <$> r j

mutual
  ||| Renames the free variables of a term, in any applicative: `Identity` to
  ||| weaken, `Maybe` to strengthen. Closure bodies are closed, so only their
  ||| capture lists are renamed.
  export
  rename : Applicative f => (Fin n -> f (Fin m)) -> Term n -> f (Term m)
  rename r (Var l i) = Var l <$> r i
  rename r (Literal l x) = pure (Literal l x)
  rename r (Erased l) = pure (Erased l)
  rename r (PrimApp l op as) = PrimApp l op <$> renameAll r as
  rename r (Effect l op as res) = (\as' => Effect l op as' res) <$> renameAll r as
  rename r (Call l f as) = Call l f <$> renameAll r as
  rename r (ConApp l c as) = ConApp l c <$> renameAll r as
  rename r (Let l q v b) = Let l q <$> rename r v <*> rename (lift r) b
  rename r (Case l x alts d) =
    Case l <$> r x <*> renameAlts r alts <*> renameMaybe r d
  rename r (CaseLit l x alts d) =
    CaseLit l <$> r x <*> renameLits r alts <*> rename r d
  rename r (Lam l lbl caps b body) = (\caps' => Lam l lbl caps' b body) <$> traverse r caps
  rename r (App l f a) = App l <$> rename r f <*> rename r a
  rename r (Suspend l lbl caps body) = (\caps' => Suspend l lbl caps' body) <$> traverse r caps
  rename r (Resume l e) = Resume l <$> rename r e
  rename r (Unreachable l) = pure (Unreachable l)
  rename r (Crash l m) = pure (Crash l m)

  renameAll : Applicative f => (Fin n -> f (Fin m)) -> List (Term n) -> f (List (Term m))
  renameAll r [] = pure []
  renameAll r (t :: ts) = (::) <$> rename r t <*> renameAll r ts

  renameMaybe : Applicative f => (Fin n -> f (Fin m)) -> Maybe (Term n) -> f (Maybe (Term m))
  renameMaybe r Nothing = pure Nothing
  renameMaybe r (Just t) = Just <$> rename r t

  renameLits : Applicative f => (Fin n -> f (Fin m)) -> List (Lit, Term n) -> f (List (Lit, Term m))
  renameLits r [] = pure []
  renameLits r ((k, t) :: rest) = (\t', rest' => (k, t') :: rest') <$> rename r t <*> renameLits r rest

  renameAlts : Applicative f => (Fin n -> f (Fin m)) -> List (Alt n) -> f (List (Alt m))
  renameAlts r [] = pure []
  renameAlts r (MkAlt c fs body :: rest) =
    (\b, rest' => MkAlt c fs b :: rest') <$> rename (liftN (length fs) r) body <*> renameAlts r rest

export
weaken : Term n -> Term (S n)
weaken t = runIdentity (rename (Id . FS) t)

export
weakenN : (k : Nat) -> Term n -> Term (k + n)
weakenN k t = runIdentity (rename (Id . shift k) t)

------------------------------------------------------------------------------
-- Free variables and closure conversion
------------------------------------------------------------------------------

||| Drops the innermost `k` variables and renumbers the rest.
unbind : Nat -> SortedSet Nat -> SortedSet Nat
unbind k s = fromList [i `minus` k | i <- Prelude.toList s, i >= k]

mutual
  ||| The free variables of a term, as indices.
  export covering
  freeIndices : Term n -> SortedSet Nat
  freeIndices (Var _ i) = singleton (finToNat i)
  freeIndices (Literal _ _) = empty
  freeIndices (Erased _) = empty
  freeIndices (PrimApp _ _ as) = unionsOf as
  freeIndices (Effect _ _ as _) = unionsOf as
  freeIndices (Call _ _ as) = unionsOf as
  freeIndices (ConApp _ _ as) = unionsOf as
  freeIndices (Let _ _ v b) = union (freeIndices v) (unbind 1 (freeIndices b))
  freeIndices (Case _ x alts d) =
    insert (finToNat x) (union (altsFree alts) (maybe empty freeIndices d))
  freeIndices (CaseLit _ x alts d) =
    insert (finToNat x) (union (litsFree alts) (freeIndices d))
  freeIndices (Lam _ _ caps _ _) = fromList (map finToNat (toList caps))
  freeIndices (App _ f a) = union (freeIndices f) (freeIndices a)
  freeIndices (Suspend _ _ caps _) = fromList (map finToNat (toList caps))
  freeIndices (Resume _ e) = freeIndices e
  freeIndices (Unreachable _) = empty
  freeIndices (Crash _ _) = empty

  covering
  unionsOf : List (Term n) -> SortedSet Nat
  unionsOf [] = empty
  unionsOf (t :: ts) = union (freeIndices t) (unionsOf ts)

  covering
  altsFree : List (Alt n) -> SortedSet Nat
  altsFree [] = empty
  altsFree (MkAlt _ fs b :: rest) = union (unbind (length fs) (freeIndices b)) (altsFree rest)

  covering
  litsFree : List (Lit, Term n) -> SortedSet Nat
  litsFree [] = empty
  litsFree ((_, t) :: rest) = union (freeIndices t) (litsFree rest)

||| The parameters a body matches on literals directly (ELIM-G-18): the
||| indices, among `arity` parameters, that a `CaseLit` scrutinizes outside
||| any closure.
export covering
matchedParams : (arity : Nat) -> Term n -> SortedSet Nat
matchedParams arity = go 0
  where
    param : Nat -> Nat -> Maybe Nat
    param d x = if x >= d && minus x d < arity then Just (minus x d) else Nothing
    go : Nat -> Term m -> SortedSet Nat
    goAlts : Nat -> List (Alt m) -> SortedSet Nat
    goAlts d [] = empty
    goAlts d (MkAlt _ fs b :: rest) = union (go (d + length fs) b) (goAlts d rest)
    goLits : Nat -> List (Lit, Term m) -> SortedSet Nat
    goLits d [] = empty
    goLits d ((_, t) :: rest) = union (go d t) (goLits d rest)
    go d (Let _ _ v b) = union (go d v) (go (S d) b)
    go d (Case _ _ alts def) = union (goAlts d alts) (maybe empty (go d) def)
    go d (CaseLit _ x alts def) =
      let here = maybe empty singleton (param d (finToNat x)) in
      union here (union (goLits d alts) (go d def))
    go d _ = empty

||| The position of an element in a vector.
position : Eq a => Vect k a -> a -> Maybe (Fin k)
position [] _ = Nothing
position (y :: ys) x = if x == y then Just FZ else FS <$> position ys x

||| The variables of scope `n` among a set of indices, in increasing order.
captures : {n : Nat} -> SortedSet Nat -> (k ** Vect k (Fin n))
captures s = let fins = mapMaybe (\i => natToFin i n) (Prelude.toList s) in (length fins ** fromList fins)

||| Closure conversion of a lambda body in scope `S n`: captures the body's
||| free variables and closes the body over them. `Nothing` cannot happen for
||| a well-scoped body; it is reported as an internal error.
export covering
lam : {n : Nat} -> Loc -> Label -> Binder -> Term (S n) -> Maybe (Term n)
lam l lbl b body =
  let (k ** caps) = captures {n} (unbind 1 (freeIndices body)) in
  Lam l lbl caps b <$> rename (closeOver caps) body
  where
    closeOver : Vect k (Fin n) -> Fin (S n) -> Maybe (Fin (S k))
    closeOver caps FZ = Just FZ
    closeOver caps (FS i) = FS <$> position caps i

||| Closure conversion of a delayed term.
export covering
delay : {n : Nat} -> Loc -> Label -> Term n -> Maybe (Term n)
delay l lbl body =
  let (k ** caps) = captures {n} (freeIndices body) in
  Suspend l lbl caps <$> rename (position caps) body

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
  tag : Nat
  fields : List Field
  loc : Loc

||| A data instance. It is static when a constructor holds a function or
||| `Lazy` value, directly or through other static data: its values exist only
||| at compile time (ELIM-G-2, ELIM-G-5).
public export
record Data where
  constructor MkData
  id : DataId
  idrisName : String
  cons : List Con
  loc : Loc
  static : Bool

||| A function instance of full Core.
public export
record TFn where
  constructor MkTFn
  id : FnId
  idrisName : String
  arity : Nat
  params : Vect arity Binder
  result : Ty
  body : Term arity
  loc : Loc
  terminating : Bool   -- Idris's checker reports it total (ELIM-G-5)
  block : Bool         -- an Idris case or with block: part of its parent (ELIM-G-11)
  inline : Bool        -- marked %inline in a trusted module (ELIM-G-13)

||| A whole program in full Core.
public export
record Source where
  constructor MkSource
  datas : List Data
  fns : List TFn
  root : FnId
  entry : EntryKind

------------------------------------------------------------------------------
-- Printing (CORE-DUMP-1)
------------------------------------------------------------------------------

indent : Nat -> String
indent d = replicate (2 * d) ' '

var : Fin n -> String
var i = "#" ++ show (finToNat i)

mutual
  ||| Variables print as de Bruijn indices, `#0` being the innermost.
  export covering
  showTerm : Nat -> Term n -> String
  showTerm _ (Var _ i) = var i
  showTerm _ (Literal _ x) = show x
  showTerm _ (Erased _) = "erased"
  showTerm d (PrimApp _ op as) = show op ++ args d as
  showTerm d (Effect _ op as _) = "io." ++ show op ++ args d as
  showTerm d (Call _ f as) = show f ++ args d as
  showTerm d (ConApp _ c as) = show c.dataId ++ "::" ++ show c ++ args d as
  showTerm d (Let _ q v b) =
    "let " ++ show q ++ " = " ++ showTerm (S d) v ++ "\n" ++ indent d ++ showTerm d b
  showTerm d (Case _ x alts def) =
    "case " ++ var x ++ " of" ++ concatMap (alt (S d)) alts ++
    maybe "" (\e => "\n" ++ indent (S d) ++ "_ => " ++ showTerm (S (S d)) e) def
  showTerm d (CaseLit _ x alts def) =
    "case " ++ var x ++ " of" ++
    concatMap (\(k, e) => "\n" ++ indent (S d) ++ show k ++ " => " ++ showTerm (S (S d)) e) alts ++
    "\n" ++ indent (S d) ++ "_ => " ++ showTerm (S (S d)) def
  showTerm d (Lam _ lbl caps b body) =
    "\\" ++ show lbl ++ "[" ++ joinBy ", " (map var (toList caps)) ++ "](" ++ show b.quantity ++
    " " ++ show b.type ++ ") => " ++ showTerm d body
  showTerm d (App _ f a) = "(" ++ showTerm d f ++ " " ++ showTerm d a ++ ")"
  showTerm d (Suspend _ lbl caps body) =
    "delay " ++ show lbl ++ "[" ++ joinBy ", " (map var (toList caps)) ++ "] (" ++ showTerm d body ++ ")"
  showTerm d (Resume _ e) = "force (" ++ showTerm d e ++ ")"
  showTerm _ (Unreachable _) = "unreachable"
  showTerm _ (Crash _ m) = "crash " ++ show m

  covering
  args : Nat -> List (Term n) -> String
  args d as = "(" ++ joinBy ", " (map (showTerm d) as) ++ ")"

  covering
  alt : Nat -> Alt n -> String
  alt d (MkAlt c fs body) =
    "\n" ++ indent d ++ show c ++ "/" ++ show (length fs) ++ " => " ++ showTerm (S d) body

export covering
showSource : Source -> String
showSource p = unlines (map dataDecl p.datas ++ map fnDecl p.fns ++ ["root " ++ show p.root])
  where
    dataDecl : Data -> String
    dataDecl d = "data " ++ show d.id ++ (if d.static then " (static)" else "") ++
                 concatMap (\c => "\n  " ++ show c.id ++ " tag " ++ show c.tag ++ " (" ++
                   joinBy ", " (map (\f => show f.quantity ++ " " ++ show f.type) c.fields) ++ ")") d.cons ++ "\n"
    fnDecl : TFn -> String
    fnDecl f = show f.id ++ " " ++
               concatMap (\b => "(" ++ show b.quantity ++ " " ++ show b.type ++ ") ") (toList f.params) ++
               ": " ++ show f.result ++ " =\n  " ++ showTerm 1 f.body ++ "\n"
