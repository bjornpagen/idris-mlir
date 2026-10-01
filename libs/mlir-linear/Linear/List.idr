||| Linear lists: a list whose spine and elements are used exactly once,
||| as upstream's `Data.Linear.LList` has them, so that a program written
||| over either reads the same. An element used freely is wrapped in `!*`.
module Linear.List

import Linear.Notation

%default total

public export
data LList : Type -> Type where
  Nil : LList a
  (::) : a -@ LList a -@ LList a

%name LList xs, ys, zs, ws

||| The length, with the list consumed; its elements are unrestricted.
export
length : LList (!* a) -@ Nat
length xs = go 0 xs
  where
    go : Nat -> LList (!* a) -@ Nat
    go acc [] = acc
    go acc (MkBang _ :: ys) = go (S acc) ys

||| The list reversed onto an accumulator, in place.
export
reverseOnto : LList a -@ LList a -@ LList a
reverseOnto acc [] = acc
reverseOnto acc (x :: xs) = reverseOnto (x :: acc) xs

||| The list reversed, in place.
export
reverse : LList a -@ LList a
reverse xs = reverseOnto [] xs
