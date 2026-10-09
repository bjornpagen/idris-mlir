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
castString = unaryOp go
  where
    go : Constant -> Maybe Constant
    go (I i) = Just (Str (prim__cast_IntString i))
    go (I8 i) = Just (Str (prim__cast_Int8String i))
    go (I16 i) = Just (Str (prim__cast_Int16String i))
    go (I32 i) = Just (Str (prim__cast_Int32String i))
    go (I64 i) = Just (Str (prim__cast_Int64String i))
    go (BI i) = Just (Str (prim__cast_IntegerString i))
    go (B8 i) = Just (Str (prim__cast_Bits8String i))
    go (B16 i) = Just (Str (prim__cast_Bits16String i))
    go (B32 i) = Just (Str (prim__cast_Bits32String i))
    go (B64 i) = Just (Str (prim__cast_Bits64String i))
    go (Ch i) = Just (Str (prim__cast_CharString i))
    go (Db i) = Just (Str (prim__cast_DoubleString i))
    go _ = Nothing

castInteger : Vect 1 (NF vars) -> Maybe (NF vars)
castInteger = unaryOp go
  where
    go : Constant -> Maybe Constant
    go (I i) = Just (BI (prim__cast_IntInteger i))
    go (I8 i) = Just (BI (prim__cast_Int8Integer i))
    go (I16 i) = Just (BI (prim__cast_Int16Integer i))
    go (I32 i) = Just (BI (prim__cast_Int32Integer i))
    go (I64 i) = Just (BI (prim__cast_Int64Integer i))
    go (B8 i) = Just (BI (prim__cast_Bits8Integer i))
    go (B16 i) = Just (BI (prim__cast_Bits16Integer i))
    go (B32 i) = Just (BI (prim__cast_Bits32Integer i))
    go (B64 i) = Just (BI (prim__cast_Bits64Integer i))
    go (Ch i) = Just (BI (prim__cast_CharInteger i))
    go (Db i) = Just (BI (prim__cast_DoubleInteger i))
    go (Str i) = Just (BI (prim__cast_StringInteger i))
    go _ = Nothing

castInt : Vect 1 (NF vars) -> Maybe (NF vars)
castInt = unaryOp go
  where
    go : Constant -> Maybe Constant
    go (I8 i) = Just (I (prim__cast_Int8Int i))
    go (I16 i) = Just (I (prim__cast_Int16Int i))
    go (I32 i) = Just (I (prim__cast_Int32Int i))
    go (I64 i) = Just (I (prim__cast_Int64Int i))
    go (BI i) = Just (I (prim__cast_IntegerInt i))
    go (B8 i) = Just (I (prim__cast_Bits8Int i))
    go (B16 i) = Just (I (prim__cast_Bits16Int i))
    go (B32 i) = Just (I (prim__cast_Bits32Int i))
    go (B64 i) = Just (I (prim__cast_Bits64Int i))
    go (Db i) = Just (I (prim__cast_DoubleInt i))
    go (Ch i) = Just (I (prim__cast_CharInt i))
    go (Str i) = Just (I (prim__cast_StringInt i))
    go _ = Nothing

-- The casts to a fixed-width integer below fold from an integer only, as
-- they always have; one from a Double, a Char or a String stays applied.

castBits8 : Vect 1 (NF vars) -> Maybe (NF vars)
castBits8 = unaryOp go
  where
    go : Constant -> Maybe Constant
    go (I i) = Just (B8 (prim__cast_IntBits8 i))
    go (I8 i) = Just (B8 (prim__cast_Int8Bits8 i))
    go (I16 i) = Just (B8 (prim__cast_Int16Bits8 i))
    go (I32 i) = Just (B8 (prim__cast_Int32Bits8 i))
    go (I64 i) = Just (B8 (prim__cast_Int64Bits8 i))
    go (BI i) = Just (B8 (prim__cast_IntegerBits8 i))
    go (B16 i) = Just (B8 (prim__cast_Bits16Bits8 i))
    go (B32 i) = Just (B8 (prim__cast_Bits32Bits8 i))
    go (B64 i) = Just (B8 (prim__cast_Bits64Bits8 i))
    go _ = Nothing

