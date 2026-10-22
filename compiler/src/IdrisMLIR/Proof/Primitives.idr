-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What one primitive computes from literals, against `Proof.Requests.grown`:
||| the step a site's builtin, read beside its call, grows a literal by
||| (`Proof.Bound.AtComputed`).
|||
||| The host bounds each primitive's result by its arguments' sizes
||| (`Idris.Host.boundOf`, `Idris.Host.computedWithin`), one bound per
||| operation; `grown` is chosen above every one of them at once. So each
||| bound, at arguments no larger than x, is below `grown x` less one
||| (`primitiveWithin`): a sum or a product of two sizes, a size times two to
||| a size, and two to four times a size are each below 2^(4x) * (x + 2), and
||| a fixed width's 2^64, a double's text and a cast's 2^1024 below 2^1024.
||| With the host's bound, what the table computes from constants no larger
||| than x is so (`computedGrown`). No power of two is ever computed: each is
||| compared through `Proof.Requests.powerMono`.
|||
||| Every proof is erased and total, and nothing here runs.
module IdrisMLIR.Proof.Primitives

import Core.TT
import Idris.Host

import IdrisMLIR.Proof.Requests

import Control.Relation
import Data.Fin
import Data.Nat
import Data.Vect

%default total

------------------------------------------------------------------------------
-- The room one computation has
------------------------------------------------------------------------------

-- What `grown x` is above, less one: its two parts.
0 Room : Nat -> Nat
Room x = power 2 (4 * x) * (x + 2) + power 2 1024

-- A number is below two to it.
0 belowItsPower : (x : Nat) -> Nat.LTE x (power 2 x)
belowItsPower Z = LTEZero
belowItsPower (S k) = plusLteMonotone (powerPositive k) (transitive (belowItsPower k) (lteAddRight (power 2 k)))

-- A number is below two to four times it.
0 belowPower : (x : Nat) -> Nat.LTE x (power 2 (4 * x))
belowPower x = transitive (belowItsPower x) (powerMono {a = x} {b = 4 * x} (lteAddRight {m = 3 * x} x))

0 oneBelowPlusTwo : (x : Nat) -> Nat.LTE 1 (x + 2)
oneBelowPlusTwo x = rewrite plusCommutative x 2 in LTESucc LTEZero

0 twoBelowPlusTwo : (x : Nat) -> Nat.LTE 2 (x + 2)
twoBelowPlusTwo x = rewrite plusCommutative x 2 in LTESucc (LTESucc LTEZero)

0 succBelowPlusTwo : (x : Nat) -> Nat.LTE (S x) (x + 2)
succBelowPlusTwo x = rewrite plusCommutative x 2 in LTESucc (lteSuccRight reflexive)

-- A product with a factor of at least one is no smaller than the other, on
-- either side.
0 timesRight : (c : Nat) -> Nat.LTE 1 k -> Nat.LTE c (c * k)
timesRight c one = replace {p = \z => Nat.LTE z (c * k)} (multOneRightNeutral c) (timesMono {a = c} {b = c} {c = 1} {d = k} reflexive one)

0 timesLeft : (c : Nat) -> Nat.LTE 1 k -> Nat.LTE c (k * c)
timesLeft c one = replace {p = \z => Nat.LTE z (k * c)} (plusZeroRightNeutral c) (timesMono {a = 1} {b = k} {c = c} {d = c} one reflexive)

-- Twice a number, as a product.
0 twice : (x : Nat) -> x * 2 = x + x
twice x = trans (multCommutative x 2) (cong (x +) (plusZeroRightNeutral x))

-- The bounds below the first part, 2^(4x) * (x + 2).

0 powerBelow : (x : Nat) -> Nat.LTE (power 2 (4 * x)) (power 2 (4 * x) * (x + 2))
powerBelow x = timesRight (power 2 (4 * x)) (oneBelowPlusTwo x)

