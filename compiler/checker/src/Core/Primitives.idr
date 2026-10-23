-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Core.Primitives

import Core.Primitives.Host
import Core.TT
import Core.Value

import Data.Vect

%default covering

-- A primitive the evaluator computes is the primitive itself, called by
-- its name: what `prim__add_Int` means while the compiler runs is what the
-- runtime that runs the compiler gives it, not an Idris program written to
-- agree with it. So each operation below applies `prim__...` of the same
-- name to the constants, and decides only whether it applies: it applies
-- where every host computes the runtime's one meaning, and stays applied
-- elsewhere. So a partial primitive (division by zero, the head of an
-- empty string), a cast of an infinity, a NaN or a String, whose value on
-- Chez is not the runtime's, a Double's text and a Double's function of
-- the C library, which agree with the runtime only as far as two printers
-- or two libraries happen to, a Double's operation whose result is a NaN,
-- whose bits are the target's, and a cast the compiler has never folded
-- stay applied.

||| A primitive: its name, its operation, its type and its totality.
public export
record Prim where
  constructor MkPrim
  {arity : Nat}
  called : Known
  fn : PrimFn arity
  type : ClosedTerm
  totality : Totality

binOp : (Constant -> Constant -> Maybe Constant) ->
        Vect 2 (NF vars) -> Maybe (NF vars)
binOp fn [NPrimVal fc x, NPrimVal _ y]
    = map (NPrimVal fc) (fn x y)
binOp _ _ = Nothing

unaryOp : (Constant -> Maybe Constant) ->
          Vect 1 (NF vars) -> Maybe (NF vars)
unaryOp fn [NPrimVal fc x]
    = map (NPrimVal fc) (fn x)
unaryOp _ _ = Nothing