castBits16 : Vect 1 (NF vars) -> Maybe (NF vars)
castBits16 = unaryOp go
  where
    go : Constant -> Maybe Constant
    go (I i) = Just (B16 (prim__cast_IntBits16 i))
    go (I8 i) = Just (B16 (prim__cast_Int8Bits16 i))
    go (I16 i) = Just (B16 (prim__cast_Int16Bits16 i))
    go (I32 i) = Just (B16 (prim__cast_Int32Bits16 i))
    go (I64 i) = Just (B16 (prim__cast_Int64Bits16 i))
    go (BI i) = Just (B16 (prim__cast_IntegerBits16 i))
    go (B8 i) = Just (B16 (prim__cast_Bits8Bits16 i))
    go (B32 i) = Just (B16 (prim__cast_Bits32Bits16 i))
    go (B64 i) = Just (B16 (prim__cast_Bits64Bits16 i))
    go _ = Nothing

castBits32 : Vect 1 (NF vars) -> Maybe (NF vars)
castBits32 = unaryOp go
  where
    go : Constant -> Maybe Constant
    go (I i) = Just (B32 (prim__cast_IntBits32 i))
    go (I8 i) = Just (B32 (prim__cast_Int8Bits32 i))
    go (I16 i) = Just (B32 (prim__cast_Int16Bits32 i))
    go (I32 i) = Just (B32 (prim__cast_Int32Bits32 i))
    go (I64 i) = Just (B32 (prim__cast_Int64Bits32 i))
    go (BI i) = Just (B32 (prim__cast_IntegerBits32 i))
    go (B8 i) = Just (B32 (prim__cast_Bits8Bits32 i))
    go (B16 i) = Just (B32 (prim__cast_Bits16Bits32 i))
    go (B64 i) = Just (B32 (prim__cast_Bits64Bits32 i))
    go _ = Nothing

castBits64 : Vect 1 (NF vars) -> Maybe (NF vars)
castBits64 = unaryOp go
  where
    go : Constant -> Maybe Constant
    go (I i) = Just (B64 (prim__cast_IntBits64 i))
    go (I8 i) = Just (B64 (prim__cast_Int8Bits64 i))
    go (I16 i) = Just (B64 (prim__cast_Int16Bits64 i))
    go (I32 i) = Just (B64 (prim__cast_Int32Bits64 i))
    go (I64 i) = Just (B64 (prim__cast_Int64Bits64 i))
    go (BI i) = Just (B64 (prim__cast_IntegerBits64 i))
    go (B8 i) = Just (B64 (prim__cast_Bits8Bits64 i))
    go (B16 i) = Just (B64 (prim__cast_Bits16Bits64 i))
    go (B32 i) = Just (B64 (prim__cast_Bits32Bits64 i))
    go _ = Nothing

castInt8 : Vect 1 (NF vars) -> Maybe (NF vars)
castInt8 = unaryOp go
  where
    go : Constant -> Maybe Constant
    go (I i) = Just (I8 (prim__cast_IntInt8 i))
    go (I16 i) = Just (I8 (prim__cast_Int16Int8 i))
    go (I32 i) = Just (I8 (prim__cast_Int32Int8 i))
    go (I64 i) = Just (I8 (prim__cast_Int64Int8 i))
    go (BI i) = Just (I8 (prim__cast_IntegerInt8 i))
    go (B8 i) = Just (I8 (prim__cast_Bits8Int8 i))
    go (B16 i) = Just (I8 (prim__cast_Bits16Int8 i))
    go (B32 i) = Just (I8 (prim__cast_Bits32Int8 i))
    go (B64 i) = Just (I8 (prim__cast_Bits64Int8 i))
    go _ = Nothing

