-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Core.Primitives

import Core.TT
import Core.Value

import Data.Vect

%default covering

-- A primitive the evaluator computes is the primitive itself, called by
-- its name: what `prim__add_Int` means while the compiler runs is what the
-- runtime that runs the compiler gives it, not an Idris program written to
-- agree with it. So each operation below applies `prim__...` of the same
-- name to the constants, and decides only whether it applies: a partial
-- primitive (division by zero, the head of an empty string) and a cast the
-- compiler has never folded stay applied.

public export
record Prim where
  constructor MkPrim
  {arity : Nat}
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
castString [NPrimVal fc (Db i)] = Just (NPrimVal fc (Str (prim__cast_DoubleString i)))
castString _ = Nothing

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
castInteger [NPrimVal fc (Db i)] = Just (NPrimVal fc (BI (prim__cast_DoubleInteger i)))
castInteger [NPrimVal fc (Str i)] = Just (NPrimVal fc (BI (prim__cast_StringInteger i)))
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
castInt [NPrimVal fc (Db i)] = Just (NPrimVal fc (I (prim__cast_DoubleInt i)))
castInt [NPrimVal fc (Ch i)] = Just (NPrimVal fc (I (prim__cast_CharInt i)))
castInt [NPrimVal fc (Str i)] = Just (NPrimVal fc (I (prim__cast_StringInt i)))
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
castDouble [NPrimVal fc (Str i)] = Just (NPrimVal fc (Db (prim__cast_StringDouble i)))
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

strHead : Vect 1 (NF vars) -> Maybe (NF vars)
strHead [NPrimVal fc (Str "")] = Nothing
strHead [NPrimVal fc (Str str)]
    = Just (NPrimVal fc (Ch (assert_total (prim__strHead str))))
strHead _ = Nothing

strTail : Vect 1 (NF vars) -> Maybe (NF vars)
strTail [NPrimVal fc (Str "")] = Nothing
strTail [NPrimVal fc (Str str)]
    = Just (NPrimVal fc (Str (assert_total (prim__strTail str))))
strTail _ = Nothing

strIndex : Vect 2 (NF vars) -> Maybe (NF vars)
strIndex [NPrimVal fc (Str str), NPrimVal _ (I i)]
    = if i >= 0 && integerToNat (cast i) < length str
         then Just (NPrimVal fc (Ch (assert_total (prim__strIndex str i))))
         else Nothing
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
add (Db x) (Db y) = pure $ Db (prim__add_Double x y)
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
sub (Db x) (Db y) = pure $ Db (prim__sub_Double x y)
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
mul (Db x) (Db y) = pure $ Db (prim__mul_Double x y)
mul _ _ = Nothing

div : Constant -> Constant -> Maybe Constant
div (BI x) (BI 0) = Nothing
div (BI x) (BI y) = pure $ BI (assert_total (prim__div_Integer x y))
div (I x) (I 0) = Nothing
div (I x) (I y) = pure $ I (assert_total (prim__div_Int x y))
div (I8 x) (I8 0) = Nothing
div (I8 x) (I8 y) = pure $ I8 (assert_total (prim__div_Int8 x y))
div (I16 x) (I16 0) = Nothing
div (I16 x) (I16 y) = pure $ I16 (assert_total (prim__div_Int16 x y))
div (I32 x) (I32 0) = Nothing
div (I32 x) (I32 y) = pure $ I32 (assert_total (prim__div_Int32 x y))
div (I64 x) (I64 0) = Nothing
div (I64 x) (I64 y) = pure $ I64 (assert_total (prim__div_Int64 x y))
div (B8 x) (B8 0) = Nothing
div (B8 x) (B8 y) = pure $ B8 (assert_total (prim__div_Bits8 x y))
div (B16 x) (B16 0) = Nothing
div (B16 x) (B16 y) = pure $ B16 (assert_total (prim__div_Bits16 x y))
div (B32 x) (B32 0) = Nothing
div (B32 x) (B32 y) = pure $ B32 (assert_total (prim__div_Bits32 x y))
div (B64 x) (B64 0) = Nothing
div (B64 x) (B64 y) = pure $ B64 (assert_total (prim__div_Bits64 x y))
div (Db x) (Db y) = pure $ Db (assert_total (prim__div_Double x y))
div _ _ = Nothing

mod : Constant -> Constant -> Maybe Constant
mod (BI x) (BI 0) = Nothing
mod (BI x) (BI y) = pure $ BI (assert_total (prim__mod_Integer x y))
mod (I x) (I 0) = Nothing
mod (I x) (I y) = pure $ I (assert_total (prim__mod_Int x y))
mod (I8 x) (I8 0) = Nothing
mod (I8 x) (I8 y) = pure $ I8 (assert_total (prim__mod_Int8 x y))
mod (I16 x) (I16 0) = Nothing
mod (I16 x) (I16 y) = pure $ I16 (assert_total (prim__mod_Int16 x y))
mod (I32 x) (I32 0) = Nothing
mod (I32 x) (I32 y) = pure $ I32 (assert_total (prim__mod_Int32 x y))
mod (I64 x) (I64 0) = Nothing
mod (I64 x) (I64 y) = pure $ I64 (assert_total (prim__mod_Int64 x y))
mod (B8 x) (B8 0) = Nothing
mod (B8 x) (B8 y) = pure $ B8 (assert_total (prim__mod_Bits8 x y))
mod (B16 x) (B16 0) = Nothing
mod (B16 x) (B16 y) = pure $ B16 (assert_total (prim__mod_Bits16 x y))
mod (B32 x) (B32 0) = Nothing
mod (B32 x) (B32 y) = pure $ B32 (assert_total (prim__mod_Bits32 x y))
mod (B64 x) (B64 0) = Nothing
mod (B64 x) (B64 y) = pure $ B64 (assert_total (prim__mod_Bits64 x y))
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
neg (Db x) = pure $ Db (prim__negate_Double x)
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

doubleOp : (Double -> Double) -> Vect 1 (NF vars) -> Maybe (NF vars)
doubleOp f [NPrimVal fc (Db x)] = Just (NPrimVal fc (Db (f x)))
doubleOp f _ = Nothing

