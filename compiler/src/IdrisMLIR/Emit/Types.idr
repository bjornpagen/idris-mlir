-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Core's functions and values as the contract's, each at the type the
||| index gives (Emit.Index).
module IdrisMLIR.Emit.Types

import IdrisMLIR.Emit.Index
import IdrisMLIR.Emit.Monad
import IdrisMLIR.Ids
import IdrisMLIR.MLIR
import IdrisMLIR.Term
import IdrisMLIR.Types

import Control.Monad.State
import Data.SortedMap

%default total

||| The symbol of a function.
export
fnSymbol : Index -> FnId -> E String
fnSymbol ix f = case lookup f ix.fns of
  Just _ => pure f.name
  Nothing => internal ("a function " ++ show f ++ ", which is not in the program")

||| A value held whole as an op uses it: its name and its type as it is
||| held. A constructor taken apart is built again first (Operations.force).
export
operand : Index -> Val -> E Value
operand ix (MkVal n t u Whole) = pure (MkValue n (heldType u t))
operand ix v = internal ("one operand of a value of type " ++ show v.type ++ " taken apart")

||| A value of type `t` held as `q`, of a fresh name, and the value that
||| binds it: a region's argument.
export
freshVal : Index -> Ty -> Quantity -> E (Val, Value)
freshVal ix t q = do
  n <- fresh
  pure (val n t q, MkValue n (heldType q t))