castInt16 : Vect 1 (NF vars) -> Maybe (NF vars)
castInt16 = unaryOp go
  where
    go : Constant -> Maybe Constant
    go (I i) = Just (I16 (prim__cast_IntInt16 i))
    go (I8 i) = Just (I16 (prim__cast_Int8Int16 i))
    go (I32 i) = Just (I16 (prim__cast_Int32Int16 i))
    go (I64 i) = Just (I16 (prim__cast_Int64Int16 i))
    go (BI i) = Just (I16 (prim__cast_IntegerInt16 i))
    go (B8 i) = Just (I16 (prim__cast_Bits8Int16 i))
    go (B16 i) = Just (I16 (prim__cast_Bits16Int16 i))
    go (B32 i) = Just (I16 (prim__cast_Bits32Int16 i))
    go (B64 i) = Just (I16 (prim__cast_Bits64Int16 i))
    go _ = Nothing

castInt32 : Vect 1 (NF vars) -> Maybe (NF vars)
castInt32 = unaryOp go
  where
    go : Constant -> Maybe Constant
    go (I i) = Just (I32 (prim__cast_IntInt32 i))
    go (I8 i) = Just (I32 (prim__cast_Int8Int32 i))
    go (I16 i) = Just (I32 (prim__cast_Int16Int32 i))
    go (I64 i) = Just (I32 (prim__cast_Int64Int32 i))
    go (BI i) = Just (I32 (prim__cast_IntegerInt32 i))
    go (B8 i) = Just (I32 (prim__cast_Bits8Int32 i))
    go (B16 i) = Just (I32 (prim__cast_Bits16Int32 i))
    go (B32 i) = Just (I32 (prim__cast_Bits32Int32 i))
    go (B64 i) = Just (I32 (prim__cast_Bits64Int32 i))
    go _ = Nothing

castInt64 : Vect 1 (NF vars) -> Maybe (NF vars)
castInt64 = unaryOp go
  where
    go : Constant -> Maybe Constant
    go (I i) = Just (I64 (prim__cast_IntInt64 i))
    go (I8 i) = Just (I64 (prim__cast_Int8Int64 i))
    go (I16 i) = Just (I64 (prim__cast_Int16Int64 i))
    go (I32 i) = Just (I64 (prim__cast_Int32Int64 i))
    go (BI i) = Just (I64 (prim__cast_IntegerInt64 i))
    go (B8 i) = Just (I64 (prim__cast_Bits8Int64 i))
    go (B16 i) = Just (I64 (prim__cast_Bits16Int64 i))
    go (B32 i) = Just (I64 (prim__cast_Bits32Int64 i))
    go (B64 i) = Just (I64 (prim__cast_Bits64Int64 i))
    go _ = Nothing

castDouble : Vect 1 (NF vars) -> Maybe (NF vars)
castDouble = unaryOp go
  where
    go : Constant -> Maybe Constant
    go (I i) = Just (Db (prim__cast_IntDouble i))
    go (I8 i) = Just (Db (prim__cast_Int8Double i))
    go (I16 i) = Just (Db (prim__cast_Int16Double i))
    go (I32 i) = Just (Db (prim__cast_Int32Double i))
    go (I64 i) = Just (Db (prim__cast_Int64Double i))
    go (B8 i) = Just (Db (prim__cast_Bits8Double i))
    go (B16 i) = Just (Db (prim__cast_Bits16Double i))
    go (B32 i) = Just (Db (prim__cast_Bits32Double i))
    go (B64 i) = Just (Db (prim__cast_Bits64Double i))
    go (BI i) = Just (Db (prim__cast_IntegerDouble i))
    go (Str i) = Just (Db (prim__cast_StringDouble i))
    go _ = Nothing

