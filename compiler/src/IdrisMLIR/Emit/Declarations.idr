-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The program's declarations: its functions, each named by its symbol (its
||| key printed, once), each followed by the functions its
||| lambdas and delays became. A family is no declaration: a data type
||| holds its group's attribute, which declares it (Emit.Index).
module IdrisMLIR.Emit.Declarations

import IdrisMLIR.Emit.Bodies
import IdrisMLIR.Emit.Closures
import IdrisMLIR.Emit.Index
import IdrisMLIR.Emit.Monad
import IdrisMLIR.Emit.Tensors
import IdrisMLIR.Emit.Types
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.MLIR
import IdrisMLIR.Spec.Grades.Grade
import IdrisMLIR.Term
import IdrisMLIR.Types

import Control.Monad.State
import Data.List
import Data.Maybe
import Data.SnocList
import Data.Vect

%default total

||| A parameter as the function binds it: at its binder's quantity, which
||| is Idris's and is never demoted; the world binds no value.
parameter : Index -> Loc -> String -> (Nat, (Shown, Binder)) -> E (InScope, Maybe Argument)
parameter ix l sym (i, (name, MkBinder _ WorldT)) = pure (World, Nothing)
parameter ix l sym (i, (name, b)) = do
  (v, o) <- freshVal ix b.type b.quantity
  pure (Whole v, Just (MkArgument o (Binder name l sym i)))

||| A function, located by its Idris name, each parameter by the name Idris
||| gave it, its erased index parameters its telescope, then the functions
||| its lambdas and delays became, in the order their bodies were finished,
||| each with its symbol. Which one is the root is the program's to say,
||| not the function's. What Idris proved of its loops is its own
||| property. It is written from the state `initial` makes for it.
export
function : Index -> TFn -> E (List (String, Statement))
function ix f = do
  ((args, res), ops) <- inFunction $ do
    bound <- traverse (\(i, p) => parameter ix f.loc f.symbol (finToNat i, p)) (zip (range {len = f.arity}) f.params)
    let sc = MkScope (\i => fst (index i bound)) f.telescope
    res <- plain ix f.loc (para (alg ix) f.body sc (expecting (Just f.result)))
    res' <- traverse (fit ix f.loc (Just f.result)) res
    pure (mapMaybe snd (toList bound), res')
  body <- epilogue ix f.loc res ops
  let type = FunctionType (MkSignature (map (\a => a.value.type) args) (resultTypes ix f.result))
      fn = functionOp f.symbol (map (sortOf ix) f.telescope) type (MkRegion args body) f.termination
  lifted <- gets (.lifted)
  pure ((f.symbol, MkStatement Nothing fn (Named (shown f.key.origin) f.loc)) :: (lifted <>> []))
