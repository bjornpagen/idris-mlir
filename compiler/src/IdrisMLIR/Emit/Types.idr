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
import Data.List
import Data.SortedMap

%default total

||| The symbol of a function.
export
fnSymbol : Index -> FnId -> E String
fnSymbol ix f = case lookup f ix.fns of
  Just _ => pure f.name
  Nothing => internal ("a function " ++ show f ++ ", which is not in the program")

||| The sum a data instance is, by the one fact the registry gives it: base's
||| list, whose constructors play nil and cons, or a type that keeps a
||| promise, or neither.
kindOf : Data -> SumKind
kindOf d =
  if map (.role) d.cons == [Just ListNil, Just ListCons] then BaseList
  else maybe Plain promised d.promise
  where
    promised : Promise -> SumKind
    promised Types.InPlace = SumKind.InPlace

||| The one constructor of a record, the element of an array of records.
recordOf : Index -> DataId -> E Con
recordOf ix r = case (.cons) <$> lookup r ix.datas of
  Just [c] => pure c
  _ => internal (show r ++ ", the element of an array of records, is no record")

||| The columns of an array of records of kind `k` and dimensions `ds`: one
||| array per field of the record, in field order, of the array's kind and
||| dimensions and of the field's type; a field that is a value array adds
||| its dimensions after the array's, a field that is an array of records
||| its columns.
export
columnsOf : Index -> ArrayKind -> List Dim -> DataId -> E (List Ty)
columnsOf ix k ds r = map (column k . typeOf) . (.fields) <$> recordOf ix r
  where
    column : ArrayKind -> Ty -> Ty
    column ValueArray (TensorT es e) = TensorT (ds ++ es) e
    column ValueArray (ColumnsT ValueArray es r') = ColumnsT ValueArray (ds ++ es) r'
    column ValueArray t = TensorT ds t
    column OrderedArray t = MemRefT ds t

mutual
  ||| The contract type of a Core type, spelled inside the bodies of the
  ||| data instances `inside` names: a data type is written with its body
  ||| everywhere but inside its own body, where its name alone names it.
  ||| `fuel` counts the bodies and the columns a spelling may still enter,
  ||| at most one per data instance of the program. An array of records is
  ||| no one type: where it stands its columns do (`typesIn`).
  typeIn : Index -> (fuel : Nat) -> List DataId -> Ty -> E MlirType
  typeIn ix fuel inside (IntT t) = pure (IntegerType (width t))
  typeIn ix fuel inside CharT = pure (IntegerType 32)
  typeIn ix fuel inside DoubleT = pure F64Type
  typeIn ix fuel inside StrT = pure (Idr StrType)
  typeIn ix fuel inside BigT = pure (Idr BigType)
  typeIn ix fuel inside NatT = pure (Idr NatType)
  -- The world is its carrier at its one grade, (one, plain).
  typeIn ix fuel inside WorldT = pure (Idr (QType One Plain (Idr WorldType)))
  typeIn ix fuel inside (DataT d) = case lookup d ix.datas of
    Just dt => do
      t <- dataIn ix fuel inside dt
      pure (case dt.repr of
              Sop => t
              Box => Idr (BoxType t))
    Nothing => internal ("unknown data " ++ show d)
  typeIn ix fuel inside (FunT (MkBinder q a) r) =
    pure (Idr (FnType (MkSignature !(typesIn ix fuel inside q a) !(typesIn ix fuel inside Many r))))
  typeIn ix fuel inside (LazyT r) = (\t => Idr (LazyType t)) <$> typeIn ix fuel inside r
  typeIn ix fuel inside (TensorT ds e) = RankedTensorType ds <$> typeIn ix fuel inside e
  -- Every memref the frontend writes is an array a world orders, in the
  -- world's memory.
  typeIn ix fuel inside (MemRefT ds e) =
    (\t => MemRefType ds t (Just (Idr WorldSpaceAttr))) <$> typeIn ix fuel inside e
  typeIn ix fuel inside (ColumnsT k ds r) =
    internal ("an array of records of " ++ show r ++ " where one value is held")

  ||| The contract types of a value of a Core type held as `q` says: its
  ||| one type, or each of its columns.
  typesIn : Index -> (fuel : Nat) -> List DataId -> Quantity -> Ty -> E (List MlirType)
  typesIn ix (S more) inside q (ColumnsT k ds r) = do
    cols <- columnsOf ix k ds r
    columnTypes ix more inside q cols
  typesIn ix Z inside q (ColumnsT k ds r) =
    internal ("the columns of " ++ show r ++ " inside more types than there are data types")
  typesIn ix fuel inside q t = (:: []) <$> heldIn ix fuel inside q t

  columnTypes : Index -> Nat -> List DataId -> Quantity -> List Ty -> E (List MlirType)
  columnTypes ix fuel inside q [] = pure []
  columnTypes ix fuel inside q (c :: cs) =
    (++) <$> typesIn ix fuel inside q c <*> columnTypes ix fuel inside q cs

  ||| A data instance's identified type: its name, and, outside its own
  ||| body, its constructors in tag order, each field held as it binds, a
  ||| field that is an array of records as its columns.
  dataIn : Index -> (fuel : Nat) -> List DataId -> Data -> E MlirType
  dataIn ix fuel inside d =
    if elem d.id inside then pure (Idr (DataType d.id.name Nothing)) else withBody ix fuel inside d

  withBody : Index -> (fuel : Nat) -> List DataId -> Data -> E MlirType
  withBody ix Z inside d =
    internal ("the body of " ++ show d.id ++ " inside more bodies than there are data types")
  withBody ix (S more) inside d = do
    ctors <- ctorsIn ix more (d.id :: inside) d.cons
    pure (Idr (DataType d.id.name
                (Just (MkIdrSum (kindOf d) ctors (Just (d.key.origin, d.key.arguments))))))

  ctorsIn : Index -> Nat -> List DataId -> List Con -> E (List (IdrCtor MlirType))
  ctorsIn ix fuel inside [] = pure []
  ctorsIn ix fuel inside (c :: cs) = do
    fs <- fieldsIn ix fuel inside c.fields
    (MkIdrCtor c.id.name fs False ::) <$> ctorsIn ix fuel inside cs

  fieldsIn : Index -> Nat -> List DataId -> List Binder -> E (List MlirType)
  fieldsIn ix fuel inside [] = pure []
  fieldsIn ix fuel inside (MkBinder q t :: bs) =
    (++) <$> typesIn ix fuel inside q t <*> fieldsIn ix fuel inside bs

  heldIn : Index -> (fuel : Nat) -> List DataId -> Quantity -> Ty -> E MlirType
  heldIn ix fuel inside q t =
    if linear q t then (\c => Idr (QType One Plain c)) <$> typeIn ix fuel inside t
    else typeIn ix fuel inside t

||| The contract type of a Core type.
export
mlirType : Index -> Ty -> E MlirType
mlirType ix = typeIn ix ix.dataCount []

||| The contract type of a value of type `t` used as `q` says: its quantity
||| is in the type, where no pass can lose it.
export
heldType : Index -> Quantity -> Ty -> E MlirType
heldType ix = heldIn ix ix.dataCount []

||| The contract types of a value of type `t` used as `q` says: one, or one
||| per column of an array of records, in order.
export
heldTypes : Index -> Quantity -> Ty -> E (List MlirType)
heldTypes ix = typesIn ix ix.dataCount []

||| The contract type of what a binder binds.
export
binderType : Index -> Binder -> E MlirType
binderType ix (MkBinder q t) = heldType ix q t

||| The contract types of what a binder binds.
export
binderTypes : Index -> Binder -> E (List MlirType)
binderTypes ix (MkBinder q t) = heldTypes ix q t

||| A value held whole as an op uses it: its name and its type as it is
||| held.
export
operand : Index -> Val -> E Value
operand ix (MkVal n t u Whole) = MkValue n <$> heldType ix u t
operand ix v = internal ("one operand of a value of type " ++ show v.type ++ " held in parts")

mutual
  ||| A value as ops use it: itself, or each of its columns, in order. A
  ||| constructor taken apart is built again first (Operations.force).
  export
  operandsOf : Index -> Val -> E (List Value)
  operandsOf ix (MkVal n t u (Columns ps)) = allOperands ix ps
  operandsOf ix v = (:: []) <$> operand ix v

  allOperands : Index -> List Val -> E (List Value)
  allOperands ix [] = pure []
  allOperands ix (v :: vs) = (++) <$> operandsOf ix v <*> allOperands ix vs

||| A value of type `t` held as `q`, named from `names` in order: its one
||| name, or one per column, the columns of an array of records being
||| values in their own right; and the names left over.
export
fromNames : Index -> Ty -> Quantity -> List String -> E (Val, List String)
fromNames ix t q = go ix.dataCount t
  where
    mutual
      go : Nat -> Ty -> List String -> E (Val, List String)
      go (S more) (ColumnsT k ds r) ns = do
        cols <- columnsOf ix k ds r
        (ps, rest) <- goAll more cols ns
        key <- fresh
        pure (MkVal key (ColumnsT k ds r) q (Columns ps), rest)
      go Z (ColumnsT _ _ r) ns = internal ("the columns of " ++ show r ++ " nested deeper than there are data types")
      go fuel t (n :: rest) = pure (val n t q, rest)
      go fuel t [] = internal ("fewer values than a value of type " ++ show t ++ " has")

      goAll : Nat -> List Ty -> List String -> E (List Val, List String)
      goAll fuel [] ns = pure ([], ns)
      goAll fuel (c :: cs) ns = do
        (v, rest) <- go fuel c ns
        (vs, rest') <- goAll fuel cs rest
        pure (v :: vs, rest')

||| A value of type `t` held as `q`, of fresh names, and the values that
||| bind it: a region's arguments, one per column of an array of records.
export
freshVal : Index -> Ty -> Quantity -> E (Val, List Value)
freshVal ix t q = do
  types <- heldTypes ix q t
  names <- traverse (const fresh) types
  (v, _) <- fromNames ix t q names
  pure (v, zipWith MkValue names types)
