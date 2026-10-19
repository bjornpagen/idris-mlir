-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
module Bits

import Data.Vect

%default total

-- partial, covering and assert_total in a comment are no finding
{- nor partial
   in a block -}
||| bitsOf d n: the low d bits of n, a recursion on the length of a Vect, which is structure, not fuel
export
bitsOf : (d : Nat) -> Int -> Vect d Bool
bitsOf Z _ = []
bitsOf (S d) n = (mod n 2 == 1) :: bitsOf d (div n 2)

name : String
name = "partial covering assert_total"

coveringSet : List Nat
coveringSet = []

partialSums : List Nat -> List Nat
partialSums = scanl (+) 0
