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

mutual
  ||| The contract type of a Core type.
  mtype : Index -> Ty -> E MType
  mtype ix (IntT t) = pure (I (width t))
  mtype ix CharT = pure (I 32)
  mtype ix DoubleT = pure F64
  mtype ix StrT = pure Str
  mtype ix BigT = pure Big
  mtype ix NatT = pure Natural
  mtype ix WorldT = pure World
  mtype ix ErasedT = pure Erased
  mtype ix (DataT d) = case lookup d ix.datas of
    Just dt => pure (case dt.repr of
                       Sop => Data (mangle d.name)
                       Box => Boxed (mangle d.name))
    Nothing => internal ("unknown data " ++ show d)
  mtype ix (FunT a r) = pure (Fn [!(binderType ix a)] [!(mtype ix r)])
  mtype ix (LazyT r) = pure (Fn [] [!(mtype ix r)])

  ||| The contract type of what a binder binds: its quantity is in the
  ||| type, where no pass can lose it.
  binderType : Index -> Binder -> E MType
  binderType ix Gone = pure Erased
  binderType ix (Held u t) = case modeOf u t of
    Plain => mtype ix t
    Linear => Lin <$> mtype ix t

||| The contract type of a value of type `t` held as `mode` says.
heldType : Index -> Mode -> Ty -> E MType
heldType ix Plain t = mtype ix t
heldType ix Linear t = Lin <$> mtype ix t

export
typeText : Index -> Ty -> E String
typeText ix t = showType <$> mtype ix t

export
binderText : Index -> Binder -> E String
binderText ix b = showType <$> binderType ix b

||| The contract type of a value as it is held.
export
valText : Index -> Val -> E String
valText ix v = showType <$> heldType ix v.mode v.type

||| A typed parameter: `%3: !idr.lin<i64>`.
export
param : Index -> Val -> E String
param ix v = pure (v.name ++ ": " ++ !(valText ix v))