-- The runtime casts a finite Double to an integer by truncating it toward
-- zero (an Int wrapped modulo 2^64), which the primitive computes on either
-- host. Of an infinity or NaN the cast crashes the program ("cast of a
-- non-finite Double"), and on Chez it would raise in `inexact->exact` and
-- crash the compiler, so it has no value here: it stays applied, and the
-- program's run reaches the runtime's meaning. A Double is finite exactly
-- when it lies strictly between the two infinities, by IEEE 754's
-- comparisons, which both hosts' Doubles have; NaN, ordered with no
-- Double, lies between none.
finite : Double -> Maybe Double
finite x = if negate infinity < x && x < infinity then Just x else Nothing
  where
    infinity : Double
    infinity = 1.0 / 0.0

-- A Double's operation folds to its result where the result is a number,
-- an infinity among them, which IEEE 754 fixes to one double. Where the
-- result is a NaN, IEEE 754 fixes only that it is one, not its sign or its
-- payload: x86's default NaN has its sign bit set and arm64's has not, and
-- LLVM leaves payloads unspecified. So a NaN has no one value to fold to,
-- and the operation stays applied: the program's run reaches its target's
-- NaN. No constant is then a NaN (no literal is one, and a cast from an
-- integer gives a number or an infinity), which is what makes
-- `sameDouble`, by which definitional equality compares two doubles,
-- compare their bits. A NaN is the one Double that IEEE's `==` finds
-- unequal to itself.
number : Double -> Maybe Constant
number x = if x == x then Just (Db x) else Nothing

-- A Double's text stays applied, finite or not. The runtime writes a
-- finite Double in its shortest digits, laid out as the stock Chez backend
-- lays them out, so Chez's `number->string` gives the runtime's text only
-- because the runtime was written to match it: two printers that agree,
-- not one meaning. An infinity or NaN they write differently (`inf`,
-- where Chez writes `+inf.0`). The program's run writes the runtime's.
castString : Vect 1 (NF vars) -> Maybe (NF vars)
castString [NPrimVal fc (I i)] = Just (NPrimVal fc (Str (prim__cast_IntString i)))
castString [NPrimVal fc (I8 i)] = Just (NPrimVal fc (Str (prim__cast_Int8String i)))
castString [NPrimVal fc (I16 i)] = Just (NPrimVal fc (Str (prim__cast_Int16String i)))
castString [NPrimVal fc (I32 i)] = Just (NPrimVal fc (Str (prim__cast_Int32String i)))
castString [NPrimVal fc (I64 i)] = Just (NPrimVal fc (Str (prim__cast_Int64String i)))
castString [NPrimVal fc (BI i)] = Just (NPrimVal fc (Str (prim__cast_IntegerString i)))
castString [NPrimVal fc (B8 i)] = Just (NPrimVal fc (Str (prim__cast_Bits8String i)))
castString [NPrimVal fc (B16 i)] = Just (NPrimVal fc (Str (prim__cast_Bits16String i)))
castString [NPrimVal fc (B32 i)] = Just (NPrimVal fc (Str (prim__cast_Bits32String i)))
castString [NPrimVal fc (B64 i)] = Just (NPrimVal fc (Str (prim__cast_Bits64String i)))
castString [NPrimVal fc (Ch i)] = Just (NPrimVal fc (Str (prim__cast_CharString i)))
castString _ = Nothing

-- A String's number stays applied, cast to an Int, an Integer or a Double
-- as to every other type. The runtime reads only its own numerals in a
-- string: an integer literal, and for a Double a decimal, an infinity or
-- NaN; any other string is 0. Chez's primitive reads any Scheme number, so
-- there `"1.5"` is the Int 1, `"1/2"` the Double 0.5, and `"1+2i"` a
-- complex number held as a Double, which the next comparison of it raises
-- on; and the integer casts truncate what it reads exactly, raising on
-- `"1e309"`. Either raise crashes the compiler. Reading the runtime's
-- numerals here would be a second implementation of them.

castInteger : Vect 1 (NF vars) -> Maybe (NF vars)
castInteger [NPrimVal fc (I i)] = Just (NPrimVal fc (BI (prim__cast_IntInteger i)))
castInteger [NPrimVal fc (I8 i)] = Just (NPrimVal fc (BI (prim__cast_Int8Integer i)))
castInteger [NPrimVal fc (I16 i)] = Just (NPrimVal fc (BI (prim__cast_Int16Integer i)))
castInteger [NPrimVal fc (I32 i)] = Just (NPrimVal fc (BI (prim__cast_Int32Integer i)))
castInteger [NPrimVal fc (I64 i)] = Just (NPrimVal fc (BI (prim__cast_Int64Integer i)))
castInteger [NPrimVal fc (B8 i)] = Just (NPrimVal fc (BI (prim__cast_Bits8Integer i)))
castInteger [NPrimVal fc (B16 i)] = Just (NPrimVal fc (BI (prim__cast_Bits16Integer i)))
castInteger [NPrimVal fc (B32 i)] = Just (NPrimVal fc (BI (prim__cast_Bits32Integer i)))
castInteger [NPrimVal fc (B64 i)] = Just (NPrimVal fc (BI (prim__cast_Bits64Integer i)))
castInteger [NPrimVal fc (Ch i)] = Just (NPrimVal fc (BI (prim__cast_CharInteger i)))
castInteger [NPrimVal fc (Db i)] = NPrimVal fc . BI . prim__cast_DoubleInteger <$> finite i
castInteger _ = Nothing

castInt : Vect 1 (NF vars) -> Maybe (NF vars)
castInt [NPrimVal fc (I8 i)] = Just (NPrimVal fc (I (prim__cast_Int8Int i)))
castInt [NPrimVal fc (I16 i)] = Just (NPrimVal fc (I (prim__cast_Int16Int i)))
castInt [NPrimVal fc (I32 i)] = Just (NPrimVal fc (I (prim__cast_Int32Int i)))
castInt [NPrimVal fc (I64 i)] = Just (NPrimVal fc (I (prim__cast_Int64Int i)))
castInt [NPrimVal fc (BI i)] = Just (NPrimVal fc (I (prim__cast_IntegerInt i)))
castInt [NPrimVal fc (B8 i)] = Just (NPrimVal fc (I (prim__cast_Bits8Int i)))
castInt [NPrimVal fc (B16 i)] = Just (NPrimVal fc (I (prim__cast_Bits16Int i)))
castInt [NPrimVal fc (B32 i)] = Just (NPrimVal fc (I (prim__cast_Bits32Int i)))
castInt [NPrimVal fc (B64 i)] = Just (NPrimVal fc (I (prim__cast_Bits64Int i)))
castInt [NPrimVal fc (Db i)] = NPrimVal fc . I . prim__cast_DoubleInt <$> finite i
castInt [NPrimVal fc (Ch i)] = Just (NPrimVal fc (I (prim__cast_CharInt i)))
castInt _ = Nothing

-- The casts to a fixed-width integer below fold from an integer only, as
-- they always have; one from a Double, a Char or a String stays applied.

castBits8 : Vect 1 (NF vars) -> Maybe (NF vars)
castBits8 [NPrimVal fc (I i)] = Just (NPrimVal fc (B8 (prim__cast_IntBits8 i)))
castBits8 [NPrimVal fc (I8 i)] = Just (NPrimVal fc (B8 (prim__cast_Int8Bits8 i)))
castBits8 [NPrimVal fc (I16 i)] = Just (NPrimVal fc (B8 (prim__cast_Int16Bits8 i)))
castBits8 [NPrimVal fc (I32 i)] = Just (NPrimVal fc (B8 (prim__cast_Int32Bits8 i)))
castBits8 [NPrimVal fc (I64 i)] = Just (NPrimVal fc (B8 (prim__cast_Int64Bits8 i)))
castBits8 [NPrimVal fc (BI i)] = Just (NPrimVal fc (B8 (prim__cast_IntegerBits8 i)))
castBits8 [NPrimVal fc (B16 i)] = Just (NPrimVal fc (B8 (prim__cast_Bits16Bits8 i)))
castBits8 [NPrimVal fc (B32 i)] = Just (NPrimVal fc (B8 (prim__cast_Bits32Bits8 i)))
castBits8 [NPrimVal fc (B64 i)] = Just (NPrimVal fc (B8 (prim__cast_Bits64Bits8 i)))
castBits8 _ = Nothing

castBits16 : Vect 1 (NF vars) -> Maybe (NF vars)
castBits16 [NPrimVal fc (I i)] = Just (NPrimVal fc (B16 (prim__cast_IntBits16 i)))
castBits16 [NPrimVal fc (I8 i)] = Just (NPrimVal fc (B16 (prim__cast_Int8Bits16 i)))
castBits16 [NPrimVal fc (I16 i)] = Just (NPrimVal fc (B16 (prim__cast_Int16Bits16 i)))
castBits16 [NPrimVal fc (I32 i)] = Just (NPrimVal fc (B16 (prim__cast_Int32Bits16 i)))
castBits16 [NPrimVal fc (I64 i)] = Just (NPrimVal fc (B16 (prim__cast_Int64Bits16 i)))
castBits16 [NPrimVal fc (BI i)] = Just (NPrimVal fc (B16 (prim__cast_IntegerBits16 i)))
castBits16 [NPrimVal fc (B8 i)] = Just (NPrimVal fc (B16 (prim__cast_Bits8Bits16 i)))
castBits16 [NPrimVal fc (B32 i)] = Just (NPrimVal fc (B16 (prim__cast_Bits32Bits16 i)))
castBits16 [NPrimVal fc (B64 i)] = Just (NPrimVal fc (B16 (prim__cast_Bits64Bits16 i)))
castBits16 _ = Nothing

castBits32 : Vect 1 (NF vars) -> Maybe (NF vars)
castBits32 [NPrimVal fc (I i)] = Just (NPrimVal fc (B32 (prim__cast_IntBits32 i)))
castBits32 [NPrimVal fc (I8 i)] = Just (NPrimVal fc (B32 (prim__cast_Int8Bits32 i)))
castBits32 [NPrimVal fc (I16 i)] = Just (NPrimVal fc (B32 (prim__cast_Int16Bits32 i)))
castBits32 [NPrimVal fc (I32 i)] = Just (NPrimVal fc (B32 (prim__cast_Int32Bits32 i)))
castBits32 [NPrimVal fc (I64 i)] = Just (NPrimVal fc (B32 (prim__cast_Int64Bits32 i)))
castBits32 [NPrimVal fc (BI i)] = Just (NPrimVal fc (B32 (prim__cast_IntegerBits32 i)))
castBits32 [NPrimVal fc (B8 i)] = Just (NPrimVal fc (B32 (prim__cast_Bits8Bits32 i)))
castBits32 [NPrimVal fc (B16 i)] = Just (NPrimVal fc (B32 (prim__cast_Bits16Bits32 i)))
castBits32 [NPrimVal fc (B64 i)] = Just (NPrimVal fc (B32 (prim__cast_Bits64Bits32 i)))
castBits32 _ = Nothing

castBits64 : Vect 1 (NF vars) -> Maybe (NF vars)
castBits64 [NPrimVal fc (I i)] = Just (NPrimVal fc (B64 (prim__cast_IntBits64 i)))
castBits64 [NPrimVal fc (I8 i)] = Just (NPrimVal fc (B64 (prim__cast_Int8Bits64 i)))
castBits64 [NPrimVal fc (I16 i)] = Just (NPrimVal fc (B64 (prim__cast_Int16Bits64 i)))
castBits64 [NPrimVal fc (I32 i)] = Just (NPrimVal fc (B64 (prim__cast_Int32Bits64 i)))
castBits64 [NPrimVal fc (I64 i)] = Just (NPrimVal fc (B64 (prim__cast_Int64Bits64 i)))
castBits64 [NPrimVal fc (BI i)] = Just (NPrimVal fc (B64 (prim__cast_IntegerBits64 i)))
castBits64 [NPrimVal fc (B8 i)] = Just (NPrimVal fc (B64 (prim__cast_Bits8Bits64 i)))
castBits64 [NPrimVal fc (B16 i)] = Just (NPrimVal fc (B64 (prim__cast_Bits16Bits64 i)))
castBits64 [NPrimVal fc (B32 i)] = Just (NPrimVal fc (B64 (prim__cast_Bits32Bits64 i)))
castBits64 _ = Nothing

castInt8 : Vect 1 (NF vars) -> Maybe (NF vars)
castInt8 [NPrimVal fc (I i)] = Just (NPrimVal fc (I8 (prim__cast_IntInt8 i)))
castInt8 [NPrimVal fc (I16 i)] = Just (NPrimVal fc (I8 (prim__cast_Int16Int8 i)))
castInt8 [NPrimVal fc (I32 i)] = Just (NPrimVal fc (I8 (prim__cast_Int32Int8 i)))
castInt8 [NPrimVal fc (I64 i)] = Just (NPrimVal fc (I8 (prim__cast_Int64Int8 i)))
castInt8 [NPrimVal fc (BI i)] = Just (NPrimVal fc (I8 (prim__cast_IntegerInt8 i)))
castInt8 [NPrimVal fc (B8 i)] = Just (NPrimVal fc (I8 (prim__cast_Bits8Int8 i)))
castInt8 [NPrimVal fc (B16 i)] = Just (NPrimVal fc (I8 (prim__cast_Bits16Int8 i)))
castInt8 [NPrimVal fc (B32 i)] = Just (NPrimVal fc (I8 (prim__cast_Bits32Int8 i)))
castInt8 [NPrimVal fc (B64 i)] = Just (NPrimVal fc (I8 (prim__cast_Bits64Int8 i)))
castInt8 _ = Nothing

castInt16 : Vect 1 (NF vars) -> Maybe (NF vars)
castInt16 [NPrimVal fc (I i)] = Just (NPrimVal fc (I16 (prim__cast_IntInt16 i)))
castInt16 [NPrimVal fc (I8 i)] = Just (NPrimVal fc (I16 (prim__cast_Int8Int16 i)))
castInt16 [NPrimVal fc (I32 i)] = Just (NPrimVal fc (I16 (prim__cast_Int32Int16 i)))
castInt16 [NPrimVal fc (I64 i)] = Just (NPrimVal fc (I16 (prim__cast_Int64Int16 i)))
castInt16 [NPrimVal fc (BI i)] = Just (NPrimVal fc (I16 (prim__cast_IntegerInt16 i)))
castInt16 [NPrimVal fc (B8 i)] = Just (NPrimVal fc (I16 (prim__cast_Bits8Int16 i)))
castInt16 [NPrimVal fc (B16 i)] = Just (NPrimVal fc (I16 (prim__cast_Bits16Int16 i)))
castInt16 [NPrimVal fc (B32 i)] = Just (NPrimVal fc (I16 (prim__cast_Bits32Int16 i)))
castInt16 [NPrimVal fc (B64 i)] = Just (NPrimVal fc (I16 (prim__cast_Bits64Int16 i)))
castInt16 _ = Nothing

castInt32 : Vect 1 (NF vars) -> Maybe (NF vars)
castInt32 [NPrimVal fc (I i)] = Just (NPrimVal fc (I32 (prim__cast_IntInt32 i)))
castInt32 [NPrimVal fc (I8 i)] = Just (NPrimVal fc (I32 (prim__cast_Int8Int32 i)))
castInt32 [NPrimVal fc (I16 i)] = Just (NPrimVal fc (I32 (prim__cast_Int16Int32 i)))
castInt32 [NPrimVal fc (I64 i)] = Just (NPrimVal fc (I32 (prim__cast_Int64Int32 i)))
castInt32 [NPrimVal fc (BI i)] = Just (NPrimVal fc (I32 (prim__cast_IntegerInt32 i)))
castInt32 [NPrimVal fc (B8 i)] = Just (NPrimVal fc (I32 (prim__cast_Bits8Int32 i)))
castInt32 [NPrimVal fc (B16 i)] = Just (NPrimVal fc (I32 (prim__cast_Bits16Int32 i)))
castInt32 [NPrimVal fc (B32 i)] = Just (NPrimVal fc (I32 (prim__cast_Bits32Int32 i)))
castInt32 [NPrimVal fc (B64 i)] = Just (NPrimVal fc (I32 (prim__cast_Bits64Int32 i)))
castInt32 _ = Nothing

castInt64 : Vect 1 (NF vars) -> Maybe (NF vars)
castInt64 [NPrimVal fc (I i)] = Just (NPrimVal fc (I64 (prim__cast_IntInt64 i)))
castInt64 [NPrimVal fc (I8 i)] = Just (NPrimVal fc (I64 (prim__cast_Int8Int64 i)))
castInt64 [NPrimVal fc (I16 i)] = Just (NPrimVal fc (I64 (prim__cast_Int16Int64 i)))
castInt64 [NPrimVal fc (I32 i)] = Just (NPrimVal fc (I64 (prim__cast_Int32Int64 i)))
castInt64 [NPrimVal fc (BI i)] = Just (NPrimVal fc (I64 (prim__cast_IntegerInt64 i)))
castInt64 [NPrimVal fc (B8 i)] = Just (NPrimVal fc (I64 (prim__cast_Bits8Int64 i)))
castInt64 [NPrimVal fc (B16 i)] = Just (NPrimVal fc (I64 (prim__cast_Bits16Int64 i)))
castInt64 [NPrimVal fc (B32 i)] = Just (NPrimVal fc (I64 (prim__cast_Bits32Int64 i)))
castInt64 [NPrimVal fc (B64 i)] = Just (NPrimVal fc (I64 (prim__cast_Bits64Int64 i)))
castInt64 _ = Nothing

castDouble : Vect 1 (NF vars) -> Maybe (NF vars)
castDouble [NPrimVal fc (I i)] = Just (NPrimVal fc (Db (prim__cast_IntDouble i)))
castDouble [NPrimVal fc (I8 i)] = Just (NPrimVal fc (Db (prim__cast_Int8Double i)))
castDouble [NPrimVal fc (I16 i)] = Just (NPrimVal fc (Db (prim__cast_Int16Double i)))
castDouble [NPrimVal fc (I32 i)] = Just (NPrimVal fc (Db (prim__cast_Int32Double i)))
castDouble [NPrimVal fc (I64 i)] = Just (NPrimVal fc (Db (prim__cast_Int64Double i)))
castDouble [NPrimVal fc (B8 i)] = Just (NPrimVal fc (Db (prim__cast_Bits8Double i)))
castDouble [NPrimVal fc (B16 i)] = Just (NPrimVal fc (Db (prim__cast_Bits16Double i)))
castDouble [NPrimVal fc (B32 i)] = Just (NPrimVal fc (Db (prim__cast_Bits32Double i)))
castDouble [NPrimVal fc (B64 i)] = Just (NPrimVal fc (Db (prim__cast_Bits64Double i)))
castDouble [NPrimVal fc (BI i)] = Just (NPrimVal fc (Db (prim__cast_IntegerDouble i)))
castDouble _ = Nothing

castChar : Vect 1 (NF vars) -> Maybe (NF vars)
castChar [NPrimVal fc (I i)] = Just (NPrimVal fc (Ch (prim__cast_IntChar i)))
castChar [NPrimVal fc (I8 i)] = Just (NPrimVal fc (Ch (prim__cast_Int8Char i)))
castChar [NPrimVal fc (I16 i)] = Just (NPrimVal fc (Ch (prim__cast_Int16Char i)))
castChar [NPrimVal fc (I32 i)] = Just (NPrimVal fc (Ch (prim__cast_Int32Char i)))
castChar [NPrimVal fc (I64 i)] = Just (NPrimVal fc (Ch (prim__cast_Int64Char i)))
castChar [NPrimVal fc (B8 i)] = Just (NPrimVal fc (Ch (prim__cast_Bits8Char i)))
castChar [NPrimVal fc (B16 i)] = Just (NPrimVal fc (Ch (prim__cast_Bits16Char i)))
castChar [NPrimVal fc (B32 i)] = Just (NPrimVal fc (Ch (prim__cast_Bits32Char i)))
castChar [NPrimVal fc (B64 i)] = Just (NPrimVal fc (Ch (prim__cast_Bits64Char i)))
castChar [NPrimVal fc (BI i)] = Just (NPrimVal fc (Ch (prim__cast_IntegerChar i)))
castChar _ = Nothing

strLength : Vect 1 (NF vars) -> Maybe (NF vars)
strLength [NPrimVal fc (Str s)] = Just (NPrimVal fc (I (prim__strLength s)))
strLength _ = Nothing

-- A partial primitive is applied through the host's trusted form of it
-- (`Core.Primitives.Host`), which stays unapplied where the primitive fails.
strHead : Vect 1 (NF vars) -> Maybe (NF vars)
strHead [NPrimVal fc (Str str)] = NPrimVal fc . Ch <$> stringHead str
strHead _ = Nothing

strTail : Vect 1 (NF vars) -> Maybe (NF vars)
strTail [NPrimVal fc (Str str)] = NPrimVal fc . Str <$> stringTail str
strTail _ = Nothing

strIndex : Vect 2 (NF vars) -> Maybe (NF vars)
strIndex [NPrimVal fc (Str str), NPrimVal _ (I i)] = NPrimVal fc . Ch <$> stringIndex str i
strIndex _ = Nothing

strCons : Vect 2 (NF vars) -> Maybe (NF vars)
strCons [NPrimVal fc (Ch x), NPrimVal _ (Str y)]
    = Just (NPrimVal fc (Str (prim__strCons x y)))
strCons _ = Nothing

strAppend : Vect 2 (NF vars) -> Maybe (NF vars)
strAppend [NPrimVal fc (Str x), NPrimVal _ (Str y)]
    = Just (NPrimVal fc (Str (prim__strAppend x y)))
strAppend _ = Nothing

strReverse : Vect 1 (NF vars) -> Maybe (NF vars)
strReverse [NPrimVal fc (Str x)]
    = Just (NPrimVal fc (Str (prim__strReverse x)))
strReverse _ = Nothing

strSubstr : Vect 3 (NF vars) -> Maybe (NF vars)
strSubstr [NPrimVal fc (I start), NPrimVal _ (I len), NPrimVal _ (Str str)]
    = Just (NPrimVal fc (Str (prim__strSubstr start len str)))
strSubstr _ = Nothing


add : Constant -> Constant -> Maybe Constant
add (BI x) (BI y) = pure $ BI (prim__add_Integer x y)
add (I x) (I y) = pure $ I (prim__add_Int x y)
add (I8 x) (I8 y) = pure $ I8 (prim__add_Int8 x y)
add (I16 x) (I16 y) = pure $ I16 (prim__add_Int16 x y)
add (I32 x) (I32 y) = pure $ I32 (prim__add_Int32 x y)
add (I64 x) (I64 y) = pure $ I64 (prim__add_Int64 x y)
add (B8 x) (B8 y) = pure $ B8 (prim__add_Bits8 x y)
add (B16 x) (B16 y) = pure $ B16 (prim__add_Bits16 x y)
add (B32 x) (B32 y) = pure $ B32 (prim__add_Bits32 x y)
add (B64 x) (B64 y) = pure $ B64 (prim__add_Bits64 x y)
add (Db x) (Db y) = number (prim__add_Double x y)
add _ _ = Nothing

sub : Constant -> Constant -> Maybe Constant
sub (BI x) (BI y) = pure $ BI (prim__sub_Integer x y)
sub (I x) (I y) = pure $ I (prim__sub_Int x y)
sub (I8 x) (I8 y) = pure $ I8 (prim__sub_Int8 x y)
sub (I16 x) (I16 y) = pure $ I16 (prim__sub_Int16 x y)
sub (I32 x) (I32 y) = pure $ I32 (prim__sub_Int32 x y)
sub (I64 x) (I64 y) = pure $ I64 (prim__sub_Int64 x y)
sub (B8 x) (B8 y) = pure $ B8 (prim__sub_Bits8 x y)
sub (B16 x) (B16 y) = pure $ B16 (prim__sub_Bits16 x y)
sub (B32 x) (B32 y) = pure $ B32 (prim__sub_Bits32 x y)
sub (B64 x) (B64 y) = pure $ B64 (prim__sub_Bits64 x y)
sub (Db x) (Db y) = number (prim__sub_Double x y)
sub _ _ = Nothing

mul : Constant -> Constant -> Maybe Constant
mul (BI x) (BI y) = pure $ BI (prim__mul_Integer x y)
mul (B8 x) (B8 y) = pure $ B8 (prim__mul_Bits8 x y)
mul (B16 x) (B16 y) = pure $ B16 (prim__mul_Bits16 x y)
mul (B32 x) (B32 y) = pure $ B32 (prim__mul_Bits32 x y)
mul (B64 x) (B64 y) = pure $ B64 (prim__mul_Bits64 x y)
mul (I x) (I y) = pure $ I (prim__mul_Int x y)
mul (I8 x) (I8 y) = pure $ I8 (prim__mul_Int8 x y)
mul (I16 x) (I16 y) = pure $ I16 (prim__mul_Int16 x y)
mul (I32 x) (I32 y) = pure $ I32 (prim__mul_Int32 x y)
mul (I64 x) (I64 y) = pure $ I64 (prim__mul_Int64 x y)
mul (Db x) (Db y) = number (prim__mul_Double x y)
mul _ _ = Nothing

-- Through the host's trusted division and remainder, which stay unapplied
-- at a zero divisor.
div : Constant -> Constant -> Maybe Constant
div (BI x) (BI y) = BI <$> divInteger x y
div (I x) (I y) = I <$> divInt x y
div (I8 x) (I8 y) = I8 <$> divInt8 x y
div (I16 x) (I16 y) = I16 <$> divInt16 x y
div (I32 x) (I32 y) = I32 <$> divInt32 x y
div (I64 x) (I64 y) = I64 <$> divInt64 x y
div (B8 x) (B8 y) = B8 <$> divBits8 x y
div (B16 x) (B16 y) = B16 <$> divBits16 x y
div (B32 x) (B32 y) = B32 <$> divBits32 x y
div (B64 x) (B64 y) = B64 <$> divBits64 x y
-- A double's division never fails, but its primitive is registered partial
-- with the integers' divisions, so it is reached through `/`, which is that
-- primitive for `Double`.
div (Db x) (Db y) = number (x / y)
div _ _ = Nothing

mod : Constant -> Constant -> Maybe Constant
mod (BI x) (BI y) = BI <$> modInteger x y
mod (I x) (I y) = I <$> modInt x y
mod (I8 x) (I8 y) = I8 <$> modInt8 x y
mod (I16 x) (I16 y) = I16 <$> modInt16 x y
mod (I32 x) (I32 y) = I32 <$> modInt32 x y
mod (I64 x) (I64 y) = I64 <$> modInt64 x y
mod (B8 x) (B8 y) = B8 <$> modBits8 x y
mod (B16 x) (B16 y) = B16 <$> modBits16 x y
mod (B32 x) (B32 y) = B32 <$> modBits32 x y
mod (B64 x) (B64 y) = B64 <$> modBits64 x y
mod _ _ = Nothing

shiftl : Constant -> Constant -> Maybe Constant
shiftl (I x) (I y) = pure $ I (prim__shl_Int x y)
shiftl (I8 x) (I8 y) = pure $ I8 (prim__shl_Int8 x y)
shiftl (I16 x) (I16 y) = pure $ I16 (prim__shl_Int16 x y)
shiftl (I32 x) (I32 y) = pure $ I32 (prim__shl_Int32 x y)
shiftl (I64 x) (I64 y) = pure $ I64 (prim__shl_Int64 x y)
shiftl (BI x) (BI y) = pure $ BI (prim__shl_Integer x y)
shiftl (B8 x) (B8 y) = pure $ B8 (prim__shl_Bits8 x y)
shiftl (B16 x) (B16 y) = pure $ B16 (prim__shl_Bits16 x y)
shiftl (B32 x) (B32 y) = pure $ B32 (prim__shl_Bits32 x y)
shiftl (B64 x) (B64 y) = pure $ B64 (prim__shl_Bits64 x y)
shiftl _ _ = Nothing

shiftr : Constant -> Constant -> Maybe Constant
shiftr (I x) (I y) = pure $ I (prim__shr_Int x y)
shiftr (I8 x) (I8 y) = pure $ I8 (prim__shr_Int8 x y)
shiftr (I16 x) (I16 y) = pure $ I16 (prim__shr_Int16 x y)
shiftr (I32 x) (I32 y) = pure $ I32 (prim__shr_Int32 x y)
shiftr (I64 x) (I64 y) = pure $ I64 (prim__shr_Int64 x y)
shiftr (BI x) (BI y) = pure $ BI (prim__shr_Integer x y)
shiftr (B8 x) (B8 y) = pure $ B8 (prim__shr_Bits8 x y)
shiftr (B16 x) (B16 y) = pure $ B16 (prim__shr_Bits16 x y)
shiftr (B32 x) (B32 y) = pure $ B32 (prim__shr_Bits32 x y)
shiftr (B64 x) (B64 y) = pure $ B64 (prim__shr_Bits64 x y)
shiftr _ _ = Nothing

band : Constant -> Constant -> Maybe Constant
band (I x) (I y) = pure $ I (prim__and_Int x y)
band (I8 x) (I8 y) = pure $ I8 (prim__and_Int8 x y)
band (I16 x) (I16 y) = pure $ I16 (prim__and_Int16 x y)
band (I32 x) (I32 y) = pure $ I32 (prim__and_Int32 x y)
band (I64 x) (I64 y) = pure $ I64 (prim__and_Int64 x y)
band (BI x) (BI y) = pure $ BI (prim__and_Integer x y)
band (B8 x) (B8 y) = pure $ B8 (prim__and_Bits8 x y)
band (B16 x) (B16 y) = pure $ B16 (prim__and_Bits16 x y)
band (B32 x) (B32 y) = pure $ B32 (prim__and_Bits32 x y)
band (B64 x) (B64 y) = pure $ B64 (prim__and_Bits64 x y)
band _ _ = Nothing

bor : Constant -> Constant -> Maybe Constant
bor (I x) (I y) = pure $ I (prim__or_Int x y)
bor (I8 x) (I8 y) = pure $ I8 (prim__or_Int8 x y)
bor (I16 x) (I16 y) = pure $ I16 (prim__or_Int16 x y)
bor (I32 x) (I32 y) = pure $ I32 (prim__or_Int32 x y)
bor (I64 x) (I64 y) = pure $ I64 (prim__or_Int64 x y)
bor (BI x) (BI y) = pure $ BI (prim__or_Integer x y)
bor (B8 x) (B8 y) = pure $ B8 (prim__or_Bits8 x y)
bor (B16 x) (B16 y) = pure $ B16 (prim__or_Bits16 x y)
bor (B32 x) (B32 y) = pure $ B32 (prim__or_Bits32 x y)
bor (B64 x) (B64 y) = pure $ B64 (prim__or_Bits64 x y)
bor _ _ = Nothing

bxor : Constant -> Constant -> Maybe Constant
bxor (I x) (I y) = pure $ I (prim__xor_Int x y)
bxor (B8 x) (B8 y) = pure $ B8 (prim__xor_Bits8 x y)
bxor (B16 x) (B16 y) = pure $ B16 (prim__xor_Bits16 x y)
bxor (B32 x) (B32 y) = pure $ B32 (prim__xor_Bits32 x y)
bxor (B64 x) (B64 y) = pure $ B64 (prim__xor_Bits64 x y)
bxor (I8 x) (I8 y) = pure $ I8 (prim__xor_Int8 x y)
bxor (I16 x) (I16 y) = pure $ I16 (prim__xor_Int16 x y)
bxor (I32 x) (I32 y) = pure $ I32 (prim__xor_Int32 x y)
bxor (I64 x) (I64 y) = pure $ I64 (prim__xor_Int64 x y)
bxor (BI x) (BI y) = pure $ BI (prim__xor_Integer x y)
bxor _ _ = Nothing

-- A fixed-width integer's negation stays applied: there is no one meaning
-- to call. The Chez backend's does not wrap (the negation of a Bits8 is
-- negative, and of the least Int8 is 128, neither a value of its type),
-- and a backend need not have the primitive at all; base negates with
-- subtraction from zero instead.
neg : Constant -> Maybe Constant
neg (BI x) = pure $ BI (prim__negate_Integer x)
neg (Db x) = number (prim__negate_Double x)
neg _ = Nothing

