||| First-order Core (docs/architecture/05-middle-ir.md): what `Simplify`
||| produces and `Emit` consumes. It is MLton's SSA shape, in A-normal form:
||| every argument is an atom, every intermediate value is bound once with its
||| value type, and control is a nested `case`.
|||
||| Types are `VTy`, value types only, so a function, a `Lazy` value or static
||| data cannot occur here (PROF-HEAP-1, PROF-HEAP-2); string primitives are
||| not `Prim`s, so they cannot either (PROF-HEAP-3, CORE-INV-10).
|||
||| Every traversal is a fold with an algebra over the base functor `CodeF`.
||| `Op` is itself parameterised by what its branches hold, so `Op Code` is an
||| operation of the IR and `Op a` is that operation with its branches folded.
module IdrisMLIR.Code

import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Types

import Data.List
import Data.Maybe
import Data.SortedMap
import Data.SortedSet
import Data.String

%default total

------------------------------------------------------------------------------
-- The IR
------------------------------------------------------------------------------

||| A runtime operand: a variable, a literal or the erased value.
public export
data Atom = AVar VarId | ALit Lit | AErased

export
Eq Atom where
  AVar a == AVar b = a == b
  ALit a == ALit b = a == b
  AErased == AErased = True
  _ == _ = False

export
Show Atom where
  show (AVar x) = show x
  show (ALit l) = show l
  show AErased = "erased"

||| A constructor alternative: the constructor, the variables bound to its
||| fields, and what the branch holds.
public export
record Branch r where
  constructor MkBranch
  con : ConId
  fields : List VarId
  body : r

||| An operation whose result is bound by `Bind`. `r` is what the branches of
||| a match hold.
public export
data Op r
  = OPrim Prim (List Atom)
  | OCall FnId (List Atom)
  | OCon ConId (List Atom)
  -- field i of a value of a single-constructor data type (IDR-FIELD-1)
  | OField Atom ConId Nat
  -- an IO primitive: its operands end with the world, and its result is a
  -- value of the IORes instance named here
  | OIO IOOp (List Atom) DataId
  | OCase Atom (List (Branch r)) (Maybe r)
  | OCaseLit Atom (List (Lit, r)) r

||| A function body: a sequence of bindings ending in a result, or in a point
||| that cannot be reached (an alternative Idris proved impossible).
public export
data Code = Bind Loc VarId Quantity VTy (Op Code) Code
          | Ret Loc Atom
          | Absurd Loc

||| The base functor of `Code`: one layer, with the recursive positions `r`.
public export
data CodeF r = BindF Loc VarId Quantity VTy (Op r) r
             | RetF Loc Atom
             | AbsurdF Loc

export
Functor Branch where
  map f b = { body $= f } b

export
Functor Op where
  map f (OPrim p as) = OPrim p as
  map f (OCall g as) = OCall g as
  map f (OCon c as) = OCon c as
  map f (OField a c i) = OField a c i
  map f (OIO op as r) = OIO op as r
  map f (OCase x bs d) = OCase x (map (map f) bs) (map f d)
  map f (OCaseLit x as d) = OCaseLit x (map (map f) as) (f d)

export
Foldable Op where
  foldr f z (OCase _ bs d) = foldr (\b, acc => f b.body acc) (maybe z (\e => f e z) d) bs
  foldr f z (OCaseLit _ as d) = foldr (\(_, e), acc => f e acc) (f d z) as
  foldr f z _ = z

export
Traversable Op where
  traverse f (OPrim p as) = pure (OPrim p as)
  traverse f (OCall g as) = pure (OCall g as)
  traverse f (OCon c as) = pure (OCon c as)
  traverse f (OField a c i) = pure (OField a c i)
  traverse f (OIO op as r) = pure (OIO op as r)
  traverse f (OCase x bs d) =
    OCase x <$> traverse (\b => (\e => { body := e } b) <$> f b.body) bs <*> traverse f d
  traverse f (OCaseLit x as d) =
    OCaseLit x <$> traverse (\(k, e) => (k,) <$> f e) as <*> f d

