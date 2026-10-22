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
import IdrisMLIR.Spec.Functions.Extents
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
  pure (Whole v, Just (MkArgument o (Binder name (Spanned l) sym i)))

||| The entries of a function's extents (`#idr.extent`), in order of side,
||| position and axis: the axes each argument's type names, at its
||| position among the arguments, then the result's, the one result a
||| function has, each with its term's nodes.
extentEntries : Index -> List (List (Nat, ITerm)) -> List (Nat, ITerm) -> List MlirAttr
extentEntries ix args result = inputs 0 args ++ at (ExtentAttr OnResult 0) result
  where
    at : (Nat -> List (TermNode MlirType MlirAttr) -> IdrAttr MlirType MlirAttr) -> List (Nat, ITerm) -> List MlirAttr
    at entry axes = map (\(axis, term) => Idr (entry axis (termNodes ix term))) axes

    inputs : Nat -> List (List (Nat, ITerm)) -> List MlirAttr
    inputs position [] = []
    inputs position (axes :: rest) = at (ExtentAttr OnInput position) axes ++ inputs (S position) rest

||| A function, located by its Idris name, each parameter by the name Idris
||| gave it, its erased index parameters its telescope, the index term each
||| `?` of its signature's tensors is its extents, then the functions its
||| lambdas and delays became, in the order their bodies were finished,
||| each with its symbol. Which one is the root is the program's to say,
||| not the function's. What Idris proved of its loops is its own
||| property. It is written from the state `initial` makes for it.
export
function : Index -> TFn -> E (List (String, Statement))
function ix f = do
  ((passed, res), ops) <- inFunction $ do
    bound <- traverse (\(i, p) => parameter ix f.loc f.callee.symbol (finToNat i, p))
                      (zip (range {len = f.arity}) (zip f.paramNames f.callee.params))
    let sc = MkScope (\i => fst (index i bound)) f.telescope
    res <- plain ix f.loc (para (alg ix) f.body sc (expecting (Just f.callee.result)))
    res' <- traverse (fit ix f.loc (Just f.callee.result)) res
    -- Each argument with the axes its parameter's type names: a position
    -- among the arguments is one among the parameters that take one, and
    -- the world takes none (`parameter`).
    pure (mapMaybe (\(b, axes) => (,axes) <$> snd b) (toList (zip bound f.extents.params)), res')
  body <- epilogue ix f.loc res ops
  let args = map fst passed
      type = FunctionType (MkSignature (map (\a => a.value.type) args) (resultTypes ix f.callee.result))
      extents = extentEntries ix (map snd passed) f.extents.result
      fn = functionOp f.callee.symbol (map (sortOf ix) f.telescope) extents type (MkRegion args body) f.termination
  lifted <- gets (.lifted)
  pure ((f.callee.symbol, MkStatement Nothing fn (Named (shown f.key.origin) f.loc)) :: (lifted <>> []))
