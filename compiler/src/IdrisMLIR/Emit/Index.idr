-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The program's declarations, by name, as the emitters look them up: a
||| function's symbol and a data instance's type name are their ids' names,
||| the instance's key printed (Term.keyText), which the frontend interned
||| once; and each data instance's type, spelled once.
module IdrisMLIR.Emit.Index

import IdrisMLIR.Emit.Monad
import IdrisMLIR.Ids
import IdrisMLIR.MLIR
import IdrisMLIR.Term
import IdrisMLIR.Types

import Control.Relation
import Control.WellFounded
import Data.DPair
import Data.List
import Data.Nat
import Data.SortedMap

%default total

public export
record Index where
  constructor MkIndex
  datas : SortedMap DataId Data
  cons : SortedMap ConId Con
  fns : SortedMap FnId TFn
  ||| The type of each data instance: its body written whole, and in it
  ||| every body it holds, but inside its own body, where its name alone
  ||| names it.
  spelled : SortedMap DataId MlirType

------------------------------------------------------------------------------
-- Types
------------------------------------------------------------------------------

mutual
  ||| The contract type of a Core type, each data instance written as `data`
  ||| spells it.
  export
  typeWith : (DataId -> Either String MlirType) -> Ty -> Either String MlirType
  typeWith data' (IntT t) = Right (IntegerType (width t))
  typeWith data' CharT = Right (IntegerType 32)
  typeWith data' DoubleT = Right F64Type
  typeWith data' StrT = Right (Idr StrType)
  typeWith data' BigT = Right (Idr BigType)
  typeWith data' NatT = Right (Idr NatType)
  -- The world is its carrier at its one grade, (one, plain).
  typeWith data' WorldT = Right (Idr (QType One Plain (Idr WorldType)))
  typeWith data' (DataT d) = data' d
  typeWith data' (FunT (MkBinder q a) r) =
    (\x, y => Idr (FnType (MkSignature [x] [y]))) <$> heldWith data' q a <*> typeWith data' r
  typeWith data' (LazyT r) = (\t => Idr (LazyType t)) <$> typeWith data' r
  typeWith data' (TensorT ds e) = RankedTensorType ds <$> typeWith data' e
  -- Every memref the frontend writes is an array a world orders, in the
  -- world's memory.
  typeWith data' (MemRefT ds e) =
    (\t => MemRefType ds t (Just (Idr WorldSpaceAttr))) <$> typeWith data' e

  ||| The contract type of a value of a Core type used as `q` says: its
  ||| quantity is in the type, where no pass can lose it.
  export
  heldWith : (DataId -> Either String MlirType) -> Quantity -> Ty -> Either String MlirType
  heldWith data' q t =
    if linear q t then (\c => Idr (QType One Plain c)) <$> typeWith data' t else typeWith data' t

------------------------------------------------------------------------------
-- Data types, spelled once
------------------------------------------------------------------------------

||| `rest` holds fewer data instances than `u`.
Fewer : List Data -> List Data -> Type
Fewer rest u = LT (length rest) (length u)

||| A list of data instances can only lose so many before it is empty.
fewerAccessible : (u : List Data) -> Accessible Fewer u
fewerAccessible u = Access (below (length u))
  where
    below : (n : Nat) -> (y : List Data) -> LT (length y) n -> Accessible Fewer y
    below (S n) y (LTESucc yn) = Access (\z, zy => below n z (transitive zy yn))

||| The data instance `i` taken out of `u`, and what is left of `u`, which
||| holds fewer; nothing when `u` does not hold it.
enter : DataId -> (u : List Data) -> Maybe (Data, Subset (List Data) (\rest => Fewer rest u))
enter i [] = Nothing
enter i (d :: ds) =
  if d.id == i then Just (d, Element ds reflexive)
  else map (\(x, Element rest fewer) => (x, Element (d :: rest) (LTESucc fewer))) (enter i ds)

mutual
  ||| A data instance's identified type, where the bodies of `u` may still
  ||| be entered: its name, and, where its own may, the sum the frontend
  ||| gave it and its constructors in tag order, each field held as it
  ||| binds. A spelling so enters each body at most once along a path, and
  ||| entering one leaves fewer to enter, which is why it ends.
  spell : SortedMap DataId Data -> (u : List Data) -> (0 _ : Accessible Fewer u) -> DataId
       -> Either String MlirType
  spell datas u (Access rec) i = case enter i u of
    Just (d, Element rest fewer) => do
      ctors <- spellCtors datas rest (rec rest fewer) d.cons
      Right (Idr (DataType d.id.name (Just (MkIdrSum d.kind ctors (Just (d.key.origin, d.key.arguments))))))
    Nothing => case lookup i datas of
      Just d => Right (Idr (DataType d.id.name Nothing))
      Nothing => Left ("unknown data " ++ show i)

  ||| The constructors of a body: none is a label, which only
  ||| defunctionalization makes, and none runs on every force.
  spellCtors : SortedMap DataId Data -> (u : List Data) -> (0 _ : Accessible Fewer u) -> List Con
            -> Either String (List (IdrCtor MlirType))
  spellCtors datas u acc [] = Right []
  spellCtors datas u acc (c :: cs) = do
    fs <- spellFields datas u acc c.fields
    (MkIdrCtor c.id.name fs False c.role Nothing ::) <$> spellCtors datas u acc cs

  spellFields : SortedMap DataId Data -> (u : List Data) -> (0 _ : Accessible Fewer u) -> List Binder
             -> Either String (List MlirType)
  spellFields datas u acc [] = Right []
  spellFields datas u acc (MkBinder q t :: bs) =
    (::) <$> heldWith (spell datas u acc) q t <*> spellFields datas u acc bs

||| The index of a program: an internal error when a type names data the
||| program does not declare.
export
index : Source -> Either String Index
index src = do
  let datas = fromList (map (\d => (d.id, d)) src.datas)
  spelled <- traverse (\d => (\t => (d.id, t)) <$> spell datas src.datas (fewerAccessible src.datas) d.id)
                      src.datas
  Right (MkIndex datas
                 (fromList (concatMap (\d => map (\c => (c.id, c)) d.cons) src.datas))
                 (fromList (map (\f => (f.id, f)) src.fns))
                 (fromList spelled))

||| The names a report gives the functions and data instances of a term:
||| their symbols.
export
names : Index -> Names
names ix = MkNames (.name) (.name)