export
Functor CodeF where
  map f (BindF l x q t op k) = BindF l x q t (map f op) (f k)
  map f (RetF l a) = RetF l a
  map f (AbsurdF l) = AbsurdF l

mutual
  ||| The catamorphism: folds a `Code` bottom-up with an algebra.
  export
  cata : (CodeF a -> a) -> Code -> a
  cata alg (Bind l x q t op k) = alg (BindF l x q t (cataOp alg op) (cata alg k))
  cata alg (Ret l a) = alg (RetF l a)
  cata alg (Absurd l) = alg (AbsurdF l)

  cataOp : (CodeF a -> a) -> Op Code -> Op a
  cataOp alg (OPrim p as) = OPrim p as
  cataOp alg (OCall g as) = OCall g as
  cataOp alg (OCon c as) = OCon c as
  cataOp alg (OField a c i) = OField a c i
  cataOp alg (OIO op as r) = OIO op as r
  cataOp alg (OCase x bs d) = OCase x (cataBranches alg bs) (cataMaybe alg d)
  cataOp alg (OCaseLit x as d) = OCaseLit x (cataLits alg as) (cata alg d)

  cataBranches : (CodeF a -> a) -> List (Branch Code) -> List (Branch a)
  cataBranches alg [] = []
  cataBranches alg (MkBranch c xs e :: bs) = MkBranch c xs (cata alg e) :: cataBranches alg bs

  cataMaybe : (CodeF a -> a) -> Maybe Code -> Maybe a
  cataMaybe alg Nothing = Nothing
  cataMaybe alg (Just e) = Just (cata alg e)

  cataLits : (CodeF a -> a) -> List (Lit, Code) -> List (Lit, a)
  cataLits alg [] = []
  cataLits alg ((k, e) :: as) = (k, cata alg e) :: cataLits alg as

------------------------------------------------------------------------------
-- Operations, one layer
------------------------------------------------------------------------------

||| The atoms an operation reads directly (not in its branches).
export
operands : Op r -> List Atom
operands (OPrim _ as) = as
operands (OCall _ as) = as
operands (OCon _ as) = as
operands (OField a _ _) = [a]
operands (OIO _ as _) = as
operands (OCase x _ _) = [x]
operands (OCaseLit x _ _) = [x]

||| The variables an operation binds in its branches.
export
fieldBinders : Op r -> List VarId
fieldBinders (OCase _ bs _) = concatMap (.fields) bs
fieldBinders _ = []

varsOf : List Atom -> List VarId
varsOf = mapMaybe var
  where
    var : Atom -> Maybe VarId
    var (AVar x) = Just x
    var _ = Nothing

------------------------------------------------------------------------------
-- Algebras
------------------------------------------------------------------------------

||| Every variable bound in a body, in order (CORE-INV-1: unique).
export
binders : Code -> List VarId
binders = cata alg
  where
    alg : CodeF (List VarId) -> List VarId
    alg (BindF _ x _ _ op k) = x :: fieldBinders op ++ concat op ++ k
    alg _ = []

||| The functions a body calls.
export
calls : Code -> List FnId
calls = cata alg
  where
    alg : CodeF (List FnId) -> List FnId
    alg (BindF _ _ _ _ op k) = (case op of OCall f _ => [f]; _ => []) ++ concat op ++ k
    alg _ = []

||| The data instances a body mentions.
export
datasOf : Code -> List DataId
datasOf = cata alg
  where
    ty : VTy -> List DataId
    ty (DataT d) = [d]
    ty _ = []
    here : Op r -> List DataId
    here (OCon c _) = [c.dataId]
    here (OField _ c _) = [c.dataId]
    here (OIO _ _ r) = [r]
    here (OCase _ bs _) = map (\b => b.con.dataId) bs
    here _ = []
    alg : CodeF (List DataId) -> List DataId
    alg (BindF _ _ _ t op k) = ty t ++ here op ++ concat op ++ k
    alg _ = []

