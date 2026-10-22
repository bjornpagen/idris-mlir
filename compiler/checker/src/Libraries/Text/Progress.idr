-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2026 Bjorn Pagen
||| How far a reader moves through its input, as evidence a loop over the
||| input ends by. A reader that consumes leaves fewer tokens, or
||| characters, than it was given; any other leaves no more. The evidence
||| is erased, so it costs nothing at run time: a loop over the input
||| recurses on what is left, which is accessible, and every assertion of
||| totality a loop would otherwise need is gone.
|||
||| The same evidence says where a reader stands against a bound: one that
||| has read since the parse stood at the bound leaves fewer tokens than
||| the bound, and any other no more, as if a reader had been given the
||| bound and had read or not.
module Libraries.Text.Progress

import Data.Nat

%default total

||| How many of its tokens or characters a reader leaves, `left`, against
||| how many it was given: fewer if it consumes, never more.
public export
Leaves : (consumes : Bool) -> (left, given : Nat) -> Type
Leaves True left given = Nat.LT left given
Leaves False left given = Nat.LTE left given

||| Whatever a reader consumes, it leaves no more than it was given.
export
0 noMore : (c : Bool) -> Leaves c left given -> Nat.LTE left given
noMore True fewer = lteSuccLeft fewer
noMore False fewer = fewer

||| A reader given no more than another was leaves no more than that one
||| was given.
export
0 within : (c : Bool) -> Leaves c left middle -> Nat.LTE middle given -> Leaves c left given
within True fewer le = transitive fewer le
within False fewer le = transitive fewer le

||| Two readers in sequence leave what the second leaves, fewer than the
||| first was given if either consumes.
export
0 inSequence : (c1, c2 : Bool) ->
               Leaves c1 middle given -> Leaves c2 left middle ->
               Leaves (c1 || c2) left given
inSequence True c2 first second = transitive (LTESucc (noMore c2 second)) first
inSequence False c2 first second = within c2 second first

||| An alternative leaves what the branch taken leaves, fewer than it was
||| given if both branches consume: here, the first.
export
0 firstOf : (c1, c2 : Bool) -> Leaves c1 left given -> Leaves (c1 && c2) left given
firstOf True True fewer = fewer
firstOf True False fewer = noMore True fewer
firstOf False _ fewer = fewer

||| An alternative leaves what the branch taken leaves: here, the second.
export
0 secondOf : (c1, c2 : Bool) -> Leaves c2 left given -> Leaves (c1 && c2) left given
secondOf True _ fewer = fewer
secondOf False c2 fewer = noMore c2 fewer

||| A reader that moves on from where it stood against a bound stands
||| below the bound as far as it did, at least.
export
0 further : (r : Bool) -> Nat.LTE left middle -> Leaves r middle bound -> Leaves r left bound
further True le fewer = transitive (LTESucc le) fewer
further False le noMoreThan = transitive le noMoreThan

||| Since a bound, a reader that had read or not, `r`, followed by one that
||| consumes `c`, has read if either did. The consuming reader comes first
||| in the disjunction, so once it consumes, the bound is known to be
||| passed whatever was known before.
export
0 readSince : (r, c : Bool) -> Leaves r middle bound -> Leaves c left middle ->
              Leaves (c || r) left bound
readSince r True before fewer = transitive fewer (noMore r before)
readSince r False before le = further r le before

||| A reader known to have read since a bound, by `d` or else by `r`,
||| stands where one known by `r` alone may stand.
export
0 earlier : (d, r : Bool) -> Leaves (d || r) left bound -> Leaves r left bound
earlier True True fewer = fewer
earlier True False fewer = lteSuccLeft fewer
earlier False r atMost = atMost
