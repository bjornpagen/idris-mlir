-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Immutable bytes behind a quantity-1 handle: a linear byte array frozen
||| in place, read while nothing writes it, and thawed back in place when
||| the handle is given back.
|||
||| A read of the handle orders with nothing: the bytes do not change while
||| the handle lives, so a read is a value of the handle and an offset, two
||| reads at one offset are one, and a read nothing uses is no read. Only
||| giving the handle back, which ends the bytes' immutable life, is ordered.
|||
||| A view of the bytes is a `Span`: two offsets, holding no reference, so a
||| frame may keep one past its last use. Every span carries the region of
||| the handle it was taken from, a type fresh for each `withBytes`, so no
||| span leaves the continuation that holds the handle, and the buffer is
||| thawed only after every view of it has ended.
module Linear.Bytes

import Array
import Data.Buffer
import Data.Nat
import Data.So
import Linear.Notation

%default total

------------------------------------------------------------------------------
-- The handle
------------------------------------------------------------------------------

||| A quantity-1 handle to `n` bytes that nothing writes while it lives, in
||| the region `r`. The array inside is unrestricted, so a read borrows it
||| and gives the same handle back; the handle itself is used once, and the
||| one way to end it is to give it back to the `withBytes` that made it.
export
data Bytes : (0 r : Type) -> (0 n : Nat) -> Type where
  Frozen : (n : Nat) -> (bytes : Array [<n] Bits8) -> Bytes r n

||| The linear array's bytes as a handle: frozen, so no copy.
frozenAs : (m : Nat) -> (1 _ : !* (Array [<m] Bits8)) -> Bytes r m
frozenAs m (MkBang bytes) = Frozen m bytes

freezeIn : (1 _ : Res (Extents [<n]) (const (LArray [<n] Bits8))) -> Bytes r n
freezeIn ([<m] # buf) = frozenAs m (LArray.freeze buf)

||| The handle given back, its bytes thawed into a linear array for `next`.
||| This is the bytes' last use, and no view of them is left, so the thaw
||| takes the same memory and copies nothing.
thawBack : (1 _ : a -> (1 _ : LArray [<n] Bits8) -> !* b) -> (1 _ : Res a (const (Bytes r n))) -> !* b
thawBack next (x # Frozen m bytes) = LArray.thaw bytes (next x)

||| `k` given the buffer's bytes behind a handle of a fresh region, and
||| `next` given what `k` returns and the buffer back, with the bytes as `k`
||| saw them. The buffer is frozen in place and thawed in place: reusing a
||| buffer for the next input copies nothing. `k`'s result cannot name the
||| region, so it holds no view of the bytes.
export
withBytes : (1 buf : LArray [<n] Bits8) ->
            (1 k : {0 r : Type} -> (1 _ : Bytes r n) -> Res a (const (Bytes r n))) ->
            (1 next : a -> (1 _ : LArray [<n] Bits8) -> !* b) -> !* b
withBytes buf k next = thawBack next (k {r = ()} (freezeIn (LArray.shape buf)))

||| A buffer's byte at an index, read in the world's order.
byteOf : Buffer -> Index [<n] -> IO Bits8
byteOf buf [<i] = getBits8 buf (cast (finToNat i))

||| The first `n` bytes of a buffer, read once from the world, so that what
||| parses them after is pure; thawed, they are the buffer `withBytes`
||| freezes.
export
bufferBytes : Buffer -> (n : Nat) -> IO (Array [<n] Bits8)
bufferBytes buf n = tabulateIO [<n] (byteOf buf)

------------------------------------------------------------------------------
-- Reading
------------------------------------------------------------------------------

||| What a handle holds at an offset: the end, or a byte, which leaves room
||| for the offset after it. The handle comes back either way.
public export
data Peeked : (0 r : Type) -> (0 n : Nat) -> (0 at : Nat) -> Type where
  End : (1 input : Bytes r n) -> Peeked r n at
  Byte : (1 input : Bytes r n) -> (b : Bits8) -> (0 more : LT at n) -> Peeked r n at

||| The byte at an offset, or the end: one comparison with the length, the
||| program's own, its evidence erased.
export
peek : (1 _ : Bytes r n) -> (at : Nat) -> Peeked r n at
peek (Frozen n bytes) at = case choose (at < n) of
  Left more => Byte (Frozen n bytes) (bytes !! [<natToFinLt at @{more}]) (ltOpReflectsLT at n more)
  Right _ => End (Frozen n bytes)

||| A view of a handle's bytes, from `start` up to `end`, empty when `end`
||| is not after `start`: two offsets and nothing they reach.
public export
record Span (0 r : Type) (0 n : Nat) where
  constructor MkSpan
  start : Nat
  end : Nat
  0 within : LTE end n

||| The bytes from `s` up to `e`, onto `acc`, the last read first.
collect : Array [<n] Bits8 -> (s, e : Nat) -> (0 _ : LTE e n) -> List Bits8 -> List Bits8
collect bytes s Z _ acc = acc
collect bytes s (S e) fits acc = case choose (s < S e) of
  Left _ => collect bytes s e (lteSuccLeft fits) ((bytes !! [<natToFinLT e {prf = fits}]) :: acc)
  Right _ => acc

||| A span's bytes, copied out of the handle, for a value that must outlive
||| it; the handle given back.
export
copy : (1 _ : Bytes r n) -> Span r n -> Res (List Bits8) (const (Bytes r n))
copy (Frozen n bytes) sp = collect bytes sp.start sp.end sp.within [] # Frozen n bytes

||| Whether the bytes from `at` up to `e` are exactly `want`.
spells : Array [<n] Bits8 -> (at, e : Nat) -> (0 _ : LTE e n) -> List Bits8 -> Bool
spells bytes at e fits [] = at == e
spells bytes at e fits (c :: cs) = case choose (at < e) of
  Left inside =>
    bytes !! [<natToFinLT at {prf = transitive (ltOpReflectsLT at e inside) fits}] == c
      && spells bytes (S at) e fits cs
  Right _ => False

||| Whether a span holds exactly these bytes, with no copy; the handle given
||| back.
export
matches : (1 _ : Bytes r n) -> Span r n -> List Bits8 -> Res Bool (const (Bytes r n))
matches (Frozen n bytes) sp want = spells bytes sp.start sp.end sp.within want # Frozen n bytes
