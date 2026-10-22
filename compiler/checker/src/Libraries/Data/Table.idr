-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2026 Bjorn Pagen
||| A table of entries indexed by Int, each slot empty until it is written,
||| on base's mutable array, held in a reference and changed in the world's
||| order. The array's length is the table's capacity; claiming a slot past
||| it moves the table to an array at least twice as long: claiming n slots
||| copies fewer than 2n entries in all.
|||
||| The table keeps no count of the slots claimed: its holder counts them
||| already, and a slot past that count was never written, so it reads
||| empty, as a slot past the capacity does.
module Libraries.Data.Table

import Data.IOArray
import Data.IORef

%default total

export
Table : Type -> Type
Table a = IORef (IOArray a)

||| An empty table with room for `n` slots before it grows.
export
newTable : HasIO io => Int -> io (Table a)
newTable n = newIORef !(newArray (Prelude.max 0 n))

||| Slot `i`: empty for an index never claimed, and for one claimed and not
||| yet written.
export
lookupSlot : HasIO io => Int -> Table a -> io (Maybe a)
lookupSlot i t = readArray !(readIORef t) i

||| The capacity an array of `cap` slots grows to when `need` are needed:
||| at least double, and at least 4, so that the first claims on an empty
||| table do not each copy.
grown : (cap, need : Int) -> Int
grown cap need = Prelude.max need (Prelude.max 4 (2 * cap))

||| The table with slot `i` claimed. `i` is at most one past every slot
||| claimed before: a slot within the capacity is there already, and one
||| past it grows the table. The copy is bound inside the growing branch: a
||| `!` there is lifted out of `when` to the enclosing block, and would copy
||| the whole table at every claim.
export
claimSlot : HasIO io => Int -> Table a -> io ()
claimSlot i t = do
  arr <- readIORef t
  when (i >= Data.IOArray.max arr) $ do
    bigger <- newArrayCopy (grown (Data.IOArray.max arr) (i + 1)) arr
    writeIORef t bigger

||| The table with `x` in slot `i`, which it has claimed, so within the
||| capacity, where base's write always succeeds.
export
setSlot : HasIO io => Int -> a -> Table a -> io ()
setSlot i x t = ignore (writeArray !(readIORef t) i x)
