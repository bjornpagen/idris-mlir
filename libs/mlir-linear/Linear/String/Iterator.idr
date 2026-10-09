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
module Linear.String.Iterator

import Data.Buffer
import public Data.List.Lazy

%default total

-- The character that starts at a byte offset, the offset after it, and the
-- characters from an offset on. Every offset has a meaning (idris_rt.h);
-- this module passes only the boundaries it made, below the byte length.
%extern prim__scalarAt : String -> Int -> Char
%extern prim__scalarEnd : String -> Int -> Int
%extern prim__dropBytes : String -> Int -> String

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
     then Character (prim__scalarAt str offset) (MkStringIterator (prim__scalarEnd str offset))
     else EOF

||| The characters of a string folded from the left.
export
foldl : (accTy -> Char -> accTy) -> accTy -> String -> accTy
foldl op acc0 str = withString str (go acc0)
  where
    -- Each step moves the iterator strictly forward, toward the end.
    go : accTy -> (1 it : StringIterator str) -> accTy
    go acc it = case uncons str it of
      EOF => acc
      Character c next => go (op acc c) (assert_smaller it next)

||| The characters of a string, each read when the list reaches it.
export
unpack : String -> LazyList Char
unpack str = from 0
  where
    -- A delayed tail holds the next offset, not an iterator: a suspension
    -- may never be forced, and an iterator must be used once. Each step
    -- moves the offset strictly forward, toward the end.
    from : Int -> LazyList Char
    from offset =
      if offset < stringByteLength str
         then prim__scalarAt str offset :: from (assert_smaller offset (prim__scalarEnd str offset))
         else []