0 sizeBelow : (x : Nat) -> Nat.LTE x (power 2 (4 * x) * (x + 2))
sizeBelow x = transitive (belowPower x) (powerBelow x)

0 succBelow : (x : Nat) -> Nat.LTE (S x) (power 2 (4 * x) * (x + 2))
succBelow x = transitive (succBelowPlusTwo x) (timesLeft (x + 2) (powerPositive (4 * x)))

0 sumBelow : (x : Nat) -> Nat.LTE (x + x) (power 2 (4 * x) * (x + 2))
sumBelow x = replace {p = \z => Nat.LTE z (power 2 (4 * x) * (x + 2))} (twice x) (timesMono (belowPower x) (twoBelowPlusTwo x))

0 productBelow : (x : Nat) -> Nat.LTE (x * x) (power 2 (4 * x) * (x + 2))
productBelow x = timesMono (belowPower x) (lteAddRight {m = 2} x)

0 shiftBelow : (x : Nat) -> Nat.LTE (x * power 2 x) (power 2 (4 * x) * (x + 2))
shiftBelow x =
  rewrite multCommutative x (power 2 x) in
    timesMono (powerMono {a = x} {b = 4 * x} (lteAddRight {m = 3 * x} x)) (lteAddRight {m = 2} x)

-- The bounds below the second part, 2^1024.

0 widthBelow : Nat.LTE (power 2 64) (power 2 1024)
widthBelow = powerMono {a = 64} {b = 1024} (lteAddRight {m = 960} 64)

0 textBelow : Nat.LTE 49 (power 2 1024)
textBelow = transitive (belowItsPower 49) (powerMono {a = 49} {b = 1024} (lteAddRight {m = 975} 49))

-- Each part within the room.

0 inFirst : {x : Nat} -> Nat.LTE e (power 2 (4 * x) * (x + 2)) -> Nat.LTE e (Room x)
inFirst le = transitive le (lteAddRight (power 2 (4 * x) * (x + 2)))

0 inSecond : {x : Nat} -> Nat.LTE e (power 2 1024) -> Nat.LTE e (Room x)
inSecond le =
  transitive le (replace {p = Nat.LTE (power 2 1024)} (plusCommutative (power 2 1024) (power 2 (4 * x) * (x + 2)))
                         (lteAddRight (power 2 1024)))

-- A bound below the first part, wrapped to a fixed width.
0 wrapped : {x : Nat} -> Nat.LTE e (power 2 (4 * x) * (x + 2)) -> Nat.LTE (e + power 2 64) (Room x)
wrapped le = plusLteMonotone le widthBelow

------------------------------------------------------------------------------
-- Each primitive
------------------------------------------------------------------------------

-- A cast's bound, by the type it casts to: an integer's two powers, a
-- string's one more than its argument, a double's text, nothing for a
-- character or the world, and any fixed width its argument wrapped.
0 castWithin : (from, to : PrimType) -> (x : Nat) -> Nat.LTE (resultBound (Cast from to) [x]) (Room x)
castWithin from IntegerType x = plusLteMonotone (powerBelow x) reflexive
castWithin from StringType x = inFirst {x} (rewrite plusCommutative x 1 in succBelow x)
castWithin from CharType x = LTEZero
castWithin from DoubleType x = inSecond textBelow
castWithin from WorldType x = LTEZero
castWithin from IntType x = wrapped {x} (sizeBelow x)
castWithin from Int8Type x = wrapped {x} (sizeBelow x)
castWithin from Int16Type x = wrapped {x} (sizeBelow x)
castWithin from Int32Type x = wrapped {x} (sizeBelow x)
castWithin from Int64Type x = wrapped {x} (sizeBelow x)
castWithin from Bits8Type x = wrapped {x} (sizeBelow x)
castWithin from Bits16Type x = wrapped {x} (sizeBelow x)
castWithin from Bits32Type x = wrapped {x} (sizeBelow x)
castWithin from Bits64Type x = wrapped {x} (sizeBelow x)