doubleExp : Vect 1 (NF vars) -> Maybe (NF vars)
doubleExp = doubleOp (\x => prim__doubleExp x)

doubleLog : Vect 1 (NF vars) -> Maybe (NF vars)
doubleLog = doubleOp (\x => prim__doubleLog x)

doublePow : {vars : _ } -> Vect 2 (NF vars) -> Maybe (NF vars)
doublePow = binOp pow'
    where pow' : Constant -> Constant -> Maybe Constant
          pow' (Db x) (Db y) = pure $ Db (prim__doublePow x y)
          pow' _ _ = Nothing

doubleSin : Vect 1 (NF vars) -> Maybe (NF vars)
doubleSin = doubleOp (\x => prim__doubleSin x)

doubleCos : Vect 1 (NF vars) -> Maybe (NF vars)
doubleCos = doubleOp (\x => prim__doubleCos x)

doubleTan : Vect 1 (NF vars) -> Maybe (NF vars)
doubleTan = doubleOp (\x => prim__doubleTan x)

doubleASin : Vect 1 (NF vars) -> Maybe (NF vars)
doubleASin = doubleOp (\x => prim__doubleASin x)

doubleACos : Vect 1 (NF vars) -> Maybe (NF vars)
doubleACos = doubleOp (\x => prim__doubleACos x)

doubleATan : Vect 1 (NF vars) -> Maybe (NF vars)
doubleATan = doubleOp (\x => prim__doubleATan x)

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

getOp DoubleExp = doubleExp
getOp DoubleLog = doubleLog
getOp DoublePow = doublePow
getOp DoubleSin = doubleSin
getOp DoubleCos = doubleCos
getOp DoubleTan = doubleTan
getOp DoubleASin = doubleASin
getOp DoubleACos = doubleACos
getOp DoubleATan = doubleATan
getOp DoubleSqrt = doubleSqrt
getOp DoubleFloor = doubleFloor
getOp DoubleCeiling = doubleCeiling

getOp (Cast _ y) = castTo y
getOp BelieveMe = believeMe

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

||| A primitive's name: `prim__`, its operation, and the types it is at as
||| `show` spells them. The operations and types are a closed set, so every
||| name is a known identifier, a constant, and naming a primitive builds no
||| text.
export
opName : {0 arity : Nat} -> PrimFn arity -> Name
opName (Add IntType)                  = knownUN Kprim__add_Int
opName (Add Int8Type)                 = knownUN Kprim__add_Int8
opName (Add Int16Type)                = knownUN Kprim__add_Int16
opName (Add Int32Type)                = knownUN Kprim__add_Int32
opName (Add Int64Type)                = knownUN Kprim__add_Int64
opName (Add IntegerType)              = knownUN Kprim__add_Integer
opName (Add Bits8Type)                = knownUN Kprim__add_Bits8
opName (Add Bits16Type)               = knownUN Kprim__add_Bits16
opName (Add Bits32Type)               = knownUN Kprim__add_Bits32
opName (Add Bits64Type)               = knownUN Kprim__add_Bits64
opName (Add StringType)               = knownUN Kprim__add_String
opName (Add CharType)                 = knownUN Kprim__add_Char
opName (Add DoubleType)               = knownUN Kprim__add_Double
opName (Add WorldType)                = knownUN Kprim__add_PercentWorld

opName (Sub IntType)                  = knownUN Kprim__sub_Int
opName (Sub Int8Type)                 = knownUN Kprim__sub_Int8
opName (Sub Int16Type)                = knownUN Kprim__sub_Int16
opName (Sub Int32Type)                = knownUN Kprim__sub_Int32
opName (Sub Int64Type)                = knownUN Kprim__sub_Int64
opName (Sub IntegerType)              = knownUN Kprim__sub_Integer
opName (Sub Bits8Type)                = knownUN Kprim__sub_Bits8
opName (Sub Bits16Type)               = knownUN Kprim__sub_Bits16
opName (Sub Bits32Type)               = knownUN Kprim__sub_Bits32
opName (Sub Bits64Type)               = knownUN Kprim__sub_Bits64
opName (Sub StringType)               = knownUN Kprim__sub_String
opName (Sub CharType)                 = knownUN Kprim__sub_Char
opName (Sub DoubleType)               = knownUN Kprim__sub_Double
opName (Sub WorldType)                = knownUN Kprim__sub_PercentWorld

opName (Mul IntType)                  = knownUN Kprim__mul_Int
opName (Mul Int8Type)                 = knownUN Kprim__mul_Int8
opName (Mul Int16Type)                = knownUN Kprim__mul_Int16
opName (Mul Int32Type)                = knownUN Kprim__mul_Int32
opName (Mul Int64Type)                = knownUN Kprim__mul_Int64
opName (Mul IntegerType)              = knownUN Kprim__mul_Integer
opName (Mul Bits8Type)                = knownUN Kprim__mul_Bits8
opName (Mul Bits16Type)               = knownUN Kprim__mul_Bits16
opName (Mul Bits32Type)               = knownUN Kprim__mul_Bits32
opName (Mul Bits64Type)               = knownUN Kprim__mul_Bits64
opName (Mul StringType)               = knownUN Kprim__mul_String
opName (Mul CharType)                 = knownUN Kprim__mul_Char
opName (Mul DoubleType)               = knownUN Kprim__mul_Double
opName (Mul WorldType)                = knownUN Kprim__mul_PercentWorld

opName (Div IntType)                  = knownUN Kprim__div_Int
opName (Div Int8Type)                 = knownUN Kprim__div_Int8
opName (Div Int16Type)                = knownUN Kprim__div_Int16
opName (Div Int32Type)                = knownUN Kprim__div_Int32
opName (Div Int64Type)                = knownUN Kprim__div_Int64
opName (Div IntegerType)              = knownUN Kprim__div_Integer
opName (Div Bits8Type)                = knownUN Kprim__div_Bits8
opName (Div Bits16Type)               = knownUN Kprim__div_Bits16
opName (Div Bits32Type)               = knownUN Kprim__div_Bits32
opName (Div Bits64Type)               = knownUN Kprim__div_Bits64
opName (Div StringType)               = knownUN Kprim__div_String
opName (Div CharType)                 = knownUN Kprim__div_Char
opName (Div DoubleType)               = knownUN Kprim__div_Double
opName (Div WorldType)                = knownUN Kprim__div_PercentWorld