lt : Constant -> Constant -> Maybe Constant
lt (I x) (I y) = pure $ I (prim__lt_Int x y)
lt (I8 x) (I8 y) = pure $ I (prim__lt_Int8 x y)
lt (I16 x) (I16 y) = pure $ I (prim__lt_Int16 x y)
lt (I32 x) (I32 y) = pure $ I (prim__lt_Int32 x y)
lt (I64 x) (I64 y) = pure $ I (prim__lt_Int64 x y)
lt (BI x) (BI y) = pure $ I (prim__lt_Integer x y)
lt (B8 x) (B8 y) = pure $ I (prim__lt_Bits8 x y)
lt (B16 x) (B16 y) = pure $ I (prim__lt_Bits16 x y)
lt (B32 x) (B32 y) = pure $ I (prim__lt_Bits32 x y)
lt (B64 x) (B64 y) = pure $ I (prim__lt_Bits64 x y)
lt (Str x) (Str y) = pure $ I (prim__lt_String x y)
lt (Ch x) (Ch y) = pure $ I (prim__lt_Char x y)
lt (Db x) (Db y) = pure $ I (prim__lt_Double x y)
lt _ _ = Nothing

lte : Constant -> Constant -> Maybe Constant
lte (I x) (I y) = pure $ I (prim__lte_Int x y)
lte (I8 x) (I8 y) = pure $ I (prim__lte_Int8 x y)
lte (I16 x) (I16 y) = pure $ I (prim__lte_Int16 x y)
lte (I32 x) (I32 y) = pure $ I (prim__lte_Int32 x y)
lte (I64 x) (I64 y) = pure $ I (prim__lte_Int64 x y)
lte (BI x) (BI y) = pure $ I (prim__lte_Integer x y)
lte (B8 x) (B8 y) = pure $ I (prim__lte_Bits8 x y)
lte (B16 x) (B16 y) = pure $ I (prim__lte_Bits16 x y)
lte (B32 x) (B32 y) = pure $ I (prim__lte_Bits32 x y)
lte (B64 x) (B64 y) = pure $ I (prim__lte_Bits64 x y)
lte (Str x) (Str y) = pure $ I (prim__lte_String x y)
lte (Ch x) (Ch y) = pure $ I (prim__lte_Char x y)
lte (Db x) (Db y) = pure $ I (prim__lte_Double x y)
lte _ _ = Nothing

