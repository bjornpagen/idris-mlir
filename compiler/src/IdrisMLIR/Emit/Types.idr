-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Core's types as the contract's, in the dialects' vocabulary.
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
fnSymbol ix f = maybe (internal ("a function " ++ show f ++ ", which is not in the program")) pure
                      (symbolOf ix f)

||| The symbol of a data instance.
export
dataSymbol : Index -> DataId -> E String
dataSymbol ix d = maybe (internal ("unknown data " ++ show d)) pure (dataSymbolOf ix d)

mutual
  ||| The contract type of a Core type.
  export
  mlirType : Index -> Ty -> E MlirType
  mlirType ix (IntT t) = pure (IntegerType (width t))
  mlirType ix CharT = pure (IntegerType 32)
  mlirType ix DoubleT = pure F64Type
  mlirType ix StrT = pure (Idr StrType)
  mlirType ix BigT = pure (Idr BigType)
  mlirType ix NatT = pure (Idr NatType)
  -- The world is its carrier at its one grade, (one, plain).
  mlirType ix WorldT = pure (Idr (QType One Plain (Idr WorldType)))
  mlirType ix (DataT d) = case lookup d ix.datas of
    Just dt => do
      sym <- dataSymbol ix d
      pure (case dt.repr of
              Sop => Idr (DataType sym)
              Box => Idr (BoxType sym))
    Nothing => internal ("unknown data " ++ show d)
  mlirType ix (FunT a r) =
    pure (Idr (FnType (MkSignature [!(binderType ix a)] [!(mlirType ix r)])))
  mlirType ix (LazyT r) = (\t => Idr (LazyType t)) <$> mlirType ix r
  mlirType ix (ArrayT r e) = MemRefType (dimensions r) <$> mlirType ix e

  ||| The contract type of what a binder binds: its quantity is in the
  ||| type, where no pass can lose it.
  export
  binderType : Index -> Binder -> E MlirType
  binderType ix (MkBinder q t) = heldType ix q t

  ||| The contract type of a value of type `t` used as `q` says.
  export
  heldType : Index -> Quantity -> Ty -> E MlirType
  heldType ix q t =
    if linear q t then (\c => Idr (QType One Plain c)) <$> mlirType ix t else mlirType ix t

||| A value as an op uses it: its name and its type as it is held.
export
operand : Index -> Val -> E Value
operand ix v = MkValue v.name <$> heldType ix v.use v.type
