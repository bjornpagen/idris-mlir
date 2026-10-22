-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Libraries.Data.NatSet

import Data.Bits

%default total

||| A finite set of naturals, as the bits of 64-bit words, the lowest
||| positions first: `64 * k + b` is in the set when bit `b` of word `k` is
||| set. A word has no sign, so no set is negative, and every walk over a
||| set's positions is a walk over its words, each of a fixed size, where an
||| integer would be halved until it reached zero, which a negative one never
||| does. The last word is never zero, so the empty set is `[]` and each set
||| has one representation: every operation builds its words through `word`.
export
NatSet : Type
NatSet = List Bits64

-- A word before the words above it, dropped where it is zero and nothing is
-- above it, so that the last word is never zero.
word : Bits64 -> List Bits64 -> List Bits64
word 0 [] = []
word w ws = w :: ws

-- A position as the words below its own and its bit in that word: the
-- position's binary digits above the sixth count the words, the six below
-- name the bit.
place : Nat -> (Nat, Bits64)
place n = let i = natToInteger n in
              (integerToNat (shiftR i 6), cast (i .&. 63))

-- The word with only bit `b` set, for `b` below 64.
bitAt : Bits64 -> Bits64
bitAt b = prim__shl_Bits64 1 b

-- The lowest word, zero where there is none.
lowest : List Bits64 -> Bits64
lowest [] = 0
lowest (w :: _) = w

-- `n` copies of a word below the words given.
copies : Nat -> Bits64 -> List Bits64 -> List Bits64
copies Z _ ws = ws
copies (S k) w ws = w :: copies k w ws

export %inline
empty : NatSet
empty = []

export
elem : Nat -> NatSet -> Bool
elem n ns = let (q, b) = place n in go q (bitAt b) ns
  where
    go : Nat -> Bits64 -> List Bits64 -> Bool
    go _ _ [] = False
    go Z m (w :: _) = (w .&. m) /= 0
    go (S q) m (_ :: ws) = go q m ws

export
drop : NatSet -> List a -> List a
drop [] xs = xs
drop ds xs = go 0 xs
  where
    go : Nat -> List a -> List a
    go _ [] = []
    go i (x :: xs)
        = if NatSet.elem i ds
             then go (S i) xs
             else x :: go (S i) xs

-- The elements at the set's positions, read directly: the complement a
-- `drop` would need is no finite set.
export
take : NatSet -> List a -> List a
take ds = go 0
  where
    go : Nat -> List a -> List a
    go _ [] = []
    go i (x :: xs)
        = if NatSet.elem i ds
             then x :: go (S i) xs
             else go (S i) xs

export
isEmpty : NatSet -> Bool
isEmpty [] = True
isEmpty _ = False

export
size : NatSet -> Nat
size = foldl (\n, w => n + popCount w) 0

-- The bit is set, so the word it is or-ed into is not zero, and a set's
-- last word stays non-zero; zero words are added below it where the set
-- has none.
export
insert : Nat -> NatSet -> NatSet
insert n ns = let (q, b) = place n in go q (bitAt b) ns
  where
    go : Nat -> Bits64 -> List Bits64 -> List Bits64
    go Z m [] = [m]
    go Z m (w :: ws) = (w .|. m) :: ws
    go (S q) m [] = 0 :: go q m []
    go (S q) m (w :: ws) = w :: go q m ws

export
delete : Nat -> NatSet -> NatSet
delete n ns = let (q, b) = place n in go q (complement (bitAt b)) ns
  where
    go : Nat -> Bits64 -> List Bits64 -> List Bits64
    go _ _ [] = []
    go Z m (w :: ws) = word (w .&. m) ws
    go (S q) m (w :: ws) = word w (go q m ws)

-- A word is read a bit at a time, at most its 64, and no further once the
-- bits left are zero.
export
toList : NatSet -> List Nat
toList = go 0
  where
    bits : (left : Nat) -> (pos : Nat) -> Bits64 -> List Nat -> List Nat
    bits Z _ _ rest = rest
    bits (S k) pos w rest
        = if w == 0
             then rest
             else let more = bits k (S pos) (prim__shr_Bits64 w 1) rest in
                      if (w .&. 1) == 0 then more else pos :: more

    go : Nat -> List Bits64 -> List Nat
    go _ [] = []
    go pos (w :: ws) = bits 64 pos w (go (pos + 64) ws)

