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

||| The erased value's type: of quantity zero, and of no carrier.
erased : MlirType
erased = Idr (QType Zero Plain NoneType)

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
  mlirType ix ErasedT = pure erased
  mlirType ix (DataT d) = case lookup d ix.datas of
    Just dt => pure (case dt.repr of
                       Sop => Idr (DataType (mangle d.name))
                       Box => Idr (BoxType (mangle d.name)))
    Nothing => internal ("unknown data " ++ show d)
  mlirType ix (FunT a r) =
    pure (Idr (FnType (MkSignature [!(binderType ix a)] [!(mlirType ix r)])))
  mlirType ix (LazyT r) = (\t => Idr (LazyType t)) <$> mlirType ix r
  mlirType ix (ArrayT r e) = MemRefType (dimensions r) <$> mlirType ix e

  ||| The contract type of what a binder binds: its quantity is in the
  ||| type, where no pass can lose it.
  export
  binderType : Index -> Binder -> E MlirType
  binderType ix Gone = pure erased
  binderType ix (Held u t) =
    if linear u t then (\c => Idr (QType One Plain c)) <$> mlirType ix t else mlirType ix t

||| The contract type of a value of type `t` used as `u` says.
export
heldType : Index -> Use -> Ty -> E MlirType
heldType ix u t = binderType ix (Held u t)

||| A value as an op uses it: its name and its type as it is held.
export
operand : Index -> Val -> E Value
operand ix v = MkValue v.name <$> heldType ix v.use v.type