castChar : Vect 1 (NF vars) -> Maybe (NF vars)
castChar = unaryOp go
  where
    go : Constant -> Maybe Constant
    go (I i) = Just (Ch (prim__cast_IntChar i))
    go (I8 i) = Just (Ch (prim__cast_Int8Char i))
    go (I16 i) = Just (Ch (prim__cast_Int16Char i))
    go (I32 i) = Just (Ch (prim__cast_Int32Char i))
    go (I64 i) = Just (Ch (prim__cast_Int64Char i))
    go (B8 i) = Just (Ch (prim__cast_Bits8Char i))
    go (B16 i) = Just (Ch (prim__cast_Bits16Char i))
    go (B32 i) = Just (Ch (prim__cast_Bits32Char i))
    go (B64 i) = Just (Ch (prim__cast_Bits64Char i))
    go (BI i) = Just (Ch (prim__cast_IntegerChar i))
    go _ = Nothing

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

pi : (x : String) -> RigCount -> PiInfo (Term xs) -> Term xs ->
     Term (UN (Basic x) :: xs) -> Term xs
pi x rig plic ty sc = Bind emptyFC (UN (Basic x)) (Pi emptyFC rig plic ty) sc

believeMeTy : ClosedTerm
believeMeTy
    = pi "a" erased Explicit (TType emptyFC (MN "top" 0)) $
      pi "b" erased Explicit (TType emptyFC (MN "top" 0)) $
      pi "x" linear Explicit (Local emptyFC Nothing _ (Later First)) $
      Local emptyFC Nothing _ (Later First)

crashTy : ClosedTerm
crashTy
    = pi "a" erased Explicit (TType emptyFC (MN "top" 0)) $
      pi "msg" top Explicit (PrimVal emptyFC $ PrT StringType) $
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

prim : String -> Name
prim str = UN $ Basic $ "prim__" ++ str

export
opName : {0 arity : Nat} -> PrimFn arity -> Name
opName (Add ty) = prim $ "add_" ++ show ty
opName (Sub ty) = prim $ "sub_" ++ show ty
opName (Mul ty) = prim $ "mul_" ++ show ty
opName (Div ty) = prim $ "div_" ++ show ty
opName (Mod ty) = prim $ "mod_" ++ show ty
opName (Neg ty) = prim $ "negate_" ++ show ty
opName (ShiftL ty) = prim $ "shl_" ++ show ty
opName (ShiftR ty) = prim $ "shr_" ++ show ty
opName (BAnd ty) = prim $ "and_" ++ show ty
opName (BOr ty) = prim $ "or_" ++ show ty
opName (BXOr ty) = prim $ "xor_" ++ show ty
opName (LT ty) = prim $ "lt_" ++ show ty
opName (LTE ty) = prim $ "lte_" ++ show ty
opName (EQ ty) = prim $ "eq_" ++ show ty
opName (GTE ty) = prim $ "gte_" ++ show ty
opName (GT ty) = prim $ "gt_" ++ show ty
opName StrLength = prim "strLength"
opName StrHead = prim "strHead"
opName StrTail = prim "strTail"
opName StrIndex = prim "strIndex"
opName StrCons = prim "strCons"
opName StrAppend = prim "strAppend"
opName StrReverse = prim "strReverse"
opName StrSubstr = prim "strSubstr"
opName DoubleExp = prim "doubleExp"
opName DoubleLog = prim "doubleLog"
opName DoublePow = prim "doublePow"
opName DoubleSin = prim "doubleSin"
opName DoubleCos = prim "doubleCos"
opName DoubleTan = prim "doubleTan"
opName DoubleASin = prim "doubleASin"
opName DoubleACos = prim "doubleACos"
opName DoubleATan = prim "doubleATan"
opName DoubleSqrt = prim "doubleSqrt"
opName DoubleFloor = prim "doubleFloor"
opName DoubleCeiling = prim "doubleCeiling"
opName (Cast x y) = prim $ "cast_" ++ show x ++ show y
opName BelieveMe = prim $ "believe_me"
opName Crash = prim $ "crash"

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
