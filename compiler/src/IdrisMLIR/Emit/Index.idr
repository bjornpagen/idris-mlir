||| The program's declarations, by name, as the emitters look them up, and
||| the symbol each is written under.
module IdrisMLIR.Emit.Index

import IdrisMLIR.Ids
import IdrisMLIR.Term

import Data.List
import Data.Maybe
import Data.SortedMap

%default total

public export
record Index where
  constructor MkIndex
  datas : SortedMap DataId Data
  cons : SortedMap ConId Con
  fns : SortedMap FnId TFn
  ||| The symbol of each declaration and function: its key printed, with
  ||| `'n` on the n-th repeat of a printed form.
  dataSymbols : SortedMap DataId String
  fnSymbols : SortedMap FnId String

||| The symbols taken so far, each printed form with the next repeat number
||| to try for it.
Taken : Type
Taken = SortedMap String Nat

||| The symbol of a key printed as `p`: `p` itself the first time, else `p'n`
||| for the first `n` from the form's next repeat number that no symbol has
||| taken. Two keys that print alike are two identities, and a key that
||| prints as another's repeat (an Idris name may end in `'1`) is a third,
||| so no `idr.data` or `idr.func` shares a symbol. `fuel` counts the
||| symbols that can stand in the way, all those of the program.
claim : (fuel : Nat) -> String -> Taken -> (String, Taken)
claim fuel p taken = case lookup p taken of
  Nothing => (p, insert p 1 taken)
  Just n => repeat fuel n
  where
    repeat : Nat -> Nat -> (String, Taken)
    repeat (S more) n =
      let s = p ++ "'" ++ show n in
      case lookup s taken of
        Just _ => repeat more (S n)
        Nothing => (s, insert s 1 (insert p (S n) taken))
    repeat Z n = let s = p ++ "'" ++ show n in (s, insert s 1 (insert p (S n) taken))

||| The symbols of a list of keyed declarations, in order, after `taken`.
claimAll : Ord k => Nat -> List (k, String) -> Taken -> SortedMap k String -> (SortedMap k String, Taken)
claimAll fuel [] taken acc = (acc, taken)
claimAll fuel ((k, p) :: rest) taken acc =
  let (s, taken') = claim fuel p taken in claimAll fuel rest taken' (insert k s acc)

||| The index of a program. One counter of printed forms runs over the data
||| instances, then the functions, in the program's order, so the first
||| declaration of a printed form keeps it bare.
export
index : Source -> Index
index src =
  let fuel = length src.datas + length src.fns
      (dataSyms, taken) = claimAll fuel (map (\d => (d.id, keyText d.key)) src.datas) SortedMap.empty SortedMap.empty
      (fnSyms, _) = claimAll fuel (map (\f => (f.id, keyText f.key)) src.fns) taken SortedMap.empty
  in MkIndex (fromList (map (\d => (d.id, d)) src.datas))
             (fromList (concatMap (\d => map (\c => (c.id, c)) d.cons) src.datas))
             (fromList (map (\f => (f.id, f)) src.fns))
             dataSyms fnSyms

export
symbolOf : Index -> FnId -> Maybe String
symbolOf ix f = lookup f ix.fnSymbols

export
dataSymbolOf : Index -> DataId -> Maybe String
dataSymbolOf ix d = lookup d ix.dataSymbols

||| The names a report gives the functions and data instances of a term:
||| their symbols.
export
names : Index -> Names
names ix = MkNames (\f => fromMaybe (show f) (symbolOf ix f))
                   (\d => fromMaybe (show d) (dataSymbolOf ix d))
