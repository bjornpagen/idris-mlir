-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The program's declarations, by name, as the emitters look them up. A
||| function's symbol and a data instance's type name are their ids' names,
||| the instance's key printed (Term.keyText), which the frontend interned
||| once.
module IdrisMLIR.Emit.Index

import IdrisMLIR.Ids
import IdrisMLIR.Term

import Data.List
import Data.SortedMap

%default total

public export
record Index where
  constructor MkIndex
  datas : SortedMap DataId Data
  cons : SortedMap ConId Con
  fns : SortedMap FnId TFn
  ||| How many data instances the program has: how many bodies one type's
  ||| spelling can enter, each at most once.
  dataCount : Nat

||| The index of a program.
export
index : Source -> Index
index src =
  MkIndex (fromList (map (\d => (d.id, d)) src.datas))
          (fromList (concatMap (\d => map (\c => (c.id, c)) d.cons) src.datas))
          (fromList (map (\f => (f.id, f)) src.fns))
          (length src.datas)

||| The names a report gives the functions and data instances of a term:
||| their symbols.
export
names : Index -> Names
names ix = MkNames (.name) (.name)