opName (Mod IntType)                  = knownUN Kprim__mod_Int
opName (Mod Int8Type)                 = knownUN Kprim__mod_Int8
opName (Mod Int16Type)                = knownUN Kprim__mod_Int16
opName (Mod Int32Type)                = knownUN Kprim__mod_Int32
opName (Mod Int64Type)                = knownUN Kprim__mod_Int64
opName (Mod IntegerType)              = knownUN Kprim__mod_Integer
opName (Mod Bits8Type)                = knownUN Kprim__mod_Bits8
opName (Mod Bits16Type)               = knownUN Kprim__mod_Bits16
opName (Mod Bits32Type)               = knownUN Kprim__mod_Bits32
opName (Mod Bits64Type)               = knownUN Kprim__mod_Bits64
opName (Mod StringType)               = knownUN Kprim__mod_String
opName (Mod CharType)                 = knownUN Kprim__mod_Char
opName (Mod DoubleType)               = knownUN Kprim__mod_Double
opName (Mod WorldType)                = knownUN Kprim__mod_PercentWorld

opName (Neg IntType)                  = knownUN Kprim__negate_Int
opName (Neg Int8Type)                 = knownUN Kprim__negate_Int8
opName (Neg Int16Type)                = knownUN Kprim__negate_Int16
opName (Neg Int32Type)                = knownUN Kprim__negate_Int32
opName (Neg Int64Type)                = knownUN Kprim__negate_Int64
opName (Neg IntegerType)              = knownUN Kprim__negate_Integer
opName (Neg Bits8Type)                = knownUN Kprim__negate_Bits8
opName (Neg Bits16Type)               = knownUN Kprim__negate_Bits16
opName (Neg Bits32Type)               = knownUN Kprim__negate_Bits32
opName (Neg Bits64Type)               = knownUN Kprim__negate_Bits64
opName (Neg StringType)               = knownUN Kprim__negate_String
opName (Neg CharType)                 = knownUN Kprim__negate_Char
opName (Neg DoubleType)               = knownUN Kprim__negate_Double
opName (Neg WorldType)                = knownUN Kprim__negate_PercentWorld

opName (ShiftL IntType)               = knownUN Kprim__shl_Int
opName (ShiftL Int8Type)              = knownUN Kprim__shl_Int8
opName (ShiftL Int16Type)             = knownUN Kprim__shl_Int16
opName (ShiftL Int32Type)             = knownUN Kprim__shl_Int32
opName (ShiftL Int64Type)             = knownUN Kprim__shl_Int64
opName (ShiftL IntegerType)           = knownUN Kprim__shl_Integer
opName (ShiftL Bits8Type)             = knownUN Kprim__shl_Bits8
opName (ShiftL Bits16Type)            = knownUN Kprim__shl_Bits16
opName (ShiftL Bits32Type)            = knownUN Kprim__shl_Bits32
opName (ShiftL Bits64Type)            = knownUN Kprim__shl_Bits64
opName (ShiftL StringType)            = knownUN Kprim__shl_String
opName (ShiftL CharType)              = knownUN Kprim__shl_Char
opName (ShiftL DoubleType)            = knownUN Kprim__shl_Double
opName (ShiftL WorldType)             = knownUN Kprim__shl_PercentWorld

opName (ShiftR IntType)               = knownUN Kprim__shr_Int
opName (ShiftR Int8Type)              = knownUN Kprim__shr_Int8
opName (ShiftR Int16Type)             = knownUN Kprim__shr_Int16
opName (ShiftR Int32Type)             = knownUN Kprim__shr_Int32
opName (ShiftR Int64Type)             = knownUN Kprim__shr_Int64
opName (ShiftR IntegerType)           = knownUN Kprim__shr_Integer
opName (ShiftR Bits8Type)             = knownUN Kprim__shr_Bits8
opName (ShiftR Bits16Type)            = knownUN Kprim__shr_Bits16
opName (ShiftR Bits32Type)            = knownUN Kprim__shr_Bits32
opName (ShiftR Bits64Type)            = knownUN Kprim__shr_Bits64
opName (ShiftR StringType)            = knownUN Kprim__shr_String
opName (ShiftR CharType)              = knownUN Kprim__shr_Char
opName (ShiftR DoubleType)            = knownUN Kprim__shr_Double
opName (ShiftR WorldType)             = knownUN Kprim__shr_PercentWorld

opName (BAnd IntType)                 = knownUN Kprim__and_Int
opName (BAnd Int8Type)                = knownUN Kprim__and_Int8
opName (BAnd Int16Type)               = knownUN Kprim__and_Int16
opName (BAnd Int32Type)               = knownUN Kprim__and_Int32
opName (BAnd Int64Type)               = knownUN Kprim__and_Int64
opName (BAnd IntegerType)             = knownUN Kprim__and_Integer
opName (BAnd Bits8Type)               = knownUN Kprim__and_Bits8
opName (BAnd Bits16Type)              = knownUN Kprim__and_Bits16
opName (BAnd Bits32Type)              = knownUN Kprim__and_Bits32
opName (BAnd Bits64Type)              = knownUN Kprim__and_Bits64
opName (BAnd StringType)              = knownUN Kprim__and_String
opName (BAnd CharType)                = knownUN Kprim__and_Char
opName (BAnd DoubleType)              = knownUN Kprim__and_Double
opName (BAnd WorldType)               = knownUN Kprim__and_PercentWorld