eq : Constant -> Constant -> Maybe Constant
eq (I x) (I y) = pure $ I (prim__eq_Int x y)
eq (I8 x) (I8 y) = pure $ I (prim__eq_Int8 x y)
eq (I16 x) (I16 y) = pure $ I (prim__eq_Int16 x y)
eq (I32 x) (I32 y) = pure $ I (prim__eq_Int32 x y)
eq (I64 x) (I64 y) = pure $ I (prim__eq_Int64 x y)
eq (BI x) (BI y) = pure $ I (prim__eq_Integer x y)
eq (B8 x) (B8 y) = pure $ I (prim__eq_Bits8 x y)
eq (B16 x) (B16 y) = pure $ I (prim__eq_Bits16 x y)
eq (B32 x) (B32 y) = pure $ I (prim__eq_Bits32 x y)
eq (B64 x) (B64 y) = pure $ I (prim__eq_Bits64 x y)
eq (Str x) (Str y) = pure $ I (prim__eq_String x y)
eq (Ch x) (Ch y) = pure $ I (prim__eq_Char x y)
eq (Db x) (Db y) = pure $ I (prim__eq_Double x y)
eq _ _ = Nothing

gte : Constant -> Constant -> Maybe Constant
gte (I x) (I y) = pure $ I (prim__gte_Int x y)
gte (I8 x) (I8 y) = pure $ I (prim__gte_Int8 x y)
gte (I16 x) (I16 y) = pure $ I (prim__gte_Int16 x y)
gte (I32 x) (I32 y) = pure $ I (prim__gte_Int32 x y)
gte (I64 x) (I64 y) = pure $ I (prim__gte_Int64 x y)
gte (BI x) (BI y) = pure $ I (prim__gte_Integer x y)
gte (B8 x) (B8 y) = pure $ I (prim__gte_Bits8 x y)
gte (B16 x) (B16 y) = pure $ I (prim__gte_Bits16 x y)
gte (B32 x) (B32 y) = pure $ I (prim__gte_Bits32 x y)
gte (B64 x) (B64 y) = pure $ I (prim__gte_Bits64 x y)
gte (Str x) (Str y) = pure $ I (prim__gte_String x y)
gte (Ch x) (Ch y) = pure $ I (prim__gte_Char x y)
gte (Db x) (Db y) = pure $ I (prim__gte_Double x y)
gte _ _ = Nothing

