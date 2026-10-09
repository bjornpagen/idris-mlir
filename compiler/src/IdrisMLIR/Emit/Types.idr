||| Core's types as the contract's, in the dialects' vocabulary.
module IdrisMLIR.Emit.Types

import IdrisMLIR.CustomSyntax as Idr
import IdrisMLIR.Dialect.Idr as Idr
import IdrisMLIR.Emit.Index
import IdrisMLIR.Emit.Monad
import IdrisMLIR.Ids
import IdrisMLIR.MLIR
import IdrisMLIR.Term
import IdrisMLIR.Types

import Control.Monad.State
import Data.SortedMap

%default total

mutual
  ||| The contract type of a Core type.
  export
  mlirType : Index -> Ty -> E MlirType
  mlirType ix (IntT t) = pure (integerType (width t))
  mlirType ix CharT = pure (integerType 32)
  mlirType ix DoubleT = pure f64Type
  mlirType ix StrT = pure Idr.strType
  mlirType ix BigT = pure Idr.bigType
  mlirType ix NatT = pure Idr.natType
  mlirType ix WorldT = pure Idr.world
  mlirType ix ErasedT = pure Idr.erased
  mlirType ix (DataT d) = case lookup d ix.datas of
    Just dt => pure (case dt.repr of
                       Sop => Idr.dataType (mangle d.name)
                       Box => Idr.boxType (mangle d.name))
    Nothing => internal ("unknown data " ++ show d)
  mlirType ix (FunT a r) = pure (Idr.fnType [!(binderType ix a)] [!(mlirType ix r)])
  mlirType ix (LazyT r) = Idr.lazyType <$> mlirType ix r
  mlirType ix (ArrayT r e) = memRefType (dimensions r) <$> mlirType ix e

  ||| The contract type of what a binder binds: its quantity is in the
  ||| type, where no pass can lose it.
  export
  binderType : Index -> Binder -> E MlirType
  binderType ix Gone = pure Idr.erased
  binderType ix (Held u t) =
    if linear u t then Idr.lin <$> mlirType ix t else mlirType ix t

||| The contract type of a value of type `t` used as `u` says.
export
heldType : Index -> Use -> Ty -> E MlirType
heldType ix u t = binderType ix (Held u t)

||| A value as an op uses it: its name and its type as it is held.
export
operand : Index -> Val -> E Value
operand ix v = MkValue v.name <$> heldType ix v.use v.type
