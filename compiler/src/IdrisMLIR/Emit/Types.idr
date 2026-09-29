||| Core's types as the contract's, and typed parameters.
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

||| The contract type of a Core type.
mtype : Index -> Ty -> E MType
mtype ix (IntT t) = pure (I (width t))
mtype ix CharT = pure (I 32)
mtype ix DoubleT = pure F64
mtype ix StrT = pure Str
mtype ix BigT = pure Big
mtype ix WorldT = pure World
mtype ix ErasedT = pure Erased
mtype ix (DataT d) = case lookup d ix.datas of
  Just dt => pure (case dt.repr of
                     Sop => Data (mangle d.name)
                     Box => Boxed (mangle d.name))
  Nothing => internal ("unknown data " ++ show d)
mtype ix (FunT _ a r) = pure (Fn [!(mtype ix a)] [!(mtype ix r)])
mtype ix (LazyT r) = pure (Fn [] [!(mtype ix r)])

export
typeText : Index -> Ty -> E String
typeText ix t = showType <$> mtype ix t

||| `"0"` exactly on an erased value.
export
quantityOf : Ty -> Quantity -> E Quantity
quantityOf ErasedT _ = pure Q0
quantityOf t Q0 = internal ("a quantity-0 binder of type " ++ show t)
quantityOf _ q = pure q

||| A typed parameter with its quantity: `%3: i64 {idr.quantity = "w"}`.
export
param : Index -> Val -> E String
param ix v = do
  q <- quantityOf v.type v.quantity
  pure (v.name ++ ": " ++ !(typeText ix v.type) ++ " {idr.quantity = " ++ quoted (show q) ++ "}")