gt : Constant -> Constant -> Maybe Constant
gt (I x) (I y) = pure $ I (prim__gt_Int x y)
gt (I8 x) (I8 y) = pure $ I (prim__gt_Int8 x y)
gt (I16 x) (I16 y) = pure $ I (prim__gt_Int16 x y)
gt (I32 x) (I32 y) = pure $ I (prim__gt_Int32 x y)
gt (I64 x) (I64 y) = pure $ I (prim__gt_Int64 x y)
gt (BI x) (BI y) = pure $ I (prim__gt_Integer x y)
gt (B8 x) (B8 y) = pure $ I (prim__gt_Bits8 x y)
gt (B16 x) (B16 y) = pure $ I (prim__gt_Bits16 x y)
gt (B32 x) (B32 y) = pure $ I (prim__gt_Bits32 x y)
gt (B64 x) (B64 y) = pure $ I (prim__gt_Bits64 x y)
gt (Str x) (Str y) = pure $ I (prim__gt_String x y)
gt (Ch x) (Ch y) = pure $ I (prim__gt_Char x y)
gt (Db x) (Db y) = pure $ I (prim__gt_Double x y)
gt _ _ = Nothing

-- A Double's root, floor and ceiling fold: IEEE 754 defines each as one
-- double, the root rounded correctly and the floor and ceiling exact, so
-- the host computes the double the program computes on its target (Chez's
-- `flsqrt`, `flfloor` and `flceiling` on the stock host; upstream's math
-- ops on idris-mlir, as in the program). A Double's other functions (exp,
-- log, pow, sin, cos, tan and their inverses) stay applied: each is the C
-- library's, whose last digit IEEE 754 leaves to each library, so the
-- host's library could give another double than the target's.
doubleOp : (Double -> Double) -> Vect 1 (NF vars) -> Maybe (NF vars)
doubleOp f [NPrimVal fc (Db x)] = NPrimVal fc <$> number (f x)
doubleOp f _ = Nothing

doubleSqrt : Vect 1 (NF vars) -> Maybe (NF vars)
doubleSqrt = doubleOp (\x => prim__doubleSqrt x)

doubleFloor : Vect 1 (NF vars) -> Maybe (NF vars)
doubleFloor = doubleOp (\x => prim__doubleFloor x)

doubleCeiling : Vect 1 (NF vars) -> Maybe (NF vars)
doubleCeiling = doubleOp (\x => prim__doubleCeiling x)

-- Only reduce for concrete values
believeMe : Vect 3 (NF vars) -> Maybe (NF vars)
believeMe [_, _, val@(NDCon {})] = Just val
believeMe [_, _, val@(NTCon {})] = Just val
believeMe [_, _, val@(NPrimVal {})] = Just val
believeMe [_, _, NType fc u] = Just (NType fc u)
believeMe [_, _, val] = Nothing

primTyVal : PrimType -> ClosedTerm
primTyVal = PrimVal emptyFC . PrT

constTy : PrimType -> PrimType -> PrimType -> ClosedTerm
constTy a b c
    = let arr = fnType emptyFC in
    primTyVal a `arr` (primTyVal b `arr` primTyVal c)

constTy3 : PrimType -> PrimType -> PrimType -> PrimType -> ClosedTerm
constTy3 a b c d
    = let arr = fnType emptyFC in
    primTyVal a `arr`
         (primTyVal b `arr`
             (primTyVal c `arr` primTyVal d))

predTy : PrimType -> PrimType -> ClosedTerm
predTy a b = let arr = fnType emptyFC in
             primTyVal a `arr` primTyVal b

arithTy : PrimType -> ClosedTerm
arithTy t = constTy t t t

cmpTy : PrimType -> ClosedTerm
cmpTy t = constTy t t IntType

doubleTy : ClosedTerm
doubleTy = predTy DoubleType DoubleType

pi : (x : Known) -> RigCount -> PiInfo (Term xs) -> Term xs ->
     Term (knownUN x :: xs) -> Term xs
pi x rig plic ty sc = Bind emptyFC (knownUN x) (Pi emptyFC rig plic ty) sc

believeMeTy : ClosedTerm
believeMeTy
    = pi Ka erased Explicit (TType emptyFC (MN (known Ktop) 0)) $
      pi Kb erased Explicit (TType emptyFC (MN (known Ktop) 0)) $
      pi Kx linear Explicit (Local emptyFC Nothing _ (Later First)) $
      Local emptyFC Nothing _ (Later First)

crashTy : ClosedTerm
crashTy
    = pi Ka erased Explicit (TType emptyFC (MN (known Ktop) 0)) $
      pi Kmsg top Explicit (PrimVal emptyFC $ PrT StringType) $
      Local emptyFC Nothing _ (Later First)

castTo : PrimType -> Vect 1 (NF vars) -> Maybe (NF vars)
castTo IntType = castInt
castTo Int8Type = castInt8
castTo Int16Type = castInt16
castTo Int32Type = castInt32
castTo Int64Type = castInt64
castTo IntegerType = castInteger
castTo Bits8Type = castBits8
castTo Bits16Type = castBits16
castTo Bits32Type = castBits32
castTo Bits64Type = castBits64
castTo StringType = castString
castTo CharType = castChar
castTo DoubleType = castDouble
castTo WorldType = const Nothing

export
getOp : {0 arity : Nat} -> PrimFn arity ->
        {vars : Scope} -> Vect arity (NF vars) -> Maybe (NF vars)
getOp (Add ty) = binOp add
getOp (Sub ty) = binOp sub
getOp (Mul ty) = binOp mul
getOp (Div ty) = binOp div
getOp (Mod ty) = binOp mod
getOp (Neg ty) = unaryOp neg
getOp (ShiftL ty) = binOp shiftl
getOp (ShiftR ty) = binOp shiftr

getOp (BAnd ty) = binOp band
getOp (BOr ty) = binOp bor
getOp (BXOr ty) = binOp bxor

getOp (LT ty) = binOp lt
getOp (LTE ty) = binOp lte
getOp (EQ ty) = binOp eq
getOp (GTE ty) = binOp gte
getOp (GT ty) = binOp gt

getOp StrLength = strLength
getOp StrHead = strHead
getOp StrTail = strTail
getOp StrIndex = strIndex
getOp StrCons = strCons
getOp StrAppend = strAppend
getOp StrReverse = strReverse
getOp StrSubstr = strSubstr

getOp DoubleSqrt = doubleSqrt
getOp DoubleFloor = doubleFloor
getOp DoubleCeiling = doubleCeiling

getOp (Cast _ y) = castTo y
getOp BelieveMe = believeMe

-- Every other primitive stays applied: `crash`, and a Double's functions
-- of the C library.
getOp _ = const Nothing

-- A cast from Integer to Double, when the Integer is a Double exactly (no
-- more than 2^53 in magnitude), so that no rounding is involved.
exactDouble : Vect 1 (NF vars) -> Maybe (NF vars)
exactDouble [NPrimVal fc (BI i)]
    = if abs i <= 9007199254740992
         then Just (NPrimVal fc (Db (prim__cast_IntegerDouble i)))
         else Nothing
