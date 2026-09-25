||| Checked TT to our IR. Reads each definition's compile-time case tree
||| (`treeCT`), which Idris has not erased, and keeps binder quantities.
module IdrisMLIR.Frontend.Translate

import Core.Case.CaseTree
import Core.Context
import Libraries.Data.NameMap

import IdrisMLIR.IR

import Data.List

%default covering

data Fresh : Type where

fresh : {auto f : Ref Fresh Nat} -> Core Nat
fresh = do
  n <- get Fresh
  put Fresh (S n)
  pure n

||| The definition being translated. Errors carry its location: in `--check`
||| mode Idris only exits non-zero for errors that have a source line.
record Owner where
  constructor MkOwner
  name : Name
  fc : FC

unsupported : Owner -> String -> Core a
unsupported owner what =
  throw (GenericMsg owner.fc ("mlir backend: " ++ show owner.name ++ ": unsupported " ++ what))

intTy : PrimType -> Maybe IntTy
intTy IntType = Just IdrisInt
intTy Int8Type = Just SInt8
intTy Int16Type = Just SInt16
intTy Int32Type = Just SInt32
intTy Int64Type = Just SInt64
intTy Bits8Type = Just UInt8
intTy Bits16Type = Just UInt16
intTy Bits32Type = Just UInt32
intTy Bits64Type = Just UInt64
intTy _ = Nothing

typeTerm : Term vars -> Maybe IntTy
typeTerm (PrimVal _ (PrT t)) = intTy t
typeTerm _ = Nothing

constant : Constant -> Maybe (IntTy, Integer)
constant (I x) = Just (IdrisInt, cast x)
constant (I8 x) = Just (SInt8, cast x)
constant (I16 x) = Just (SInt16, cast x)
constant (I32 x) = Just (SInt32, cast x)
constant (I64 x) = Just (SInt64, cast x)
constant (B8 x) = Just (UInt8, cast x)
constant (B16 x) = Just (UInt16, cast x)
constant (B32 x) = Just (UInt32, cast x)
constant (B64 x) = Just (UInt64, cast x)
constant _ = Nothing

quantity : RigCount -> Quantity
quantity rig = if isErased rig then Q0 else if isLinear rig then Q1 else QW

||| Leading pi binders (quantity, type) and the remaining result type.
signature : Term vars -> (List (Quantity, Maybe IntTy), Maybe IntTy, Bool)
signature (Bind _ _ (Pi _ rig _ ty) scope) =
  let (params, result, typeLevel) = signature scope
  in ((quantity rig, typeTerm ty) :: params, result, typeLevel)
signature (TType _ _) = ([], Nothing, True)
signature ty = ([], typeTerm ty, False)

spine : Term vars -> List (Term vars) -> (Term vars, List (Term vars))
spine (App _ fn arg) args = spine fn (arg :: args)
spine fn args = (fn, args)

describe : Term vars -> String
describe (Local {}) = "local"
describe (Ref _ _ n) = "reference " ++ show n
describe (Meta _ n _ _) = "metavariable " ++ show n
describe (Bind _ _ (Lam {}) _) = "lambda"
describe (Bind {}) = "binder"
describe (App {}) = "application"
describe (As {}) = "as-pattern"
describe (TDelayed {}) = "lazy type"
describe (TDelay {}) = "delay"
describe (TForce {}) = "force"
describe (PrimVal _ c) = "constant " ++ show c
describe (Erased {}) = "erased term"
describe (TType {}) = "type"

binary : Owner -> PrimOp -> PrimType -> List Expr -> Core Expr
binary owner op t [a, b] = case intTy t of
  Just it => pure (Prim op it a b)
  Nothing => unsupported owner (show op ++ " on " ++ show t)
binary owner op _ _ = unsupported owner ("partial application of " ++ show op)

primitive : Owner -> PrimFn arity -> List Expr -> Core Expr
primitive owner (Add t) args = binary owner Add t args
primitive owner (Sub t) args = binary owner Sub t args
primitive owner (Mul t) args = binary owner Mul t args
primitive owner (LT t) args = binary owner Lt t args
primitive owner (LTE t) args = binary owner Lte t args
primitive owner (EQ t) args = binary owner Eq t args
primitive owner (GTE t) args = binary owner Gte t args
primitive owner (GT t) args = binary owner Gt t args
primitive owner (Cast from to) [arg] = case (intTy from, intTy to) of
  (Just f, Just t) => pure (Cast f t arg)
  _ => unsupported owner ("cast from " ++ show from ++ " to " ++ show to)
primitive owner op _ = unsupported owner ("primitive " ++ show op)

