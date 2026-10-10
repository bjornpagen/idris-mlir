||| A table of entries indexed by Int, each slot empty until it is written,
||| on a growable linear array: its size is the number of slots claimed. A
||| slot past it is empty to read and not there to write. The table is
||| threaded as one object, so each operation updates it in place, and
||| claiming a slot past the end grows it to at least twice its capacity:
||| claiming n slots copies fewer than 2n entries in all.
|||
||| This is the only module of the fork that imports `Linear.Array`, whose
||| `map`, `foldl`, `read` and `size` would otherwise stand beside the
||| prelude's names wherever the table is used.
module Libraries.Data.Table

import Linear.Array

%default total

export
Table : Type -> Type
Table a = Array (Maybe a)

||| An empty table with room for `n` slots before it grows.
export
newTable : Int -> Table a
newTable n = reserve (mkArray 0 Nothing) n Nothing

||| Slot `i`, with the table given back: empty for an index never claimed,
||| and for one claimed and not yet written.
export
lookupSlot : Int -> (1 _ : Table a) -> Res (Maybe a) (const (Table a))
lookupSlot i t = let n # t' = size t in
                 if 0 <= i && i < n then read t' i else Nothing # t'

||| The table with slot `i` claimed. `i` is at most its size: a slot it
||| already has is kept as it is, and the one past the last is added empty.
export
claimSlot : Int -> (1 _ : Table a) -> Table a
claimSlot i t = let n # t' = size t in if i < n then t' else push t' Nothing

||| The table with `x` in slot `i`, which it has claimed.
export
setSlot : Int -> a -> (1 _ : Table a) -> Table a
setSlot i x t = write t i (Just x)