exactDouble _ = Nothing

||| The primitive that computes nothing: `believe_me` gives a value
||| another type, and is that value on every backend. Elaboration reduces
||| it wherever it reduces a hole, so that a proof a library forges with it
||| (the bound of a `Fin` literal) is the constructor it stands for once the
||| hole it was applied to is solved.
export
coercionOp : {0 arity : Nat} -> PrimFn arity ->
             {vars : Scope} -> Vect arity (NF vars) -> Maybe (NF vars)
coercionOp BelieveMe = believeMe
coercionOp _ = const Nothing

||| The primitives whose result is the same on every backend, which the
||| elaborator may compute when it reduces a literal to a constant:
||| Integer's arithmetic and comparisons (its division and remainder are
||| Euclidean on every backend), a cast from Integer to a fixed-width
||| integer, which wraps, or to a Double that is exactly that Integer, and
||| `believe_me` (coercionOp). Any other primitive, such as the text of a
||| Double or the number a String reads as, means what the backend that
||| runs the program computes, so it stays applied.
export
sharedOp : {0 arity : Nat} -> PrimFn arity ->
           {vars : Scope} -> Vect arity (NF vars) -> Maybe (NF vars)
sharedOp (Add IntegerType) = binOp add
sharedOp (Sub IntegerType) = binOp sub
sharedOp (Mul IntegerType) = binOp mul
sharedOp (Div IntegerType) = binOp div
sharedOp (Mod IntegerType) = binOp mod
sharedOp (Neg IntegerType) = unaryOp neg
sharedOp (LT IntegerType) = binOp lt
sharedOp (LTE IntegerType) = binOp lte
sharedOp (EQ IntegerType) = binOp eq
sharedOp (GTE IntegerType) = binOp gte
sharedOp (GT IntegerType) = binOp gt
sharedOp (Cast IntegerType IntType) = castInt
sharedOp (Cast IntegerType Int8Type) = castInt8
sharedOp (Cast IntegerType Int16Type) = castInt16
sharedOp (Cast IntegerType Int32Type) = castInt32
sharedOp (Cast IntegerType Int64Type) = castInt64
sharedOp (Cast IntegerType Bits8Type) = castBits8
sharedOp (Cast IntegerType Bits16Type) = castBits16
sharedOp (Cast IntegerType Bits32Type) = castBits32
sharedOp (Cast IntegerType Bits64Type) = castBits64
sharedOp (Cast IntegerType DoubleType) = exactDouble
sharedOp op = coercionOp op

-- The primitives of one operation, one at each type it has, each with its
-- name.
typed : {arity : Nat} -> (PrimType -> PrimFn arity) -> (PrimType -> ClosedTerm) ->
        Totality -> List (PrimType, Known) -> List Prim
typed op ty tot = map (\(t, k) => MkPrim k (op t) (ty t) tot)

-- The casts, each from one type to another, with its name.
casts : List (PrimType, PrimType, Known) -> List Prim
casts = map (\(from, to, k) => MkPrim k (Cast from to) (predTy from to) isTotal)