opName (BOr IntType)                  = knownUN Kprim__or_Int
opName (BOr Int8Type)                 = knownUN Kprim__or_Int8
opName (BOr Int16Type)                = knownUN Kprim__or_Int16
opName (BOr Int32Type)                = knownUN Kprim__or_Int32
opName (BOr Int64Type)                = knownUN Kprim__or_Int64
opName (BOr IntegerType)              = knownUN Kprim__or_Integer
opName (BOr Bits8Type)                = knownUN Kprim__or_Bits8
opName (BOr Bits16Type)               = knownUN Kprim__or_Bits16
opName (BOr Bits32Type)               = knownUN Kprim__or_Bits32
opName (BOr Bits64Type)               = knownUN Kprim__or_Bits64
opName (BOr StringType)               = knownUN Kprim__or_String
opName (BOr CharType)                 = knownUN Kprim__or_Char
opName (BOr DoubleType)               = knownUN Kprim__or_Double
opName (BOr WorldType)                = knownUN Kprim__or_PercentWorld

opName (BXOr IntType)                 = knownUN Kprim__xor_Int
opName (BXOr Int8Type)                = knownUN Kprim__xor_Int8
opName (BXOr Int16Type)               = knownUN Kprim__xor_Int16
opName (BXOr Int32Type)               = knownUN Kprim__xor_Int32
opName (BXOr Int64Type)               = knownUN Kprim__xor_Int64
opName (BXOr IntegerType)             = knownUN Kprim__xor_Integer
opName (BXOr Bits8Type)               = knownUN Kprim__xor_Bits8
opName (BXOr Bits16Type)              = knownUN Kprim__xor_Bits16
opName (BXOr Bits32Type)              = knownUN Kprim__xor_Bits32
opName (BXOr Bits64Type)              = knownUN Kprim__xor_Bits64
opName (BXOr StringType)              = knownUN Kprim__xor_String
opName (BXOr CharType)                = knownUN Kprim__xor_Char
opName (BXOr DoubleType)              = knownUN Kprim__xor_Double
opName (BXOr WorldType)               = knownUN Kprim__xor_PercentWorld

opName (LT IntType)                   = knownUN Kprim__lt_Int
opName (LT Int8Type)                  = knownUN Kprim__lt_Int8
opName (LT Int16Type)                 = knownUN Kprim__lt_Int16
opName (LT Int32Type)                 = knownUN Kprim__lt_Int32
opName (LT Int64Type)                 = knownUN Kprim__lt_Int64
opName (LT IntegerType)               = knownUN Kprim__lt_Integer
opName (LT Bits8Type)                 = knownUN Kprim__lt_Bits8
opName (LT Bits16Type)                = knownUN Kprim__lt_Bits16
opName (LT Bits32Type)                = knownUN Kprim__lt_Bits32
opName (LT Bits64Type)                = knownUN Kprim__lt_Bits64
opName (LT StringType)                = knownUN Kprim__lt_String
opName (LT CharType)                  = knownUN Kprim__lt_Char
opName (LT DoubleType)                = knownUN Kprim__lt_Double
opName (LT WorldType)                 = knownUN Kprim__lt_PercentWorld

opName (LTE IntType)                  = knownUN Kprim__lte_Int
opName (LTE Int8Type)                 = knownUN Kprim__lte_Int8
opName (LTE Int16Type)                = knownUN Kprim__lte_Int16
opName (LTE Int32Type)                = knownUN Kprim__lte_Int32
opName (LTE Int64Type)                = knownUN Kprim__lte_Int64
opName (LTE IntegerType)              = knownUN Kprim__lte_Integer
opName (LTE Bits8Type)                = knownUN Kprim__lte_Bits8
opName (LTE Bits16Type)               = knownUN Kprim__lte_Bits16
opName (LTE Bits32Type)               = knownUN Kprim__lte_Bits32
opName (LTE Bits64Type)               = knownUN Kprim__lte_Bits64
opName (LTE StringType)               = knownUN Kprim__lte_String
opName (LTE CharType)                 = knownUN Kprim__lte_Char
opName (LTE DoubleType)               = knownUN Kprim__lte_Double
opName (LTE WorldType)                = knownUN Kprim__lte_PercentWorld

opName (EQ IntType)                   = knownUN Kprim__eq_Int
opName (EQ Int8Type)                  = knownUN Kprim__eq_Int8
opName (EQ Int16Type)                 = knownUN Kprim__eq_Int16
opName (EQ Int32Type)                 = knownUN Kprim__eq_Int32
opName (EQ Int64Type)                 = knownUN Kprim__eq_Int64
opName (EQ IntegerType)               = knownUN Kprim__eq_Integer
opName (EQ Bits8Type)                 = knownUN Kprim__eq_Bits8
opName (EQ Bits16Type)                = knownUN Kprim__eq_Bits16
opName (EQ Bits32Type)                = knownUN Kprim__eq_Bits32
opName (EQ Bits64Type)                = knownUN Kprim__eq_Bits64
opName (EQ StringType)                = knownUN Kprim__eq_String
opName (EQ CharType)                  = knownUN Kprim__eq_Char
opName (EQ DoubleType)                = knownUN Kprim__eq_Double
opName (EQ WorldType)                 = knownUN Kprim__eq_PercentWorld

opName (GTE IntType)                  = knownUN Kprim__gte_Int
opName (GTE Int8Type)                 = knownUN Kprim__gte_Int8
opName (GTE Int16Type)                = knownUN Kprim__gte_Int16
opName (GTE Int32Type)                = knownUN Kprim__gte_Int32
opName (GTE Int64Type)                = knownUN Kprim__gte_Int64
opName (GTE IntegerType)              = knownUN Kprim__gte_Integer
opName (GTE Bits8Type)                = knownUN Kprim__gte_Bits8
opName (GTE Bits16Type)               = knownUN Kprim__gte_Bits16
opName (GTE Bits32Type)               = knownUN Kprim__gte_Bits32
opName (GTE Bits64Type)               = knownUN Kprim__gte_Bits64
opName (GTE StringType)               = knownUN Kprim__gte_String
opName (GTE CharType)                 = knownUN Kprim__gte_Char
opName (GTE DoubleType)               = knownUN Kprim__gte_Double
opName (GTE WorldType)                = knownUN Kprim__gte_PercentWorld

