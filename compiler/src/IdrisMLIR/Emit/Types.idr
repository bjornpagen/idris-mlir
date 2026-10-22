-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Core's values as the module's, each at the type its uses and hold give
||| it (Emit.Index).
module IdrisMLIR.Emit.Types

import IdrisMLIR.Emit.Index
import IdrisMLIR.Emit.Monad
import IdrisMLIR.MLIR
import IdrisMLIR.Spec.Grades.Grade
import IdrisMLIR.Types

import Control.Monad.State

%default total

||| A value as an op uses it: its name and its type as it is graded.
export
operand : Index -> Val -> Value
operand ix v = MkValue v.name (valueType ix v)

||| A value of type `t` used as `q` and freed by its count, of a fresh
||| name, and the value that binds it: a region's argument.
export
freshVal : Index -> Ty -> Uses -> E (Val, Value)
freshVal ix t q = do
  n <- fresh
  let v = val n t q made
  pure (v, operand ix v)
