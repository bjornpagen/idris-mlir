-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Core's types as the contract's, in the dialects' vocabulary: each data
||| instance as the index spelled it (Emit.Index).
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

||| A data instance's type, as the index spelled it.
spelledData : Index -> DataId -> Either String MlirType
spelledData ix d = maybe (Left ("unknown data " ++ show d)) Right (lookup d ix.spelled)

||| The contract type of a Core type.
export
mlirType : Index -> Ty -> E MlirType
mlirType ix t = lift (typeWith (spelledData ix) t)

||| The contract type of a value of type `t` used as `q` says: its quantity
||| is in the type, where no pass can lose it.
export
heldType : Index -> Quantity -> Ty -> E MlirType
heldType ix q t = lift (heldWith (spelledData ix) q t)

||| The contract type of what a binder binds.
export
binderType : Index -> Binder -> E MlirType
binderType ix (MkBinder q t) = heldType ix q t

||| A value held whole as an op uses it: its name and its type as it is
||| held. A constructor taken apart is built again first (Operations.force).
export
operand : Index -> Val -> E Value
operand ix (MkVal n t u Whole) = MkValue n <$> heldType ix u t
operand ix v = internal ("one operand of a value of type " ++ show v.type ++ " taken apart")

||| A value of type `t` held as `q`, of a fresh name, and the value that
||| binds it: a region's argument.
export
freshVal : Index -> Ty -> Quantity -> E (Val, Value)
freshVal ix t q = do
  n <- fresh
  ty <- heldType ix q t
  pure (val n t q, MkValue n ty)