opName (GT IntType)                   = knownUN Kprim__gt_Int
opName (GT Int8Type)                  = knownUN Kprim__gt_Int8
opName (GT Int16Type)                 = knownUN Kprim__gt_Int16
opName (GT Int32Type)                 = knownUN Kprim__gt_Int32
opName (GT Int64Type)                 = knownUN Kprim__gt_Int64
opName (GT IntegerType)               = knownUN Kprim__gt_Integer
opName (GT Bits8Type)                 = knownUN Kprim__gt_Bits8
opName (GT Bits16Type)                = knownUN Kprim__gt_Bits16
opName (GT Bits32Type)                = knownUN Kprim__gt_Bits32
opName (GT Bits64Type)                = knownUN Kprim__gt_Bits64
opName (GT StringType)                = knownUN Kprim__gt_String
opName (GT CharType)                  = knownUN Kprim__gt_Char
opName (GT DoubleType)                = knownUN Kprim__gt_Double
opName (GT WorldType)                 = knownUN Kprim__gt_PercentWorld

opName StrLength                      = knownUN Kprim__strLength
opName StrHead                        = knownUN Kprim__strHead
opName StrTail                        = knownUN Kprim__strTail
opName StrIndex                       = knownUN Kprim__strIndex
opName StrCons                        = knownUN Kprim__strCons
opName StrAppend                      = knownUN Kprim__strAppend
opName StrReverse                     = knownUN Kprim__strReverse
opName StrSubstr                      = knownUN Kprim__strSubstr
opName DoubleExp                      = knownUN Kprim__doubleExp
opName DoubleLog                      = knownUN Kprim__doubleLog
opName DoublePow                      = knownUN Kprim__doublePow
opName DoubleSin                      = knownUN Kprim__doubleSin
opName DoubleCos                      = knownUN Kprim__doubleCos
opName DoubleTan                      = knownUN Kprim__doubleTan
opName DoubleASin                     = knownUN Kprim__doubleASin
opName DoubleACos                     = knownUN Kprim__doubleACos
opName DoubleATan                     = knownUN Kprim__doubleATan
opName DoubleSqrt                     = knownUN Kprim__doubleSqrt
opName DoubleFloor                    = knownUN Kprim__doubleFloor
opName DoubleCeiling                  = knownUN Kprim__doubleCeiling