-- Each primitive's bound at arguments of size x, within the room.
0 boundWithin : (op : PrimFn arity) -> (x : Nat) -> Nat.LTE (resultBound op (replicate arity x)) (Room x)
boundWithin (Add _) x = wrapped {x} (sumBelow x)
boundWithin (Sub _) x = wrapped {x} (sumBelow x)
boundWithin (Mul _) x = wrapped {x} (productBelow x)
boundWithin (Div _) x = wrapped {x} (sizeBelow x)
boundWithin (Mod _) x = wrapped {x} (sizeBelow x)
boundWithin (Neg _) x = wrapped {x} (sizeBelow x)
boundWithin (ShiftL _) x = wrapped {x} (shiftBelow x)
boundWithin (ShiftR _) x = wrapped {x} (shiftBelow x)
boundWithin (BAnd _) x = wrapped {x} (sumBelow x)
boundWithin (BOr _) x = wrapped {x} (sumBelow x)
boundWithin (BXOr _) x = wrapped {x} (sumBelow x)
boundWithin (Primitive.LT _) x = inSecond {x} (powerPositive 1024)
boundWithin (Primitive.LTE _) x = inSecond {x} (powerPositive 1024)
boundWithin (Primitive.EQ _) x = inSecond {x} (powerPositive 1024)
boundWithin (Primitive.GTE _) x = inSecond {x} (powerPositive 1024)
boundWithin (Primitive.GT _) x = inSecond {x} (powerPositive 1024)
boundWithin StrLength x = inFirst {x} (sizeBelow x)
boundWithin StrHead x = LTEZero
boundWithin StrTail x = inFirst {x} (sizeBelow x)
boundWithin StrIndex x = LTEZero
boundWithin StrCons x = inFirst {x} (succBelow x)
boundWithin StrAppend x = inFirst {x} (sumBelow x)
boundWithin StrReverse x = inFirst {x} (sizeBelow x)
boundWithin StrSubstr x = inFirst {x} (sizeBelow x)
boundWithin DoubleExp x = inSecond textBelow
boundWithin DoubleLog x = inSecond textBelow
boundWithin DoublePow x = inSecond textBelow
boundWithin DoubleSin x = inSecond textBelow
boundWithin DoubleCos x = inSecond textBelow
boundWithin DoubleTan x = inSecond textBelow
boundWithin DoubleASin x = inSecond textBelow
boundWithin DoubleACos x = inSecond textBelow
boundWithin DoubleATan x = inSecond textBelow
boundWithin DoubleSqrt x = inSecond textBelow
boundWithin DoubleFloor x = inSecond textBelow
boundWithin DoubleCeiling x = inSecond textBelow
boundWithin (Cast from to) x = castWithin from to x
boundWithin BelieveMe x = inFirst {x} (sizeBelow x)
boundWithin Crash x = LTEZero

||| What one primitive computes from arguments of size at most x, by the
||| host's bound, is below `grown x`: one computation's growth.
export
0 primitiveWithin : (op : PrimFn arity) -> (x : Nat) -> Nat.LTE (S (resultBound op (replicate arity x))) (grown x)
primitiveWithin op x = LTESucc (boundWithin op x)

||| What the host's table computes from constants of size at most x is
||| below `grown x`: within the primitive's bound at their sizes
||| (`Idris.Host.computedWithin`), which grows with them
||| (`Idris.Host.resultBoundMonotone`), each at most x.
export
0 computedGrown : {arity : Nat} -> {x : Nat} -> (op : PrimFn arity) -> (cs : Vect arity Constant) -> tableOf op cs = Just c ->
                  SizesWithin (map Host.constantSize cs) (replicate arity x) -> Nat.LTE (S (constantSize c)) (grown x)
computedGrown op cs computed within =
  transitive (LTESucc (transitive (computedWithin op cs computed) (resultBoundMonotone op within))) (primitiveWithin op x)
