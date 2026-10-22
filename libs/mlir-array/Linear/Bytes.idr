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
||| the region `r`: the linear array's own slots, frozen in place, and how
||| many there are. A read gives the same handle back; the handle itself is
||| used once, and the one way to end it is to give it back to the
||| `withBytes` that made it.
export
data Bytes : (0 r : Type) -> (0 n : Nat) -> Type where
  Lent : (n : Nat) -> (1 bytes : Frozen r [<n] Bits8) -> Bytes r n

||| The handle's frozen bytes, given back with what `k` returned.
returned : (1 _ : Res a (const (Bytes r n))) -> Res a (const (Frozen r [<n] Bits8))
returned (x # Lent _ bytes) = x # bytes

||| What `k` returns, given the buffer's bytes frozen in place behind a
||| handle that holds their count, and the buffer back, thawed in place.
lent : (1 k : {0 r : Type} -> (1 _ : Bytes r n) -> Res a (const (Bytes r n))) ->
       (1 _ : Res (Extents [<n]) (const (LArray [<n] Bits8))) -> Res a (const (LArray [<n] Bits8))
lent k ([<m] # buf) = LArray.withFrozen buf (\bytes => returned (k (Lent m bytes)))

||| `k` given the buffer's bytes behind a handle of a fresh region, and
||| `next` given what `k` returns and the buffer back, with the bytes as `k`
||| saw them. The buffer is frozen in place and thawed in place: reusing a
||| buffer for the next input copies nothing. `k`'s result cannot name the
||| region, so it holds no view of the bytes.
export
withBytes : (1 buf : LArray [<n] Bits8) ->
            (1 k : {0 r : Type} -> (1 _ : Bytes r n) -> Res a (const (Bytes r n))) ->
            (1 next : a -> (1 _ : LArray [<n] Bits8) -> !* b) -> !* b
withBytes buf k next = let x # buf = lent k (LArray.shape buf) in next x buf

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
peek (Lent n bytes) at = case choose (at < n) of
  Left more =>
    let b # bytes = Frozen.read bytes [<natToFinLt at @{more}] in
    Byte (Lent n bytes) b (ltOpReflectsLT at n more)
  Right _ => End (Lent n bytes)

||| A view of a handle's bytes, from `start` up to `end`, empty when `end`
||| is not after `start`: two offsets and nothing they reach.
public export
record Span (0 r : Type) (0 n : Nat) where
  constructor MkSpan
  start : Nat
  end : Nat
  0 within : LTE end n

||| The bytes from `s` up to `e`, onto `acc`, the last read first; the
||| handle given back.
collect : (1 _ : Frozen r [<n] Bits8) -> (s, e : Nat) -> (0 _ : LTE e n) -> List Bits8 ->
          Res (List Bits8) (const (Frozen r [<n] Bits8))
collect bytes s Z _ acc = acc # bytes
collect bytes s (S e) fits acc = case choose (s < S e) of
  Left _ =>
    let b # bytes = Frozen.read bytes [<natToFinLT e {prf = fits}] in
    collect bytes s e (lteSuccLeft fits) (b :: acc)
  Right _ => acc # bytes

||| A span's bytes, copied out of the handle, for a value that must outlive
||| it; the handle given back.
export
copy : (1 _ : Bytes r n) -> Span r n -> Res (List Bits8) (const (Bytes r n))
copy (Lent n bytes) sp =
  let got # bytes = collect bytes sp.start sp.end sp.within [] in
  got # Lent n bytes

||| Whether the bytes from `at` up to `e` are exactly `want`; the handle
||| given back.
spells : (1 _ : Frozen r [<n] Bits8) -> (at, e : Nat) -> (0 _ : LTE e n) -> List Bits8 ->
         Res Bool (const (Frozen r [<n] Bits8))
spells bytes at e fits [] = (at == e) # bytes
spells bytes at e fits (c :: cs) = case choose (at < e) of
  Left inside =>
    let b # bytes = Frozen.read bytes [<natToFinLT at {prf = transitive (ltOpReflectsLT at e inside) fits}] in
    if b == c then spells bytes (S at) e fits cs else False # bytes
  Right _ => False # bytes

||| Whether a span holds exactly these bytes, with no copy; the handle given
||| back.
export
matches : (1 _ : Bytes r n) -> Span r n -> List Bits8 -> Res Bool (const (Bytes r n))
matches (Lent n bytes) sp want =
  let same # bytes = spells bytes sp.start sp.end sp.within want in
  same # Lent n bytes
