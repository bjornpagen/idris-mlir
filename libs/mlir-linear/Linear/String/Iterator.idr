-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Strings read front to back by a linear iterator, with the API of
||| upstream's contrib `Data.String.Iterator`, so that a program reads the
||| same over either. An iterator is a byte offset into the string's UTF-8,
||| at the start of a character or at the end. Only `withString` and
||| `uncons` make one, so each step reads one character, and a loop over
||| `uncons` keeps the iterator and the step's result off the heap. An
||| offset depends on what a string holds, not on where it is, so an
||| iterator of one string is an iterator of every string equal to it.
|||
||| Unlike the rest of this package it declares primitives of its own,
||| which idris-mlir gives their runtime meaning: over base's alone a
||| linear-time iterator would decode UTF-8 here, a second copy of the
||| runtime's strings, and one by character index takes quadratic time on
||| text that is not ASCII. Stock Idris's backends do not know them.
|||
||| A step moves past the character it read by the length of that
||| character's UTF-8, a function of the character alone: every character
||| is a Unicode scalar value and every string well-formed UTF-8, so that
||| is where the next one starts. The length is the byte length of the
||| character's own string, so on each host it means what that host's
||| strings say, and idris-mlir computes it without building the string. A
||| walk takes each character's first byte off the count of bytes left, a
||| successor by its type, and the rest after it, so a walk to the end takes
||| at most as many steps as the string has bytes, which is what ends
||| `foldl` and `unpack`.
module Linear.String.Iterator

import Control.WellFounded
import Data.Buffer
import public Data.List.Lazy
import Data.Nat

%default total

-- The character that starts at a byte offset, and the characters from an
-- offset on. Every offset has a meaning (idris_rt.h); this module passes
-- only the boundaries it made, below the byte length.
%extern prim__scalarAt : String -> Int -> Char
%extern prim__dropBytes : String -> Int -> String

||| The number of bytes of a character's UTF-8, 1 to 4: the byte length of
||| its own string. idris-mlir's registry lowers its calls to the runtime's
||| one rule for that length (`idr.str.scalar_bytes`); any other host runs
||| the body.
scalarBytes : Char -> Int
scalarBytes c = stringByteLength (cast c)

||| The bytes of a character's UTF-8 after its first.
continuation : Char -> Nat
continuation c = cast (scalarBytes c - 1)

||| What is left of a count once some of it is taken is no more than it.
0 minusLeft : (l, k : Nat) -> LTE (minus l k) l
minusLeft Z _ = LTEZero
minusLeft (S l) Z = reflexive
minusLeft (S l) (S k) = lteSuccRight (minusLeft l k)

||| An iterator over the string it is indexed by. The index exists at
||| compile time only.
export
data StringIterator : String -> Type where
  MkStringIterator : (offset : Int) -> StringIterator str

||| Runs `f` on an iterator at the start of `str`, used once, so that no
||| iterator outlives the call.
export
withString : (str : String) -> ((1 it : StringIterator str) -> a) -> a
withString str f = f (MkStringIterator 0)

||| Runs `f` on the rest of `str`, from the iterator on.
export
withIteratorString : (str : String) -> (1 it : StringIterator str) -> (f : (res : String) -> a) -> a
withIteratorString str (MkStringIterator offset) f = f (prim__dropBytes str offset)

||| The end, or a character and the iterator after it. The character is
||| unrestricted.
public export
data UnconsResult : String -> Type where
  EOF : UnconsResult str
  Character : (c : Char) -> (1 it : StringIterator str) -> UnconsResult str

||| The end, or the character at the iterator and the iterator after it.
export
uncons : (str : String) -> (1 it : StringIterator str) -> UnconsResult str
uncons str (MkStringIterator offset) =
  if offset < stringByteLength str
     then let c = prim__scalarAt str offset in
          Character c (MkStringIterator (offset + scalarBytes c))
     else EOF

||| The characters of a string folded from the left.
export
foldl : (accTy -> Char -> accTy) -> accTy -> String -> accTy
foldl op acc0 str = go acc0 bytes (wellFounded bytes)
  where
    end : Int
    end = stringByteLength str

    bytes : Nat
    bytes = cast end

    -- `left` bytes remain, so the character read starts `left` before the
    -- end, and fewer remain after it.
    go : accTy -> (left : Nat) -> (0 _ : Accessible LT left) -> accTy
    go acc Z _ = acc
    go acc (S l) (Access rec) =
      let c = prim__scalarAt str (end - cast (S l)) in
      go (op acc c) (minus l (continuation c)) (rec _ (LTESucc (minusLeft l (continuation c))))

||| The characters of a string, each read when the list reaches it.
export
unpack : String -> LazyList Char
unpack str = from bytes (wellFounded bytes)
  where
    end : Int
    end = stringByteLength str

    bytes : Nat
    bytes = cast end

    -- A delayed tail holds the bytes left, not an iterator: a suspension
    -- may never be forced, and an iterator must be used once. The
    -- character read starts `left` before the end, and fewer remain after
    -- it.
    from : (left : Nat) -> (0 _ : Accessible LT left) -> LazyList Char
    from Z _ = []
    from (S l) (Access rec) =
      let c = prim__scalarAt str (end - cast (S l)) in
      c :: from (minus l (continuation c)) (rec _ (LTESucc (minusLeft l (continuation c))))