sums : List (SortedMap VarId Nat) -> SortedMap VarId Nat
sums = foldl (mergeWith (+)) empty

maxes : List (SortedMap VarId Nat) -> SortedMap VarId Nat
maxes = foldl (mergeWith max) empty

||| How often each variable is used on the path that uses it most: uses add
||| up along a path and take the maximum over alternatives (CORE-INV-9).
export
uses : Code -> SortedMap VarId Nat
uses = cata alg
  where
    count : List Atom -> SortedMap VarId Nat
    count as = sums [singleton x 1 | x <- varsOf as]
    alg : CodeF (SortedMap VarId Nat) -> SortedMap VarId Nat
    alg (BindF _ _ _ _ op k) = sums [count (operands op), maxes (toList op), k]
    alg (RetF _ a) = count [a]
    alg (AbsurdF _) = empty

||| Whether an operation can crash or has an effect, given which callees are
||| safe: division by an unknown or zero divisor, IO, or an unsafe call. Its
||| branches are judged separately.
export
safeOp : (FnId -> Bool) -> Op r -> Bool
safeOp s (OPrim (IntOp Div _) [_, ALit (LInt _ n)]) = n /= 0
safeOp s (OPrim (IntOp Mod _) [_, ALit (LInt _ n)]) = n /= 0
safeOp s (OPrim (IntOp Div _) _) = False
safeOp s (OPrim (IntOp Mod _) _) = False
safeOp s (OIO {}) = False
safeOp s (OCall f _) = s f
safeOp s _ = True

||| Code that cannot crash and has no effect (ELIM-G-5, PROF-HEAP-5).
export
safeCode : (FnId -> Bool) -> Code -> Bool
safeCode s = cata alg
  where
    alg : CodeF Bool -> Bool
    alg (BindF _ _ _ _ op k) = safeOp s op && and (map delay (toList op)) && k
    alg _ = True

||| Does a body need contract version 1 (IDR-MOD-1): characters, strings,
||| the world or IO?
export
needsV1 : Code -> Bool
needsV1 = cata alg
  where
    lit : Atom -> Bool
    lit (ALit (LChar _)) = True
    lit (ALit (LStr _)) = True
    lit _ = False
    here : Op r -> Bool
    here (OIO {}) = True
    here (OPrim (Cast _ SChar) _) = True
    here (OPrim (Cast SChar _) _) = True
    here (OPrim (Compare _ SChar) _) = True
    here (OCaseLit _ as _) = any (\(k, _) => case k of LChar _ => True; _ => False) as
    here op = any lit (operands op)
    alg : CodeF Bool -> Bool
    alg (BindF _ _ _ t op k) = t == CharT || t == StrT || t == WorldT || here op || or (map delay (toList op)) || k
    alg (RetF _ a) = lit a
    alg (AbsurdF _) = False

------------------------------------------------------------------------------
-- Programs
------------------------------------------------------------------------------

||| A field of a runtime constructor.
public export
record CField where
  constructor MkCField
  quantity : Quantity
  type : VTy

public export
record CCon where
  constructor MkCCon
  id : ConId
  tag : Nat
  fields : List CField
  loc : Loc

||| A runtime data instance.
public export
record CData where
  constructor MkCData
  id : DataId
  idrisName : String
  cons : List CCon
  loc : Loc

public export
record Param where
  constructor MkParam
  var : VarId
  quantity : Quantity
  type : VTy

||| A function of first-order Core: an instance, or a specialization of one.
public export
record CFn where
  constructor MkCFn
  id : FnId
  idrisName : String
  params : List Param
  result : VTy
  body : Code
  loc : Loc
  terminating : Bool
  ||| For a specialization, the instance and the static arguments it was
  ||| made for, printed in dumps (ELIM-G-3).
  specializes : Maybe String

||| A whole program in first-order Core.
public export
record Target where
  constructor MkTarget
  datas : List CData
  fns : List CFn
  root : FnId
  entry : EntryKind

