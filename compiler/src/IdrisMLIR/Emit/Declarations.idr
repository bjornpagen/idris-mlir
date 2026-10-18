-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The program's declarations: its functions, each named by its symbol and
||| stating its key as `#idr.instance`, each followed by the functions its
||| lambdas and delays became. A data instance is no declaration: its body
||| is in the module's table of data types (Emit.Index).
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
instanceAttr key = idr (InstanceAttr key.origin (argumentsText key.arguments))

||| A function, located by its Idris name, each parameter by the name Idris
||| gave it, then the functions its lambdas and delays became, in the order
||| their bodies were finished, each with its symbol. Which one is the root
||| is the program's to say, not the function's. What Idris proved of it is
||| its own property: `total` when every loop of its body is one Idris
||| proved terminating. It is written from the state `initial` makes for it.
export
function : Index -> TFn -> E (List (String, Statement))
function ix f = do
  let sym = f.id.name
  ((args, res), ops) <- inFunction $ do
    bound <- traverse (\(_, b) => freshVal (typeOf b) b.quantity) f.params
    held <- traverse (\(i, (v, _)) => holdFor ix f.loc (mostUses i f.body) v) (zip range bound)
    res <- plain' (para alg' f.body (\i => Whole (index i held)) (expecting (Just f.result)))
    res' <- traverse (fit ix f.loc (Just f.result)) res
    let args = map (\((name, _), (_, o)) => MkArgument o (Named name f.loc)) (toList (zip f.params bound))
    pure (args, res')
  let rt = mlirType f.result
  body <- epilogue ix f.loc res ops
  -- One cell for a lazy constant. Inlining the function that builds it
  -- would build a fresh cell at every use, and each force would run the
  -- body again.
  let shared = f.arity == 0 && lazyResult f.result
  let fn = Idr.funcOp {total' = f.facts.terminating,
                       noInline = shared,
                       instance = Just (instanceAttr f.key)}
                      sym
                      (FunctionType (MkSignature (map (\a : Argument => a.value.type) args) [rt]))
                      (MkRegion args body)
  lifted <- gets (.lifted)
  pure ((sym, MkStatement Nothing fn (Named (shown f.key.origin) f.loc)) :: (lifted <>> []))
  where
    lazyResult : Ty -> Bool
    lazyResult (LazyT _) = True
    lazyResult _ = False
    alg' : {0 nv : Nat} -> TermF (Sub Em) nv -> Em nv
    alg' = alg ix
    plain' : E (Maybe Val) -> E (Maybe Val)
    plain' = plain ix f.loc
