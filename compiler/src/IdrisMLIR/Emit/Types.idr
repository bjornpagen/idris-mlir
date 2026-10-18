-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Core's values as the contract's, each at the type the index gives
||| (Emit.Index).
module IdrisMLIR.Emit.Types

import IdrisMLIR.Emit.Index
import IdrisMLIR.Emit.Monad
import IdrisMLIR.MLIR
import IdrisMLIR.Types

import Control.Monad.State

%default total

||| A value as an op uses it: its name and its type as it is held.
export
operand : Val -> Value
operand v = MkValue v.name (heldType v.use v.type)

||| A value of type `t` held as `q`, of a fresh name, and the value that
||| binds it: a region's argument.
export
freshVal : Ty -> Quantity -> E (Val, Value)
freshVal t q = do
  n <- fresh
  let v = MkVal n t q
  pure (v, operand v)
