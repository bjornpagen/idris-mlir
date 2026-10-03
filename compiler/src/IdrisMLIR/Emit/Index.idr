||| The program's declarations, by name, as the emitters look them up.
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

export
index : Source -> Index
index src =
  MkIndex (fromList (map (\d => (d.id, d)) src.datas))
          (fromList (concatMap (\d => map (\c => (c.id, c)) d.cons) src.datas))
          (fromList (map (\f => (f.id, f)) src.fns))
