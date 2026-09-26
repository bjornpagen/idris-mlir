||| After `Simplify`: the program is first order and heap free (PROF-HEAP-*,
||| CORE-INV-2, CORE-INV-3, CORE-INV-10). `Simplify` reports most violations
||| itself, with the reason; this is the final guard.
module IdrisMLIR.HeapCheck

import IdrisMLIR.Core

import Data.List

%default covering

checkTy : Loc -> Ty -> Either Diag ()
checkTy l (FunT {}) = Left (diag "PROF-HEAP-1" "HeapCheck" l "a function value survives at runtime")
checkTy l (LazyT _) = Left (diag "PROF-HEAP-2" "HeapCheck" l "a Lazy value survives at runtime")
checkTy _ _ = Right ()

mutual
  checkExpr : Expr -> Either Diag ()
  checkExpr (ELam l _ _ _ _) = Left (diag "PROF-HEAP-1" "HeapCheck" l "a lambda survives at runtime")
  checkExpr (EApp l _ _) = Left (diag "PROF-HEAP-1" "HeapCheck" l "an unknown function is applied at runtime")
  checkExpr (EPartial l _ _) = Left (diag "PROF-HEAP-1" "HeapCheck" l "a partial application survives")
  checkExpr (EDelay l _) = Left (diag "PROF-HEAP-2" "HeapCheck" l "a Delay survives at runtime")
  checkExpr (EForce l _) = Left (diag "PROF-HEAP-2" "HeapCheck" l "a Force survives at runtime")
  checkExpr (EWorld l) = Left (diag "PROF-IO-3" "HeapCheck" l "%MkWorld survives")
  checkExpr (EPrim l op args) = do
    when (buildsString op) $
      Left (diag "PROF-HEAP-3" "HeapCheck" l "a string is built at runtime")
    when (isStringOp op) $
      Left (diag "PROF-PRIM-4" "HeapCheck" l ("the string operation " ++ show op ++ " at runtime"))
    traverse_ checkExpr args
  checkExpr (EIO _ _ args _) = traverse_ checkExpr args
  checkExpr (ECall _ _ args) = traverse_ checkExpr args
  checkExpr (ECon _ _ _ args) = traverse_ checkExpr args
  checkExpr (ELet l _ _ t v b) = checkTy l t >> checkExpr v >> checkExpr b
  checkExpr (EMatchCon _ _ alts d) = traverse_ (\(MkConAlt _ _ e) => checkExpr e) alts >> traverse_ checkExpr d
  checkExpr (EMatchLit _ _ alts d) = traverse_ (checkExpr . snd) alts >> checkExpr d
  checkExpr _ = Right ()

||| The contract version a first-order program needs (IDR-MOD-1).
export
requiredVersion : Program -> Nat
requiredVersion prog =
  if any usesV1 prog.fns || any (\d => any (\c => any (v1Ty . (.type)) c.fields) d.cons) prog.datas
     || isIO prog.entry
     then 1 else 0
  where
    isIO : EntryKind -> Bool
    isIO IOEntry = True
    isIO IntEntry = False
    v1Ty : Ty -> Bool
    v1Ty CharT = True
    v1Ty StrT = True
    v1Ty WorldT = True
    v1Ty _ = False
    v1Expr : Expr -> Bool
    v1Expr (ELit _ (LChar _)) = True
    v1Expr (ELit _ (LStr _)) = True
    v1Expr (EIO {}) = True
    v1Expr (EPrim _ (Cast _ CharT) _) = True
    v1Expr (EPrim _ _ as) = any v1Expr as
    v1Expr (ECall _ _ as) = any v1Expr as
    v1Expr (ECon _ _ _ as) = any v1Expr as
    v1Expr (ELet _ _ _ t v b) = v1Ty t || v1Expr v || v1Expr b
    v1Expr (EMatchCon _ _ alts d) = any (\(MkConAlt _ _ e) => v1Expr e) alts || maybe False v1Expr d
    v1Expr (EMatchLit _ _ alts d) = any (v1Expr . snd) alts || v1Expr d
    v1Expr _ = False
    usesV1 : Fn -> Bool
    usesV1 f = v1Ty f.result || any (v1Ty . (.type)) f.params || v1Expr f.body

export
heapCheck : Program -> Either Diag Program
heapCheck prog = do
  for_ prog.fns $ \f => do
    checkTy f.loc f.result
    traverse_ (checkTy f.loc . (.type)) f.params
    checkExpr f.body
  for_ prog.datas $ \d => for_ d.cons $ \c => traverse_ (checkTy c.loc . (.type)) c.fields
  pure ({ version := requiredVersion prog } prog)
