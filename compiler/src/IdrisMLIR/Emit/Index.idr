||| The program's declarations, by name, as the emitters look them up: the
||| module's symbol table.
module IdrisMLIR.Emit.Index

import IdrisMLIR.Ids
import IdrisMLIR.MLIR.Text
import IdrisMLIR.Term

import Data.List
import Data.SortedMap

%default total

||| Each declaration with its symbol, which every reference to it writes:
||| mangled once, where it is declared, rather than at each reference, as
||| an instance's name runs to thousands of characters and is referred to
||| from every call.
public export
record Index where
  constructor MkIndex
  datas : SortedMap DataId (Data, String)
  cons : SortedMap ConId (Con, SymbolRef)
  fns : SortedMap FnId (TFn, String)

export
index : Source -> Index
index src =
  MkIndex (fromList (map (\d => (d.id, (d, mangle d.id.name))) src.datas))
          (fromList (foldr (\d, rest => map (con (mangle d.id.name)) d.cons ++ rest) [] src.datas))
          (fromList (map (\f => (f.id, (f, mangle f.id.name))) src.fns))
  where
    con : String -> Con -> (ConId, (Con, SymbolRef))
    con dataSymbol c = (c.id, (c, MkSymbolRef dataSymbol [mangle c.id.name]))