opName (Cast IntType IntType)         = knownUN Kprim__cast_IntInt
opName (Cast IntType Int8Type)        = knownUN Kprim__cast_IntInt8
opName (Cast IntType Int16Type)       = knownUN Kprim__cast_IntInt16
opName (Cast IntType Int32Type)       = knownUN Kprim__cast_IntInt32
opName (Cast IntType Int64Type)       = knownUN Kprim__cast_IntInt64
opName (Cast IntType IntegerType)     = knownUN Kprim__cast_IntInteger
opName (Cast IntType Bits8Type)       = knownUN Kprim__cast_IntBits8
opName (Cast IntType Bits16Type)      = knownUN Kprim__cast_IntBits16
opName (Cast IntType Bits32Type)      = knownUN Kprim__cast_IntBits32
opName (Cast IntType Bits64Type)      = knownUN Kprim__cast_IntBits64
opName (Cast IntType StringType)      = knownUN Kprim__cast_IntString
opName (Cast IntType CharType)        = knownUN Kprim__cast_IntChar
opName (Cast IntType DoubleType)      = knownUN Kprim__cast_IntDouble
opName (Cast IntType WorldType)       = knownUN Kprim__cast_IntPercentWorld
opName (Cast Int8Type IntType)        = knownUN Kprim__cast_Int8Int
opName (Cast Int8Type Int8Type)       = knownUN Kprim__cast_Int8Int8
opName (Cast Int8Type Int16Type)      = knownUN Kprim__cast_Int8Int16
opName (Cast Int8Type Int32Type)      = knownUN Kprim__cast_Int8Int32
opName (Cast Int8Type Int64Type)      = knownUN Kprim__cast_Int8Int64
opName (Cast Int8Type IntegerType)    = knownUN Kprim__cast_Int8Integer
opName (Cast Int8Type Bits8Type)      = knownUN Kprim__cast_Int8Bits8
opName (Cast Int8Type Bits16Type)     = knownUN Kprim__cast_Int8Bits16
opName (Cast Int8Type Bits32Type)     = knownUN Kprim__cast_Int8Bits32
opName (Cast Int8Type Bits64Type)     = knownUN Kprim__cast_Int8Bits64
opName (Cast Int8Type StringType)     = knownUN Kprim__cast_Int8String
opName (Cast Int8Type CharType)       = knownUN Kprim__cast_Int8Char
opName (Cast Int8Type DoubleType)     = knownUN Kprim__cast_Int8Double
opName (Cast Int8Type WorldType)      = knownUN Kprim__cast_Int8PercentWorld
opName (Cast Int16Type IntType)       = knownUN Kprim__cast_Int16Int
opName (Cast Int16Type Int8Type)      = knownUN Kprim__cast_Int16Int8
opName (Cast Int16Type Int16Type)     = knownUN Kprim__cast_Int16Int16
opName (Cast Int16Type Int32Type)     = knownUN Kprim__cast_Int16Int32
opName (Cast Int16Type Int64Type)     = knownUN Kprim__cast_Int16Int64
opName (Cast Int16Type IntegerType)   = knownUN Kprim__cast_Int16Integer
opName (Cast Int16Type Bits8Type)     = knownUN Kprim__cast_Int16Bits8
opName (Cast Int16Type Bits16Type)    = knownUN Kprim__cast_Int16Bits16
opName (Cast Int16Type Bits32Type)    = knownUN Kprim__cast_Int16Bits32
opName (Cast Int16Type Bits64Type)    = knownUN Kprim__cast_Int16Bits64
opName (Cast Int16Type StringType)    = knownUN Kprim__cast_Int16String
opName (Cast Int16Type CharType)      = knownUN Kprim__cast_Int16Char
opName (Cast Int16Type DoubleType)    = knownUN Kprim__cast_Int16Double
opName (Cast Int16Type WorldType)     = knownUN Kprim__cast_Int16PercentWorld
opName (Cast Int32Type IntType)       = knownUN Kprim__cast_Int32Int
opName (Cast Int32Type Int8Type)      = knownUN Kprim__cast_Int32Int8
opName (Cast Int32Type Int16Type)     = knownUN Kprim__cast_Int32Int16
opName (Cast Int32Type Int32Type)     = knownUN Kprim__cast_Int32Int32
opName (Cast Int32Type Int64Type)     = knownUN Kprim__cast_Int32Int64
opName (Cast Int32Type IntegerType)   = knownUN Kprim__cast_Int32Integer
opName (Cast Int32Type Bits8Type)     = knownUN Kprim__cast_Int32Bits8
opName (Cast Int32Type Bits16Type)    = knownUN Kprim__cast_Int32Bits16
opName (Cast Int32Type Bits32Type)    = knownUN Kprim__cast_Int32Bits32
opName (Cast Int32Type Bits64Type)    = knownUN Kprim__cast_Int32Bits64
opName (Cast Int32Type StringType)    = knownUN Kprim__cast_Int32String
opName (Cast Int32Type CharType)      = knownUN Kprim__cast_Int32Char
opName (Cast Int32Type DoubleType)    = knownUN Kprim__cast_Int32Double
opName (Cast Int32Type WorldType)     = knownUN Kprim__cast_Int32PercentWorld
opName (Cast Int64Type IntType)       = knownUN Kprim__cast_Int64Int
opName (Cast Int64Type Int8Type)      = knownUN Kprim__cast_Int64Int8
opName (Cast Int64Type Int16Type)     = knownUN Kprim__cast_Int64Int16
opName (Cast Int64Type Int32Type)     = knownUN Kprim__cast_Int64Int32
opName (Cast Int64Type Int64Type)     = knownUN Kprim__cast_Int64Int64
opName (Cast Int64Type IntegerType)   = knownUN Kprim__cast_Int64Integer
opName (Cast Int64Type Bits8Type)     = knownUN Kprim__cast_Int64Bits8
opName (Cast Int64Type Bits16Type)    = knownUN Kprim__cast_Int64Bits16
opName (Cast Int64Type Bits32Type)    = knownUN Kprim__cast_Int64Bits32
opName (Cast Int64Type Bits64Type)    = knownUN Kprim__cast_Int64Bits64
opName (Cast Int64Type StringType)    = knownUN Kprim__cast_Int64String
opName (Cast Int64Type CharType)      = knownUN Kprim__cast_Int64Char
opName (Cast Int64Type DoubleType)    = knownUN Kprim__cast_Int64Double
opName (Cast Int64Type WorldType)     = knownUN Kprim__cast_Int64PercentWorld
opName (Cast IntegerType IntType)     = knownUN Kprim__cast_IntegerInt
opName (Cast IntegerType Int8Type)    = knownUN Kprim__cast_IntegerInt8
opName (Cast IntegerType Int16Type)   = knownUN Kprim__cast_IntegerInt16
opName (Cast IntegerType Int32Type)   = knownUN Kprim__cast_IntegerInt32
opName (Cast IntegerType Int64Type)   = knownUN Kprim__cast_IntegerInt64
opName (Cast IntegerType IntegerType) = knownUN Kprim__cast_IntegerInteger
opName (Cast IntegerType Bits8Type)   = knownUN Kprim__cast_IntegerBits8
opName (Cast IntegerType Bits16Type)  = knownUN Kprim__cast_IntegerBits16
opName (Cast IntegerType Bits32Type)  = knownUN Kprim__cast_IntegerBits32
opName (Cast IntegerType Bits64Type)  = knownUN Kprim__cast_IntegerBits64
opName (Cast IntegerType StringType)  = knownUN Kprim__cast_IntegerString
opName (Cast IntegerType CharType)    = knownUN Kprim__cast_IntegerChar
opName (Cast IntegerType DoubleType)  = knownUN Kprim__cast_IntegerDouble
opName (Cast IntegerType WorldType)   = knownUN Kprim__cast_IntegerPercentWorld
opName (Cast Bits8Type IntType)       = knownUN Kprim__cast_Bits8Int
opName (Cast Bits8Type Int8Type)      = knownUN Kprim__cast_Bits8Int8
opName (Cast Bits8Type Int16Type)     = knownUN Kprim__cast_Bits8Int16
opName (Cast Bits8Type Int32Type)     = knownUN Kprim__cast_Bits8Int32
opName (Cast Bits8Type Int64Type)     = knownUN Kprim__cast_Bits8Int64
opName (Cast Bits8Type IntegerType)   = knownUN Kprim__cast_Bits8Integer
opName (Cast Bits8Type Bits8Type)     = knownUN Kprim__cast_Bits8Bits8
opName (Cast Bits8Type Bits16Type)    = knownUN Kprim__cast_Bits8Bits16
opName (Cast Bits8Type Bits32Type)    = knownUN Kprim__cast_Bits8Bits32
opName (Cast Bits8Type Bits64Type)    = knownUN Kprim__cast_Bits8Bits64
opName (Cast Bits8Type StringType)    = knownUN Kprim__cast_Bits8String
opName (Cast Bits8Type CharType)      = knownUN Kprim__cast_Bits8Char
opName (Cast Bits8Type DoubleType)    = knownUN Kprim__cast_Bits8Double
opName (Cast Bits8Type WorldType)     = knownUN Kprim__cast_Bits8PercentWorld
opName (Cast Bits16Type IntType)      = knownUN Kprim__cast_Bits16Int
opName (Cast Bits16Type Int8Type)     = knownUN Kprim__cast_Bits16Int8
opName (Cast Bits16Type Int16Type)    = knownUN Kprim__cast_Bits16Int16
opName (Cast Bits16Type Int32Type)    = knownUN Kprim__cast_Bits16Int32
opName (Cast Bits16Type Int64Type)    = knownUN Kprim__cast_Bits16Int64
opName (Cast Bits16Type IntegerType)  = knownUN Kprim__cast_Bits16Integer
opName (Cast Bits16Type Bits8Type)    = knownUN Kprim__cast_Bits16Bits8
opName (Cast Bits16Type Bits16Type)   = knownUN Kprim__cast_Bits16Bits16
opName (Cast Bits16Type Bits32Type)   = knownUN Kprim__cast_Bits16Bits32
opName (Cast Bits16Type Bits64Type)   = knownUN Kprim__cast_Bits16Bits64
opName (Cast Bits16Type StringType)   = knownUN Kprim__cast_Bits16String
opName (Cast Bits16Type CharType)     = knownUN Kprim__cast_Bits16Char
opName (Cast Bits16Type DoubleType)   = knownUN Kprim__cast_Bits16Double
opName (Cast Bits16Type WorldType)    = knownUN Kprim__cast_Bits16PercentWorld
opName (Cast Bits32Type IntType)      = knownUN Kprim__cast_Bits32Int
opName (Cast Bits32Type Int8Type)     = knownUN Kprim__cast_Bits32Int8
opName (Cast Bits32Type Int16Type)    = knownUN Kprim__cast_Bits32Int16
opName (Cast Bits32Type Int32Type)    = knownUN Kprim__cast_Bits32Int32
opName (Cast Bits32Type Int64Type)    = knownUN Kprim__cast_Bits32Int64
opName (Cast Bits32Type IntegerType)  = knownUN Kprim__cast_Bits32Integer
opName (Cast Bits32Type Bits8Type)    = knownUN Kprim__cast_Bits32Bits8
opName (Cast Bits32Type Bits16Type)   = knownUN Kprim__cast_Bits32Bits16
opName (Cast Bits32Type Bits32Type)   = knownUN Kprim__cast_Bits32Bits32
opName (Cast Bits32Type Bits64Type)   = knownUN Kprim__cast_Bits32Bits64
opName (Cast Bits32Type StringType)   = knownUN Kprim__cast_Bits32String
opName (Cast Bits32Type CharType)     = knownUN Kprim__cast_Bits32Char
opName (Cast Bits32Type DoubleType)   = knownUN Kprim__cast_Bits32Double
opName (Cast Bits32Type WorldType)    = knownUN Kprim__cast_Bits32PercentWorld
opName (Cast Bits64Type IntType)      = knownUN Kprim__cast_Bits64Int
opName (Cast Bits64Type Int8Type)     = knownUN Kprim__cast_Bits64Int8
opName (Cast Bits64Type Int16Type)    = knownUN Kprim__cast_Bits64Int16
opName (Cast Bits64Type Int32Type)    = knownUN Kprim__cast_Bits64Int32
opName (Cast Bits64Type Int64Type)    = knownUN Kprim__cast_Bits64Int64
opName (Cast Bits64Type IntegerType)  = knownUN Kprim__cast_Bits64Integer
opName (Cast Bits64Type Bits8Type)    = knownUN Kprim__cast_Bits64Bits8
opName (Cast Bits64Type Bits16Type)   = knownUN Kprim__cast_Bits64Bits16
opName (Cast Bits64Type Bits32Type)   = knownUN Kprim__cast_Bits64Bits32
opName (Cast Bits64Type Bits64Type)   = knownUN Kprim__cast_Bits64Bits64
opName (Cast Bits64Type StringType)   = knownUN Kprim__cast_Bits64String
opName (Cast Bits64Type CharType)     = knownUN Kprim__cast_Bits64Char
opName (Cast Bits64Type DoubleType)   = knownUN Kprim__cast_Bits64Double
opName (Cast Bits64Type WorldType)    = knownUN Kprim__cast_Bits64PercentWorld
opName (Cast StringType IntType)      = knownUN Kprim__cast_StringInt
opName (Cast StringType Int8Type)     = knownUN Kprim__cast_StringInt8
opName (Cast StringType Int16Type)    = knownUN Kprim__cast_StringInt16
opName (Cast StringType Int32Type)    = knownUN Kprim__cast_StringInt32
opName (Cast StringType Int64Type)    = knownUN Kprim__cast_StringInt64
opName (Cast StringType IntegerType)  = knownUN Kprim__cast_StringInteger
opName (Cast StringType Bits8Type)    = knownUN Kprim__cast_StringBits8
opName (Cast StringType Bits16Type)   = knownUN Kprim__cast_StringBits16
opName (Cast StringType Bits32Type)   = knownUN Kprim__cast_StringBits32
opName (Cast StringType Bits64Type)   = knownUN Kprim__cast_StringBits64
opName (Cast StringType StringType)   = knownUN Kprim__cast_StringString
opName (Cast StringType CharType)     = knownUN Kprim__cast_StringChar
opName (Cast StringType DoubleType)   = knownUN Kprim__cast_StringDouble
opName (Cast StringType WorldType)    = knownUN Kprim__cast_StringPercentWorld
opName (Cast CharType IntType)        = knownUN Kprim__cast_CharInt
opName (Cast CharType Int8Type)       = knownUN Kprim__cast_CharInt8
opName (Cast CharType Int16Type)      = knownUN Kprim__cast_CharInt16
opName (Cast CharType Int32Type)      = knownUN Kprim__cast_CharInt32
opName (Cast CharType Int64Type)      = knownUN Kprim__cast_CharInt64
opName (Cast CharType IntegerType)    = knownUN Kprim__cast_CharInteger
opName (Cast CharType Bits8Type)      = knownUN Kprim__cast_CharBits8
opName (Cast CharType Bits16Type)     = knownUN Kprim__cast_CharBits16
opName (Cast CharType Bits32Type)     = knownUN Kprim__cast_CharBits32
opName (Cast CharType Bits64Type)     = knownUN Kprim__cast_CharBits64
opName (Cast CharType StringType)     = knownUN Kprim__cast_CharString
opName (Cast CharType CharType)       = knownUN Kprim__cast_CharChar
opName (Cast CharType DoubleType)     = knownUN Kprim__cast_CharDouble
opName (Cast CharType WorldType)      = knownUN Kprim__cast_CharPercentWorld
opName (Cast DoubleType IntType)      = knownUN Kprim__cast_DoubleInt
opName (Cast DoubleType Int8Type)     = knownUN Kprim__cast_DoubleInt8
opName (Cast DoubleType Int16Type)    = knownUN Kprim__cast_DoubleInt16
opName (Cast DoubleType Int32Type)    = knownUN Kprim__cast_DoubleInt32
opName (Cast DoubleType Int64Type)    = knownUN Kprim__cast_DoubleInt64
opName (Cast DoubleType IntegerType)  = knownUN Kprim__cast_DoubleInteger
opName (Cast DoubleType Bits8Type)    = knownUN Kprim__cast_DoubleBits8
opName (Cast DoubleType Bits16Type)   = knownUN Kprim__cast_DoubleBits16
opName (Cast DoubleType Bits32Type)   = knownUN Kprim__cast_DoubleBits32
opName (Cast DoubleType Bits64Type)   = knownUN Kprim__cast_DoubleBits64
opName (Cast DoubleType StringType)   = knownUN Kprim__cast_DoubleString
opName (Cast DoubleType CharType)     = knownUN Kprim__cast_DoubleChar
opName (Cast DoubleType DoubleType)   = knownUN Kprim__cast_DoubleDouble
opName (Cast DoubleType WorldType)    = knownUN Kprim__cast_DoublePercentWorld
opName (Cast WorldType IntType)       = knownUN Kprim__cast_PercentWorldInt
opName (Cast WorldType Int8Type)      = knownUN Kprim__cast_PercentWorldInt8
opName (Cast WorldType Int16Type)     = knownUN Kprim__cast_PercentWorldInt16
opName (Cast WorldType Int32Type)     = knownUN Kprim__cast_PercentWorldInt32
opName (Cast WorldType Int64Type)     = knownUN Kprim__cast_PercentWorldInt64
opName (Cast WorldType IntegerType)   = knownUN Kprim__cast_PercentWorldInteger
opName (Cast WorldType Bits8Type)     = knownUN Kprim__cast_PercentWorldBits8
opName (Cast WorldType Bits16Type)    = knownUN Kprim__cast_PercentWorldBits16
opName (Cast WorldType Bits32Type)    = knownUN Kprim__cast_PercentWorldBits32
opName (Cast WorldType Bits64Type)    = knownUN Kprim__cast_PercentWorldBits64
opName (Cast WorldType StringType)    = knownUN Kprim__cast_PercentWorldString
opName (Cast WorldType CharType)      = knownUN Kprim__cast_PercentWorldChar
opName (Cast WorldType DoubleType)    = knownUN Kprim__cast_PercentWorldDouble
opName (Cast WorldType WorldType)     = knownUN Kprim__cast_PercentWorldPercentWorld

