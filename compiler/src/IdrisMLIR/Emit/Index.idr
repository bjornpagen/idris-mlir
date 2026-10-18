-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The program's declarations, by name, as the emitters look them up: a
||| function's symbol and a data instance's type name are their ids' names,
||| the instance's key printed (Term.keyText), which the frontend interned
||| once; Core's types as the contract's, each data instance by its name;
||| and each data instance's body, the module's table of data types.
module IdrisMLIR.Emit.Index

import IdrisMLIR.Emit.Monad
import IdrisMLIR.Ids
import IdrisMLIR.MLIR
import IdrisMLIR.Term
import IdrisMLIR.Types

import Data.List
import Data.SortedMap

%default total

public export
record Index where
  constructor MkIndex
  datas : SortedMap DataId Data
  cons : SortedMap ConId Con
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
  -- The world is its carrier at its one grade, (one, plain).
  mlirType WorldT = idr (QType One Plain (idr WorldType))
  mlirType (DataT d) = idr (DataType d.name)
  mlirType (FunT (MkBinder q a) r) = idr (FnType (MkSignature [heldType q a] [mlirType r]))
  mlirType (LazyT r) = idr (LazyType (mlirType r))
  mlirType (TensorT ds e) = RankedTensorType ds (mlirType e)
  -- Every memref the frontend writes is an array a world orders, in the
  -- world's memory.
  mlirType (MemRefT ds e) = MemRefType ds (mlirType e) (Just (idr WorldSpaceAttr))

  ||| The contract type of a value of a Core type used as `q` says: its
  ||| quantity is in the type, where no pass can lose it.
  export
  heldType : Quantity -> Ty -> MlirType
  heldType q t = if linear q t then idr (QType One Plain (mlirType t)) else mlirType t

------------------------------------------------------------------------------
-- The table
------------------------------------------------------------------------------

||| A data instance's body: the sum the frontend gave it, its constructors
||| in tag order, each field held as it binds, and the instance it is of.
||| None is a label, which only defunctionalization makes, and none runs on
||| every force.
body : Data -> IdrSum MlirType
body d = MkIdrSum d.kind (map ctor d.cons) (Just (d.key.origin, d.key.arguments))
  where
    ctor : Con -> IdrCtor MlirType
    ctor c = MkIdrCtor c.name (map (\(MkBinder q t) => heldType q t) c.fields) False c.role Nothing

||| The index of a program.
export
index : Source -> Index
index src =
  MkIndex (fromList (map (\d => (d.id, d)) src.datas))
          (fromList (foldr (\d, rest => map (\c => (c.id, c)) d.cons ++ rest) [] src.datas))
          (fromList (map (\f => (f.id, f)) src.fns))
          (map (\d => (d.id.name, body d)) src.datas)

||| The names a report gives the functions, data instances and constructors
||| of a term: their symbols; a constructor the program does not declare, by
||| its identity.
export
names : Index -> Names
names ix = MkNames (.name) (.name) (\c => maybe (show c) (.name) (lookup c ix.cons))