mutual
  term : {auto c : Ref Ctxt Defs} -> {auto f : Ref Fresh Nat} ->
         Owner -> List Nat -> Term vars -> Core Expr
  term owner env (Local _ _ idx _) = case getAt idx env of
    Just v => pure (Var v)
    Nothing => unsupported owner "variable index"
  term owner _ (PrimVal _ c) = case constant c of
    Just (t, n) => pure (Lit t n)
    Nothing => case c of
      PrT _ => pure CompileTime
      _ => unsupported owner ("constant " ++ show c)
  term _ _ (TType {}) = pure CompileTime
  term _ _ (Erased {}) = pure CompileTime
  term _ _ (Bind _ _ (Pi {}) _) = pure CompileTime
  term owner env (Bind _ _ (Let _ rig val ty) scope) = do
    v <- fresh
    value <- term owner env val
    let t = if isErased rig then Irrelevant else maybe Irrelevant IntT (typeTerm ty)
    body <- term owner (v :: env) scope
    pure (Let v t value body)
  term owner env tm@(App {}) = let (fn, args) = spine tm [] in application owner env fn args
  term owner env tm@(Ref {}) = application owner env tm []
  term owner _ tm = unsupported owner (describe tm)

  application : {auto c : Ref Ctxt Defs} -> {auto f : Ref Fresh Nat} ->
                Owner -> List Nat -> Term vars -> List (Term vars) -> Core Expr
  application owner env (Ref _ _ n) args = do
    defs <- get Ctxt
    Just def <- lookupCtxtExact n (gamma defs)
      | Nothing => unsupported owner ("reference to missing definition " ++ show n)
    args' <- traverse (term owner env) args
    case definition def of
      Builtin op => primitive owner op args'
      PMDef {} => pure (Call (show (fullname def)) args')
      TCon {} => pure CompileTime
      _ => unsupported owner ("reference to " ++ show (fullname def))
  application owner _ fn _ = unsupported owner ("application of " ++ describe fn)

mutual
  tree : {auto c : Ref Ctxt Defs} -> {auto f : Ref Fresh Nat} ->
         Owner -> List Nat -> CaseTree vars -> Core Expr
  tree owner env (STerm _ tm) = term owner env tm
  tree owner env (Case idx _ scTy alts) = do
    let Just v = getAt idx env
      | Nothing => unsupported owner "case variable"
    let Just t = typeTerm scTy
      | Nothing => unsupported owner "case on a non-integer type"
    (consts, Just def) <- alternatives owner env alts
      | _ => unsupported owner "case without a default branch"
    pure (Switch t (Var v) consts def)
  tree owner _ (Unmatched msg) = unsupported owner ("partial match (" ++ msg ++ ")")
  tree owner _ Impossible = unsupported owner "impossible case"

  alternatives : {auto c : Ref Ctxt Defs} -> {auto f : Ref Fresh Nat} ->
                 Owner -> List Nat -> List (CaseAlt vars) ->
                 Core (List (Integer, Expr), Maybe Expr)
  alternatives _ _ [] = pure ([], Nothing)
  alternatives owner env (ConstCase c rhs :: rest) = do
    let Just (_, n) = constant c
      | Nothing => unsupported owner ("match on constant " ++ show c)
    rhs' <- tree owner env rhs
    (consts, def) <- alternatives owner env rest
    pure ((n, rhs') :: consts, def)
  alternatives owner env (DefaultCase rhs :: _) = pure ([], Just !(tree owner env rhs))
  alternatives owner _ (ConCase n _ _ _ :: _) = unsupported owner ("match on constructor " ++ show n)
  alternatives owner _ (DelayCase {} :: _) = unsupported owner "lazy match"

isMain : Name -> Bool
isMain (NS _ (UN (Basic "main"))) = True
isMain _ = False

||| Nothing for definitions with no runtime code: types, constructors, and
||| functions computing types.
function : {auto c : Ref Ctxt Defs} -> GlobalDef -> Core (Maybe Fn)
function def = case definition def of
  PMDef _ args treeCT _ _ => do
    let owner = MkOwner (fullname def) (location def)
    let (params, result, typeLevel) = signature (type def)
    if typeLevel then pure Nothing else do
      let Just result = result
        | Nothing => unsupported owner "result type"
      let True = length params == length args
        | False => unsupported owner "definition with fewer patterns than arguments"
      f <- newRef Fresh 0
      -- `args`, the case tree's scope, lists parameters in declaration order.
      params' <- traverse (param owner) params
      body <- tree owner (map (.var) params') treeCT
      pure (Just (MkFn (show owner.name) params' result body))
  TCon {} => pure Nothing
  DCon {} => pure Nothing
  _ => unsupported (MkOwner (fullname def) (location def)) "kind of definition"
  where
    param : {auto f : Ref Fresh Nat} -> Owner -> (Quantity, Maybe IntTy) -> Core Param
    param _ (Q0, t) = pure (MkParam !fresh Q0 (maybe Irrelevant IntT t))
    param _ (q, Just t) = pure (MkParam !fresh q (IntT t))
    param owner (_, Nothing) = unsupported owner "runtime parameter type"

||| All runtime definitions of the module being compiled.
export
translateModule : {auto c : Ref Ctxt Defs} -> (moduleFC : FC) -> Core Program
translateModule moduleFC = do
  defs <- get Ctxt
  found <- traverse definitionOf (keys (toIR defs))
  fns <- catMaybes <$> traverse (\def => map (def,) <$> function def) found
  let entry = head' [fn.name | (def, fn) <- fns, isMain (fullname def)]
  pure (MkProgram (sortBy (\a, b => compare a.name b.name) (map snd fns)) entry)
  where
    definitionOf : Name -> Core GlobalDef
    definitionOf n = do
      defs <- get Ctxt
      Just def <- lookupCtxtExact n (gamma defs)
        | Nothing => throw (GenericMsg moduleFC ("mlir backend: missing definition " ++ show n))
      pure def