||| Lookup tables of a program.
public export
record Index where
  constructor MkIndex
  fns : SortedMap FnId CFn
  datas : SortedMap DataId CData
  cons : SortedMap ConId CCon

export
index : Target -> Index
index t = MkIndex (fromList [(f.id, f) | f <- t.fns])
                  (fromList [(d.id, d) | d <- t.datas])
                  (fromList [(c.id, c) | d <- t.datas, c <- d.cons])

||| The contract version a program needs (IDR-MOD-1).
export
version : Target -> Nat
version t =
  if isIO t.entry || any fnV1 t.fns || any dataV1 t.datas
     then 1 else 0
  where
    isIO : EntryKind -> Bool
    isIO IOEntry = True
    isIO IntEntry = False
    v1 : VTy -> Bool
    v1 t = t == CharT || t == StrT || t == WorldT
    dataV1 : CData -> Bool
    dataV1 d = any (\c => any (\f => v1 f.type) c.fields) d.cons
    fnV1 : CFn -> Bool
    fnV1 f = v1 f.result || any (v1 . (.type)) f.params || needsV1 f.body

------------------------------------------------------------------------------
-- Printing (CORE-DUMP-1)
------------------------------------------------------------------------------

indent : Nat -> String
indent d = replicate (2 * d) ' '

args : List Atom -> String
args as = "(" ++ joinBy ", " (map show as) ++ ")"

||| One operation, given its printed branches.
showOp : Nat -> Op (Nat -> String) -> String
showOp d (OPrim p as) = show p ++ args as
showOp d (OCall f as) = show f ++ args as
showOp d (OCon c as) = show c.dataId ++ "::" ++ show c ++ args as
showOp d (OField a c i) = show a ++ "." ++ show c ++ "#" ++ show i
showOp d (OIO op as _) = "io." ++ show op ++ args as
showOp d (OCase x bs def) =
  "case " ++ show x ++ " of" ++
  concatMap (\b => "\n" ++ indent (S d) ++ show b.con ++ "(" ++ joinBy ", " (map show b.fields) ++
                   ") => " ++ b.body (S (S d))) bs ++
  maybe "" (\e => "\n" ++ indent (S d) ++ "_ => " ++ e (S (S d))) def
showOp d (OCaseLit x as def) =
  "case " ++ show x ++ " of" ++
  concatMap (\(k, e) => "\n" ++ indent (S d) ++ show k ++ " => " ++ e (S (S d))) as ++
  "\n" ++ indent (S d) ++ "_ => " ++ def (S (S d))

||| A body, printed at an indentation depth: an algebra into `Nat -> String`.
export
showCode : Code -> Nat -> String
showCode = cata alg
  where
    alg : CodeF (Nat -> String) -> Nat -> String
    alg (BindF _ x q t op k) d =
      "let " ++ show x ++ " : " ++ show q ++ " " ++ show t ++ " = " ++ showOp (S d) op ++
      "\n" ++ indent d ++ k d
    alg (RetF _ a) d = show a
    alg (AbsurdF _) d = "unreachable"

export
showTarget : Target -> String
showTarget t = unlines (map dataDecl t.datas ++ map fnDecl t.fns ++ ["root " ++ show t.root])
  where
    dataDecl : CData -> String
    dataDecl d = unlines (("data " ++ show d.id) ::
                   map (\c => "  " ++ show c.id ++ " tag " ++ show c.tag ++ " (" ++
                              joinBy ", " (map (\f => show f.quantity ++ " " ++ show f.type) c.fields) ++ ")")
                       d.cons)
    fnDecl : CFn -> String
    fnDecl f = maybe "" (\s => "-- " ++ s ++ "\n") f.specializes ++
               show f.id ++ " " ++
               unwords (map (\p => "(" ++ show p.var ++ " : " ++ show p.quantity ++ " " ++ show p.type ++ ")") f.params) ++
               " : " ++ show f.result ++ " =\n  " ++ showCode f.body 1 ++ "\n"
