-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2026 Bjorn Pagen
||| A trail: entries written one after another, the newest last. Each cell
||| is held once, so a pass that writes a trail writes it in place and
||| counts nothing; and the trail knows how many entries it has, so what
||| was written after a point is cut back to that point when it is undone,
||| at the cost of what is undone, never of a copy. A parser's warnings and
||| a lexer's tokens are trails, and so may a parse's own state be.
module Libraries.Text.Trail

%default total

||| A state given back by a step that read it, held once, and what the step
||| gave, held freely.
public export
data Stepped : Type -> Type -> Type where
  MkStepped : (1 st : state) -> (val : a) -> Stepped state a

-- `n` entries, the newest last. The count is in the type, so cutting back
-- to fewer of them is a walk down this many cells, with no case of a
-- trail shorter than its count.
data Written : Nat -> Type -> Type where
  Blank : Written Z a
  Wrote : (1 earlier : Written n a) -> (entry : a) -> Written (S n) a

||| Entries written one after another, with how many there are.
export
data Trail : Type -> Type where
  MkTrail : (written : Nat) -> (1 entries : Written written a) -> Trail a

||| Nothing written.
export
blank : Trail a
blank = MkTrail Z Blank

||| The trail with one more entry, the newest.
export
write : a -> (1 trail : Trail a) -> Trail a
write x (MkTrail n entries) = MkTrail (S n) (Wrote entries x)

||| How many entries the trail holds, the trail given back: where it stands,
||| to cut it back to.
export
measured : (1 trail : Trail a) -> Stepped (Trail a) Nat
measured (MkTrail n entries) = MkStepped (MkTrail n entries) n

-- The first `keep` of `n` entries, the rest dropped newest first. A trail
-- only grows between the measure and the cut, so `keep` is never more than
-- `n`; were it more, every entry would be kept, which is what keeping the
-- first `keep` means.
keepFirst : (keep : Nat) -> (n : Nat) -> (1 entries : Written n a) -> Trail a
keepFirst keep Z Blank = MkTrail Z Blank
keepFirst keep (S k) (Wrote earlier x)
    = if keep < S k
         then keepFirst keep k earlier
         else MkTrail (S k) (Wrote earlier x)

||| The trail cut back to its first `keep` entries: what was written after
||| them is undone.
export
cutTo : (keep : Nat) -> (1 trail : Trail a) -> Trail a
cutTo keep (MkTrail n entries) = keepFirst keep n entries

-- The entries before `acc`, oldest first.
oldestFirst : (1 entries : Written n a) -> List a -> List a
oldestFirst Blank acc = acc
oldestFirst (Wrote earlier x) acc = oldestFirst earlier (x :: acc)

||| The entries, oldest first.
export
contents : (1 trail : Trail a) -> List a
contents (MkTrail n entries) = oldestFirst entries []
