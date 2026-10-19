-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The program's declarations as the emitters look them up: each function,
||| by its id, whose name is its symbol, the instance's key printed
||| (Term.keyText), which the frontend interned once; Core's types as the
||| contract's, each data instance by its name; and each data instance's
||| body, the module's table of data types.
module IdrisMLIR.Emit.Index

import IdrisMLIR.Emit.Monad
import IdrisMLIR.Ids
import IdrisMLIR.MLIR
import IdrisMLIR.Term
import IdrisMLIR.Types

import Data.List
import Data.SortedMap
import Data.Vect

%default total

public export
record Index where
  constructor MkIndex
  fns : SortedMap FnId TFn
  ||| The body of each data instance, by its type's name, in the program's
  ||| order: the module's table (MLIR.Bytecode.newWriter).
  table : List (String, IdrSum MlirType)

------------------------------------------------------------------------------
-- Types
------------------------------------------------------------------------------

mutual
  ||| The contract type of a Core type: a data instance is named, its body
  ||| the table's.
  export
  mlirType : Ty -> MlirType
  mlirType (IntT t) = IntegerType (width t)
  mlirType CharT = IntegerType 32
  mlirType DoubleT = F64Type
  mlirType StrT = idr StrType
  mlirType BigT = idr BigType
  mlirType NatT = idr NatType
  mlirType WorldT = idr WorldType
  mlirType (DataT d) = idr (DataType d.name)
  mlirType (FunT (MkBinder q a) r) = idr (FnType (MkSignature [heldType q a] [mlirType r]))
  mlirType (LazyT r) = idr (LazyType (mlirType r))
  mlirType (TensorT ds e) = RankedTensorType ds (mlirType e)
  -- Every memref the frontend writes is an array a world orders, in the
  -- world's memory.
  mlirType (MemRefT o e) = MemRefType (orderedDims o) (mlirType e) (Just (idr WorldSpaceAttr))

  ||| The contract type of a value of a Core type used as `q` says: its
  ||| quantity is in the type, where no pass can lose it.
  export
  heldType : Quantity -> Ty -> MlirType
  heldType q t = if linear q t then idr (QType One Plain (mlirType t) Nothing) else mlirType t

------------------------------------------------------------------------------
-- The table
------------------------------------------------------------------------------

||| A data instance's body: the sum its shape is, its constructors in tag
||| order, each field held as it binds, each playing the part the shape
||| gives it, and the instance it is of. None is a label, which only
||| defunctionalization makes.
body : Data -> IdrSum MlirType
body d = case d.shape of
  PlainSum cs => MkIdrSum Plain (map (ctor CtorRole.Plain) cs) inst
  InPlaceSum cs => MkIdrSum InPlace (map (ctor CtorRole.Plain) cs) inst
  BaseListSum nil cons => MkIdrSum BaseList [ctor ListNil (0 ** nil), ctor ListCons (2 ** cons)] inst
  where
    inst : Maybe (String, List String)
    inst = Just (d.key.origin, argumentsText d.key.arguments)
    ctor : CtorRole -> (k ** Con k) -> IdrCtor MlirType
    ctor r (_ ** c) = MkIdrCtor c.name (toList (map (\(MkBinder q t) => heldType q t) c.fields)) r

||| The index of a program.
export
index : Source -> Index
index src =
  MkIndex (fromList (map (\f => (f.id, f)) (src.root :: src.others)))
          (map (\d => (d.id.name, body d)) src.datas)

||| The names a report gives the functions and data instances of a term:
||| their symbols.
export
names : Index -> Names
names ix = MkNames (.name) (.name)