||| Every primitive, each once, with its name. Which operation is at which
||| type is irregular (no `mod`, shift or bitwise operation at `Double`, no
||| arithmetic at `String` or `Char`, no cast from a type to itself, from
||| `String` or `Double` to `Char`, or from `Char` to `Double`), so the
||| primitives are a table, and a name is known only for a primitive in it.
export
allPrimitives : List Prim
allPrimitives =
    typed Add arithTy isTotal
      [ (IntType, Kprim__add_Int)
      , (Int8Type, Kprim__add_Int8)
      , (Int16Type, Kprim__add_Int16)
      , (Int32Type, Kprim__add_Int32)
      , (Int64Type, Kprim__add_Int64)
      , (IntegerType, Kprim__add_Integer)
      , (Bits8Type, Kprim__add_Bits8)
      , (Bits16Type, Kprim__add_Bits16)
      , (Bits32Type, Kprim__add_Bits32)
      , (Bits64Type, Kprim__add_Bits64)
      , (DoubleType, Kprim__add_Double)
      ] ++

    typed Sub arithTy isTotal
      [ (IntType, Kprim__sub_Int)
      , (Int8Type, Kprim__sub_Int8)
      , (Int16Type, Kprim__sub_Int16)
      , (Int32Type, Kprim__sub_Int32)
      , (Int64Type, Kprim__sub_Int64)
      , (IntegerType, Kprim__sub_Integer)
      , (Bits8Type, Kprim__sub_Bits8)
      , (Bits16Type, Kprim__sub_Bits16)
      , (Bits32Type, Kprim__sub_Bits32)
      , (Bits64Type, Kprim__sub_Bits64)
      , (DoubleType, Kprim__sub_Double)
      ] ++

    typed Mul arithTy isTotal
      [ (IntType, Kprim__mul_Int)
      , (Int8Type, Kprim__mul_Int8)
      , (Int16Type, Kprim__mul_Int16)
      , (Int32Type, Kprim__mul_Int32)
      , (Int64Type, Kprim__mul_Int64)
      , (IntegerType, Kprim__mul_Integer)
      , (Bits8Type, Kprim__mul_Bits8)
      , (Bits16Type, Kprim__mul_Bits16)
      , (Bits32Type, Kprim__mul_Bits32)
      , (Bits64Type, Kprim__mul_Bits64)
      , (DoubleType, Kprim__mul_Double)
      ] ++

    typed Neg (\t => predTy t t) isTotal
      [ (IntType, Kprim__negate_Int)
      , (Int8Type, Kprim__negate_Int8)
      , (Int16Type, Kprim__negate_Int16)
      , (Int32Type, Kprim__negate_Int32)
      , (Int64Type, Kprim__negate_Int64)
      , (IntegerType, Kprim__negate_Integer)
      , (Bits8Type, Kprim__negate_Bits8)
      , (Bits16Type, Kprim__negate_Bits16)
      , (Bits32Type, Kprim__negate_Bits32)
      , (Bits64Type, Kprim__negate_Bits64)
      , (DoubleType, Kprim__negate_Double)
      ] ++

    typed Div arithTy notCovering
      [ (IntType, Kprim__div_Int)
      , (Int8Type, Kprim__div_Int8)
      , (Int16Type, Kprim__div_Int16)
      , (Int32Type, Kprim__div_Int32)
      , (Int64Type, Kprim__div_Int64)
      , (IntegerType, Kprim__div_Integer)
      , (Bits8Type, Kprim__div_Bits8)
      , (Bits16Type, Kprim__div_Bits16)
      , (Bits32Type, Kprim__div_Bits32)
      , (Bits64Type, Kprim__div_Bits64)
      , (DoubleType, Kprim__div_Double)
      ] ++

    typed Mod arithTy notCovering
      [ (IntType, Kprim__mod_Int)
      , (Int8Type, Kprim__mod_Int8)
      , (Int16Type, Kprim__mod_Int16)
      , (Int32Type, Kprim__mod_Int32)
      , (Int64Type, Kprim__mod_Int64)
      , (IntegerType, Kprim__mod_Integer)
      , (Bits8Type, Kprim__mod_Bits8)
      , (Bits16Type, Kprim__mod_Bits16)
      , (Bits32Type, Kprim__mod_Bits32)
      , (Bits64Type, Kprim__mod_Bits64)
      ] ++

    typed ShiftL arithTy isTotal
      [ (IntType, Kprim__shl_Int)
      , (Int8Type, Kprim__shl_Int8)
      , (Int16Type, Kprim__shl_Int16)
      , (Int32Type, Kprim__shl_Int32)
      , (Int64Type, Kprim__shl_Int64)
      , (IntegerType, Kprim__shl_Integer)
      , (Bits8Type, Kprim__shl_Bits8)
      , (Bits16Type, Kprim__shl_Bits16)
      , (Bits32Type, Kprim__shl_Bits32)
      , (Bits64Type, Kprim__shl_Bits64)
      ] ++

    typed ShiftR arithTy isTotal
      [ (IntType, Kprim__shr_Int)
      , (Int8Type, Kprim__shr_Int8)
      , (Int16Type, Kprim__shr_Int16)
      , (Int32Type, Kprim__shr_Int32)
      , (Int64Type, Kprim__shr_Int64)
      , (IntegerType, Kprim__shr_Integer)
      , (Bits8Type, Kprim__shr_Bits8)
      , (Bits16Type, Kprim__shr_Bits16)
      , (Bits32Type, Kprim__shr_Bits32)
      , (Bits64Type, Kprim__shr_Bits64)
      ] ++

    typed BAnd arithTy isTotal
      [ (IntType, Kprim__and_Int)
      , (Int8Type, Kprim__and_Int8)
      , (Int16Type, Kprim__and_Int16)
      , (Int32Type, Kprim__and_Int32)
      , (Int64Type, Kprim__and_Int64)
      , (IntegerType, Kprim__and_Integer)
      , (Bits8Type, Kprim__and_Bits8)
      , (Bits16Type, Kprim__and_Bits16)
      , (Bits32Type, Kprim__and_Bits32)
      , (Bits64Type, Kprim__and_Bits64)
      ] ++

    typed BOr arithTy isTotal
      [ (IntType, Kprim__or_Int)
      , (Int8Type, Kprim__or_Int8)
      , (Int16Type, Kprim__or_Int16)
      , (Int32Type, Kprim__or_Int32)
      , (Int64Type, Kprim__or_Int64)
      , (IntegerType, Kprim__or_Integer)
      , (Bits8Type, Kprim__or_Bits8)
      , (Bits16Type, Kprim__or_Bits16)
      , (Bits32Type, Kprim__or_Bits32)
      , (Bits64Type, Kprim__or_Bits64)
      ] ++

    typed BXOr arithTy isTotal
      [ (IntType, Kprim__xor_Int)
      , (Int8Type, Kprim__xor_Int8)
      , (Int16Type, Kprim__xor_Int16)
      , (Int32Type, Kprim__xor_Int32)
      , (Int64Type, Kprim__xor_Int64)
      , (IntegerType, Kprim__xor_Integer)
      , (Bits8Type, Kprim__xor_Bits8)
      , (Bits16Type, Kprim__xor_Bits16)
      , (Bits32Type, Kprim__xor_Bits32)
      , (Bits64Type, Kprim__xor_Bits64)
      ] ++

    typed LT cmpTy isTotal
      [ (IntType, Kprim__lt_Int)
      , (Int8Type, Kprim__lt_Int8)
      , (Int16Type, Kprim__lt_Int16)
      , (Int32Type, Kprim__lt_Int32)
      , (Int64Type, Kprim__lt_Int64)
      , (IntegerType, Kprim__lt_Integer)
      , (Bits8Type, Kprim__lt_Bits8)
      , (Bits16Type, Kprim__lt_Bits16)
      , (Bits32Type, Kprim__lt_Bits32)
      , (Bits64Type, Kprim__lt_Bits64)
      , (DoubleType, Kprim__lt_Double)
      , (StringType, Kprim__lt_String)
      , (CharType, Kprim__lt_Char)
      ] ++

    typed LTE cmpTy isTotal
      [ (IntType, Kprim__lte_Int)
      , (Int8Type, Kprim__lte_Int8)
      , (Int16Type, Kprim__lte_Int16)
      , (Int32Type, Kprim__lte_Int32)
      , (Int64Type, Kprim__lte_Int64)
      , (IntegerType, Kprim__lte_Integer)
      , (Bits8Type, Kprim__lte_Bits8)
      , (Bits16Type, Kprim__lte_Bits16)
      , (Bits32Type, Kprim__lte_Bits32)
      , (Bits64Type, Kprim__lte_Bits64)
      , (DoubleType, Kprim__lte_Double)
      , (StringType, Kprim__lte_String)
      , (CharType, Kprim__lte_Char)
      ] ++

    typed EQ cmpTy isTotal
      [ (IntType, Kprim__eq_Int)
      , (Int8Type, Kprim__eq_Int8)
      , (Int16Type, Kprim__eq_Int16)
      , (Int32Type, Kprim__eq_Int32)
      , (Int64Type, Kprim__eq_Int64)
      , (IntegerType, Kprim__eq_Integer)
      , (Bits8Type, Kprim__eq_Bits8)
      , (Bits16Type, Kprim__eq_Bits16)
      , (Bits32Type, Kprim__eq_Bits32)
      , (Bits64Type, Kprim__eq_Bits64)
      , (DoubleType, Kprim__eq_Double)
      , (StringType, Kprim__eq_String)
      , (CharType, Kprim__eq_Char)
      ] ++

    typed GTE cmpTy isTotal
      [ (IntType, Kprim__gte_Int)
      , (Int8Type, Kprim__gte_Int8)
      , (Int16Type, Kprim__gte_Int16)
      , (Int32Type, Kprim__gte_Int32)
      , (Int64Type, Kprim__gte_Int64)
      , (IntegerType, Kprim__gte_Integer)
      , (Bits8Type, Kprim__gte_Bits8)
      , (Bits16Type, Kprim__gte_Bits16)
      , (Bits32Type, Kprim__gte_Bits32)
      , (Bits64Type, Kprim__gte_Bits64)
      , (DoubleType, Kprim__gte_Double)
      , (StringType, Kprim__gte_String)
      , (CharType, Kprim__gte_Char)
      ] ++

    typed GT cmpTy isTotal
      [ (IntType, Kprim__gt_Int)
      , (Int8Type, Kprim__gt_Int8)
      , (Int16Type, Kprim__gt_Int16)
      , (Int32Type, Kprim__gt_Int32)
      , (Int64Type, Kprim__gt_Int64)
      , (IntegerType, Kprim__gt_Integer)
      , (Bits8Type, Kprim__gt_Bits8)
      , (Bits16Type, Kprim__gt_Bits16)
      , (Bits32Type, Kprim__gt_Bits32)
      , (Bits64Type, Kprim__gt_Bits64)
      , (DoubleType, Kprim__gt_Double)
      , (StringType, Kprim__gt_String)
      , (CharType, Kprim__gt_Char)
      ] ++

    [ MkPrim Kprim__strLength StrLength (predTy StringType IntType) isTotal
    , MkPrim Kprim__strHead StrHead (predTy StringType CharType) notCovering
    , MkPrim Kprim__strTail StrTail (predTy StringType StringType) notCovering
    , MkPrim Kprim__strIndex StrIndex (constTy StringType IntType CharType) notCovering
    , MkPrim Kprim__strCons StrCons (constTy CharType StringType StringType) isTotal
    , MkPrim Kprim__strAppend StrAppend (arithTy StringType) isTotal
    , MkPrim Kprim__strReverse StrReverse (predTy StringType StringType) isTotal
    , MkPrim Kprim__strSubstr StrSubstr (constTy3 IntType IntType StringType StringType) isTotal
    , MkPrim Kprim__believe_me BelieveMe believeMeTy isTotal
    , MkPrim Kprim__crash Crash crashTy notCovering
    ] ++

    [ MkPrim Kprim__doubleExp DoubleExp doubleTy isTotal
    , MkPrim Kprim__doubleLog DoubleLog doubleTy isTotal
    , MkPrim Kprim__doublePow DoublePow (arithTy DoubleType) isTotal
    , MkPrim Kprim__doubleSin DoubleSin doubleTy isTotal
    , MkPrim Kprim__doubleCos DoubleCos doubleTy isTotal
    , MkPrim Kprim__doubleTan DoubleTan doubleTy isTotal
    , MkPrim Kprim__doubleASin DoubleASin doubleTy isTotal
    , MkPrim Kprim__doubleACos DoubleACos doubleTy isTotal
    , MkPrim Kprim__doubleATan DoubleATan doubleTy isTotal
    , MkPrim Kprim__doubleSqrt DoubleSqrt doubleTy isTotal
    , MkPrim Kprim__doubleFloor DoubleFloor doubleTy isTotal
    , MkPrim Kprim__doubleCeiling DoubleCeiling doubleTy isTotal
    ] ++

    casts
      [ (IntType, Int8Type, Kprim__cast_IntInt8)
      , (IntType, Int16Type, Kprim__cast_IntInt16)
      , (IntType, Int32Type, Kprim__cast_IntInt32)
      , (IntType, Int64Type, Kprim__cast_IntInt64)
      , (IntType, IntegerType, Kprim__cast_IntInteger)
      , (IntType, Bits8Type, Kprim__cast_IntBits8)
      , (IntType, Bits16Type, Kprim__cast_IntBits16)
      , (IntType, Bits32Type, Kprim__cast_IntBits32)
      , (IntType, Bits64Type, Kprim__cast_IntBits64)
      , (IntType, DoubleType, Kprim__cast_IntDouble)
      , (IntType, StringType, Kprim__cast_IntString)
      , (IntType, CharType, Kprim__cast_IntChar)
      , (Int8Type, IntType, Kprim__cast_Int8Int)
      , (Int8Type, Int16Type, Kprim__cast_Int8Int16)
      , (Int8Type, Int32Type, Kprim__cast_Int8Int32)
      , (Int8Type, Int64Type, Kprim__cast_Int8Int64)
      , (Int8Type, IntegerType, Kprim__cast_Int8Integer)
      , (Int8Type, Bits8Type, Kprim__cast_Int8Bits8)
      , (Int8Type, Bits16Type, Kprim__cast_Int8Bits16)
      , (Int8Type, Bits32Type, Kprim__cast_Int8Bits32)
      , (Int8Type, Bits64Type, Kprim__cast_Int8Bits64)
      , (Int8Type, DoubleType, Kprim__cast_Int8Double)
      , (Int8Type, StringType, Kprim__cast_Int8String)
      , (Int8Type, CharType, Kprim__cast_Int8Char)
      , (Int16Type, IntType, Kprim__cast_Int16Int)
      , (Int16Type, Int8Type, Kprim__cast_Int16Int8)
      , (Int16Type, Int32Type, Kprim__cast_Int16Int32)
      , (Int16Type, Int64Type, Kprim__cast_Int16Int64)
      , (Int16Type, IntegerType, Kprim__cast_Int16Integer)
      , (Int16Type, Bits8Type, Kprim__cast_Int16Bits8)
      , (Int16Type, Bits16Type, Kprim__cast_Int16Bits16)
      , (Int16Type, Bits32Type, Kprim__cast_Int16Bits32)
      , (Int16Type, Bits64Type, Kprim__cast_Int16Bits64)
      , (Int16Type, DoubleType, Kprim__cast_Int16Double)
      , (Int16Type, StringType, Kprim__cast_Int16String)
      , (Int16Type, CharType, Kprim__cast_Int16Char)
      , (Int32Type, IntType, Kprim__cast_Int32Int)
      , (Int32Type, Int8Type, Kprim__cast_Int32Int8)
      , (Int32Type, Int16Type, Kprim__cast_Int32Int16)
      , (Int32Type, Int64Type, Kprim__cast_Int32Int64)
      , (Int32Type, IntegerType, Kprim__cast_Int32Integer)
      , (Int32Type, Bits8Type, Kprim__cast_Int32Bits8)
      , (Int32Type, Bits16Type, Kprim__cast_Int32Bits16)
      , (Int32Type, Bits32Type, Kprim__cast_Int32Bits32)
      , (Int32Type, Bits64Type, Kprim__cast_Int32Bits64)
      , (Int32Type, DoubleType, Kprim__cast_Int32Double)
      , (Int32Type, StringType, Kprim__cast_Int32String)
      , (Int32Type, CharType, Kprim__cast_Int32Char)
      , (Int64Type, IntType, Kprim__cast_Int64Int)
      , (Int64Type, Int8Type, Kprim__cast_Int64Int8)
      , (Int64Type, Int16Type, Kprim__cast_Int64Int16)
      , (Int64Type, Int32Type, Kprim__cast_Int64Int32)
      , (Int64Type, IntegerType, Kprim__cast_Int64Integer)
      , (Int64Type, Bits8Type, Kprim__cast_Int64Bits8)
      , (Int64Type, Bits16Type, Kprim__cast_Int64Bits16)
      , (Int64Type, Bits32Type, Kprim__cast_Int64Bits32)
      , (Int64Type, Bits64Type, Kprim__cast_Int64Bits64)
      , (Int64Type, DoubleType, Kprim__cast_Int64Double)
      , (Int64Type, StringType, Kprim__cast_Int64String)
      , (Int64Type, CharType, Kprim__cast_Int64Char)
      , (IntegerType, IntType, Kprim__cast_IntegerInt)
      , (IntegerType, Int8Type, Kprim__cast_IntegerInt8)
      , (IntegerType, Int16Type, Kprim__cast_IntegerInt16)
      , (IntegerType, Int32Type, Kprim__cast_IntegerInt32)
      , (IntegerType, Int64Type, Kprim__cast_IntegerInt64)
      , (IntegerType, Bits8Type, Kprim__cast_IntegerBits8)
      , (IntegerType, Bits16Type, Kprim__cast_IntegerBits16)
      , (IntegerType, Bits32Type, Kprim__cast_IntegerBits32)
      , (IntegerType, Bits64Type, Kprim__cast_IntegerBits64)
      , (IntegerType, DoubleType, Kprim__cast_IntegerDouble)
      , (IntegerType, StringType, Kprim__cast_IntegerString)
      , (IntegerType, CharType, Kprim__cast_IntegerChar)
      , (Bits8Type, IntType, Kprim__cast_Bits8Int)
      , (Bits8Type, Int8Type, Kprim__cast_Bits8Int8)
      , (Bits8Type, Int16Type, Kprim__cast_Bits8Int16)
      , (Bits8Type, Int32Type, Kprim__cast_Bits8Int32)
      , (Bits8Type, Int64Type, Kprim__cast_Bits8Int64)
      , (Bits8Type, IntegerType, Kprim__cast_Bits8Integer)
      , (Bits8Type, Bits16Type, Kprim__cast_Bits8Bits16)
      , (Bits8Type, Bits32Type, Kprim__cast_Bits8Bits32)
      , (Bits8Type, Bits64Type, Kprim__cast_Bits8Bits64)
      , (Bits8Type, DoubleType, Kprim__cast_Bits8Double)
      , (Bits8Type, StringType, Kprim__cast_Bits8String)
      , (Bits8Type, CharType, Kprim__cast_Bits8Char)
      , (Bits16Type, IntType, Kprim__cast_Bits16Int)
      , (Bits16Type, Int8Type, Kprim__cast_Bits16Int8)
      , (Bits16Type, Int16Type, Kprim__cast_Bits16Int16)
      , (Bits16Type, Int32Type, Kprim__cast_Bits16Int32)
      , (Bits16Type, Int64Type, Kprim__cast_Bits16Int64)
      , (Bits16Type, IntegerType, Kprim__cast_Bits16Integer)
      , (Bits16Type, Bits8Type, Kprim__cast_Bits16Bits8)
      , (Bits16Type, Bits32Type, Kprim__cast_Bits16Bits32)
      , (Bits16Type, Bits64Type, Kprim__cast_Bits16Bits64)
      , (Bits16Type, DoubleType, Kprim__cast_Bits16Double)
      , (Bits16Type, StringType, Kprim__cast_Bits16String)
      , (Bits16Type, CharType, Kprim__cast_Bits16Char)
      , (Bits32Type, IntType, Kprim__cast_Bits32Int)
      , (Bits32Type, Int8Type, Kprim__cast_Bits32Int8)
      , (Bits32Type, Int16Type, Kprim__cast_Bits32Int16)
      , (Bits32Type, Int32Type, Kprim__cast_Bits32Int32)
      , (Bits32Type, Int64Type, Kprim__cast_Bits32Int64)
      , (Bits32Type, IntegerType, Kprim__cast_Bits32Integer)
      , (Bits32Type, Bits8Type, Kprim__cast_Bits32Bits8)
      , (Bits32Type, Bits16Type, Kprim__cast_Bits32Bits16)
      , (Bits32Type, Bits64Type, Kprim__cast_Bits32Bits64)
      , (Bits32Type, DoubleType, Kprim__cast_Bits32Double)
      , (Bits32Type, StringType, Kprim__cast_Bits32String)
      , (Bits32Type, CharType, Kprim__cast_Bits32Char)
      , (Bits64Type, IntType, Kprim__cast_Bits64Int)
      , (Bits64Type, Int8Type, Kprim__cast_Bits64Int8)
      , (Bits64Type, Int16Type, Kprim__cast_Bits64Int16)
      , (Bits64Type, Int32Type, Kprim__cast_Bits64Int32)
      , (Bits64Type, Int64Type, Kprim__cast_Bits64Int64)
      , (Bits64Type, IntegerType, Kprim__cast_Bits64Integer)
      , (Bits64Type, Bits8Type, Kprim__cast_Bits64Bits8)
      , (Bits64Type, Bits16Type, Kprim__cast_Bits64Bits16)
      , (Bits64Type, Bits32Type, Kprim__cast_Bits64Bits32)
      , (Bits64Type, DoubleType, Kprim__cast_Bits64Double)
      , (Bits64Type, StringType, Kprim__cast_Bits64String)
      , (Bits64Type, CharType, Kprim__cast_Bits64Char)
      , (DoubleType, IntType, Kprim__cast_DoubleInt)
      , (DoubleType, Int8Type, Kprim__cast_DoubleInt8)
      , (DoubleType, Int16Type, Kprim__cast_DoubleInt16)
      , (DoubleType, Int32Type, Kprim__cast_DoubleInt32)
      , (DoubleType, Int64Type, Kprim__cast_DoubleInt64)
      , (DoubleType, IntegerType, Kprim__cast_DoubleInteger)
      , (DoubleType, Bits8Type, Kprim__cast_DoubleBits8)
      , (DoubleType, Bits16Type, Kprim__cast_DoubleBits16)
      , (DoubleType, Bits32Type, Kprim__cast_DoubleBits32)
      , (DoubleType, Bits64Type, Kprim__cast_DoubleBits64)
      , (DoubleType, StringType, Kprim__cast_DoubleString)
      , (StringType, IntType, Kprim__cast_StringInt)
      , (StringType, Int8Type, Kprim__cast_StringInt8)
      , (StringType, Int16Type, Kprim__cast_StringInt16)
      , (StringType, Int32Type, Kprim__cast_StringInt32)
      , (StringType, Int64Type, Kprim__cast_StringInt64)
      , (StringType, IntegerType, Kprim__cast_StringInteger)
      , (StringType, Bits8Type, Kprim__cast_StringBits8)
      , (StringType, Bits16Type, Kprim__cast_StringBits16)
      , (StringType, Bits32Type, Kprim__cast_StringBits32)
      , (StringType, Bits64Type, Kprim__cast_StringBits64)
      , (StringType, DoubleType, Kprim__cast_StringDouble)
      , (CharType, IntType, Kprim__cast_CharInt)
      , (CharType, Int8Type, Kprim__cast_CharInt8)
      , (CharType, Int16Type, Kprim__cast_CharInt16)
      , (CharType, Int32Type, Kprim__cast_CharInt32)
      , (CharType, Int64Type, Kprim__cast_CharInt64)
      , (CharType, IntegerType, Kprim__cast_CharInteger)
      , (CharType, Bits8Type, Kprim__cast_CharBits8)
      , (CharType, Bits16Type, Kprim__cast_CharBits16)
      , (CharType, Bits32Type, Kprim__cast_CharBits32)
      , (CharType, Bits64Type, Kprim__cast_CharBits64)
      , (CharType, StringType, Kprim__cast_CharString)
      ]