-- Within this module a set is a list of words, which the Prelude's
-- `toList` would print, so the positions are named in full.
export
Show NatSet where
  show ns = show (NatSet.toList ns)

export
partition : NatSet -> List a -> (List a , List a)
partition ps = go 0
  where
    go : Nat -> List a -> (List a , List a)
    go i [] = ([], [])
    go i (x :: xs)
      = let xys = go (S i) xs in
        if NatSet.elem i ps
           then mapFst (x ::) xys
           else mapSnd (x ::) xys

export
intersection : NatSet -> NatSet -> NatSet
intersection (x :: xs) (y :: ys) = word (x .&. y) (intersection xs ys)
intersection _ _ = []

-- The longer set's last word is its own, or both last words are or-ed, so
-- the last word stays non-zero.
export
union : NatSet -> NatSet -> NatSet
union [] ys = ys
union xs [] = xs
union (x :: xs) (y :: ys) = (x .|. y) :: union xs ys

export
intersectAll : List NatSet -> NatSet
intersectAll [] = []
intersectAll (x::xs) = foldr intersection x xs

export
allLessThan : Nat -> NatSet
allLessThan n = let (q, b) = place n in copies q oneBits (word (bitAt b - 1) [])

0 allLessThanSpecEmpty : NatSet.toList (allLessThan 0) === []
allLessThanSpecEmpty = Refl

0 allLessThanSpecNonEmpty : NatSet.toList (allLessThan 10) === [0..9]
allLessThanSpecNonEmpty = Refl

export
overwrite : a -> NatSet -> List a -> List a
overwrite c [] xs = xs
overwrite c ds xs = go 0 xs
  where
    go : Nat -> List a -> List a
    go _ [] = []
    go i (x :: xs)
        = if NatSet.elem i ds
             then c :: go (S i) xs
             else x :: go (S i) xs

-- The words shifted down by `b` bits, `b` from 1 to 63, each word taking the
-- low bits of the one above it.
down : Bits64 -> List Bits64 -> List Bits64
down b [] = []
down b (w :: ws)
    = word (prim__shr_Bits64 w b .|. prim__shl_Bits64 (lowest ws) (64 - b)) (down b ws)

-- The words shifted up by `b` bits, `b` from 1 to 63, the bits leaving each
-- word carried into the one above it.
up : Bits64 -> (carry : Bits64) -> List Bits64 -> List Bits64
up b c [] = word c []
up b c (w :: ws) = word (prim__shl_Bits64 w b .|. c) (up b (prim__shr_Bits64 w (64 - b)) ws)

-- Pop the zero (whether or not in the set) and shift all the
-- other positions by -1 (useful when coming back from under
-- a binder)
export %inline
popZ : NatSet -> NatSet
popZ = down 1

-- Pop the positions below `n` and shift the others by `-n`: whole words go,
-- then the bits left below 64 are shifted out.
export
popNs : Nat -> NatSet -> NatSet
popNs n ns = let (q, b) = place n in bits b (whole q ns)
  where
    whole : Nat -> List Bits64 -> List Bits64
    whole Z ws = ws
    whole (S _) [] = []
    whole (S q) (_ :: ws) = whole q ws

    bits : Bits64 -> List Bits64 -> List Bits64
    bits 0 ws = ws
    bits b ws = down b ws

-- Add a 'new' Zero (not in the set) and shift all the
-- other positions by +1 (useful when going under a binder)
export %inline
addZ : NatSet -> NatSet
addZ = up 1 0

-- Add `n` new positions below the set's (none in the set) and shift the
-- others by `+n`: the bits below 64 are shifted in, then whole zero words
-- go below, none where the set is empty.
export
addNs : Nat -> NatSet -> NatSet
addNs n ns = let (q, b) = place n in whole q (bits b ns)
  where
    bits : Bits64 -> List Bits64 -> List Bits64
    bits 0 ws = ws
    bits b ws = up b 0 ws

    whole : Nat -> List Bits64 -> List Bits64
    whole _ [] = []
    whole q ws = copies q 0 ws

||| The set's words, lowest first, as a TTC writes them.
export
toWords : NatSet -> List Bits64
toWords ns = ns

||| The set whose words these are, lowest first: a zero last word is dropped,
||| so any words a TTC holds read as a set.
export
fromWords : List Bits64 -> NatSet
fromWords = foldr word []
