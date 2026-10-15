-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The module's declarations: the functions of the program, each named by
||| its symbol and stating its key as `#idr.instance`, each followed by the
||| functions its lambdas and delays became. A data instance is no
||| declaration: its type carries its constructors (Emit.Types).
module IdrisMLIR.Emit.Declarations

import IdrisMLIR.Dialect.Idr as Idr
import IdrisMLIR.Emit.Bodies
import IdrisMLIR.Emit.Index
import IdrisMLIR.Emit.Monad
import IdrisMLIR.Emit.Tensors
import IdrisMLIR.Emit.Types
import IdrisMLIR.Facts
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.MLIR
import IdrisMLIR.Term
import IdrisMLIR.Types

import Control.Monad.State
import Data.List
import Data.SnocList
import Data.Vect

%default total

||| What a function is an instance of, as text.
instanceAttr : InstanceKey -> MlirAttr
instanceAttr key = Idr (InstanceAttr key.origin (map StringAttr key.arguments))

||| A function, located by its Idris name, each parameter by the name Idris
||| gave it, then the functions its lambdas and delays became, in the order
||| their bodies were finished. Only the root is public. What Idris proved
||| of it is its own property: `total` when every loop of its body is one
||| Idris proved terminating. It is written from the state `initial` makes
||| for it.
export covering
function : Index -> FnId -> TFn -> E (List Statement)
function ix root f = do
  sym <- fnSymbol ix f.id
  -- A parameter that is an array of records is an argument per column.
  ((args, res), ops) <- inFunction $ do
    bound <- traverse (\(_, b) => freshVal ix (typeOf b) b.quantity) f.params
    res <- plain' (para alg' f.body (\i => fst (index i bound)) (Just f.result))
    res' <- traverse (fit ix f.loc (Just f.result)) res
    let args = concatMap (\((name, _), (_, vs)) => map (\o => MkArgument o (Named name f.loc)) vs)
                         (toList (zip f.params bound))
    pure (args, res')
  rts <- heldTypes ix Many f.result
  body <- epilogue ix f.loc res ops
  -- One cell for a lazy constant. Inlining the function that builds it
  -- would build a fresh cell at every use, and each force would run the
  -- body again.
  let shared = f.arity == 0 && lazyResult f.result
  let fn = Idr.funcOp {symVisibility = if f.id == root then Nothing else Just "private",
                       total' = f.facts.terminating,
                       noInline = shared,
                       instance = Just (instanceAttr f.key)}
                      sym
                      (FunctionType (MkSignature (map (\a : Argument => a.value.type) args) rts))
                      (MkRegion args body)
  lifted <- gets (.lifted)
  pure (MkStatement Nothing fn (Named (shown f.key.origin) f.loc) :: (lifted <>> []))
  where
    lazyResult : Ty -> Bool
    lazyResult (LazyT _) = True
    lazyResult _ = False
    covering
    alg' : {0 nv : Nat} -> TermF (Sub Em) nv -> Em nv
    alg' = alg ix
    plain' : E (Maybe Val) -> E (Maybe Val)
    plain' = plain ix f.loc