opName BelieveMe                      = knownUN Kprim__believe_me
opName Crash                          = knownUN Kprim__crash

integralTypes : List PrimType
integralTypes = [ IntType
                , Int8Type
                , Int16Type
                , Int32Type
                , Int64Type
                , IntegerType
                , Bits8Type
                , Bits16Type
                , Bits32Type
                , Bits64Type
                ]

numTypes : List PrimType
numTypes = integralTypes ++ [DoubleType]

primTypes : List PrimType
primTypes = numTypes ++ [StringType, CharType]

export
allPrimitives : List Prim
allPrimitives =
    map (\t => MkPrim (Add t) (arithTy t) isTotal)     numTypes ++
    map (\t => MkPrim (Sub t) (arithTy t) isTotal)     numTypes ++
    map (\t => MkPrim (Mul t) (arithTy t) isTotal)     numTypes ++
    map (\t => MkPrim (Neg t) (predTy t t) isTotal)    numTypes ++
    map (\t => MkPrim (Div t) (arithTy t) notCovering) numTypes ++
    map (\t => MkPrim (Mod t) (arithTy t) notCovering) integralTypes ++

    map (\t => MkPrim (ShiftL t) (arithTy t) isTotal)  integralTypes ++
    map (\t => MkPrim (ShiftR t) (arithTy t) isTotal)  integralTypes ++
    map (\t => MkPrim (BAnd t) (arithTy t) isTotal)    integralTypes ++
    map (\t => MkPrim (BOr t) (arithTy t) isTotal)     integralTypes ++
    map (\t => MkPrim (BXOr t) (arithTy t) isTotal)    integralTypes ++

    map (\t => MkPrim (LT t) (cmpTy t) isTotal)  primTypes ++
    map (\t => MkPrim (LTE t) (cmpTy t) isTotal) primTypes ++
    map (\t => MkPrim (EQ t) (cmpTy t) isTotal)  primTypes ++
    map (\t => MkPrim (GTE t) (cmpTy t) isTotal) primTypes ++
    map (\t => MkPrim (GT t) (cmpTy t) isTotal)  primTypes ++

    [MkPrim StrLength (predTy StringType IntType) isTotal,
     MkPrim StrHead (predTy StringType CharType) notCovering,
     MkPrim StrTail (predTy StringType StringType) notCovering,
     MkPrim StrIndex (constTy StringType IntType CharType) notCovering,
     MkPrim StrCons (constTy CharType StringType StringType) isTotal,
     MkPrim StrAppend (arithTy StringType) isTotal,
     MkPrim StrReverse (predTy StringType StringType) isTotal,
     MkPrim StrSubstr (constTy3 IntType IntType StringType StringType) isTotal,
     MkPrim BelieveMe believeMeTy isTotal,
     MkPrim Crash crashTy notCovering] ++

    [MkPrim DoubleExp doubleTy isTotal,
     MkPrim DoubleLog doubleTy isTotal,
     MkPrim DoublePow (arithTy DoubleType) isTotal,
     MkPrim DoubleSin doubleTy isTotal,
     MkPrim DoubleCos doubleTy isTotal,
     MkPrim DoubleTan doubleTy isTotal,
     MkPrim DoubleASin doubleTy isTotal,
     MkPrim DoubleACos doubleTy isTotal,
     MkPrim DoubleATan doubleTy isTotal,
     MkPrim DoubleSqrt doubleTy isTotal,
     MkPrim DoubleFloor doubleTy isTotal,
     MkPrim DoubleCeiling doubleTy isTotal] ++

    -- support all combinations of primitive casts with the following
    -- exceptions: String -> Char, Double -> Char, Char -> Double
    [ MkPrim (Cast t1 t2) (predTy t1 t2) isTotal
    | t1 <- primTypes
    , t2 <- primTypes
    , t1 /= t2                         &&
      (t1,t2) /= (StringType,CharType) &&
      (t1,t2) /= (DoubleType,CharType) &&
      (t1,t2) /= (CharType,DoubleType)
    ]
