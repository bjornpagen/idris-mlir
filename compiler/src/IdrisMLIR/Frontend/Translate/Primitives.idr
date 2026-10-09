||| Idris's primitives as Core's: each has one meaning, the runtime's, so
||| this only names them: the op of the dialect each is, or the operation
||| its types choose.
module IdrisMLIR.Frontend.Translate.Primitives

import Core.TT

import IdrisMLIR.Dialect.Idr as Idr
import IdrisMLIR.Frontend.Translate.Types
import IdrisMLIR.Types

%default covering

scalar : PrimType -> Maybe Scalar
scalar CharType = Just SChar
scalar DoubleType = Just SDouble
scalar t = SInt <$> intTy t

||| Double arithmetic and the C library's functions.
double : PrimFn k -> Maybe Prim
double (Add DoubleType) = Just (FloatOp FAdd)
double (Sub DoubleType) = Just (FloatOp FSub)
double (Mul DoubleType) = Just (FloatOp FMul)
double (Div DoubleType) = Just (FloatOp FDiv)
double (Neg DoubleType) = Just Negate
double DoubleExp = Just (Math Exp)
double DoubleLog = Just (Math Log)
double DoublePow = Just (Math Pow)
double DoubleSin = Just (Math Sin)
double DoubleCos = Just (Math Cos)
double DoubleTan = Just (Math Tan)
double DoubleASin = Just (Math ASin)
double DoubleACos = Just (Math ACos)
double DoubleATan = Just (Math ATan)
double DoubleSqrt = Just (Math Sqrt)
double DoubleFloor = Just (Math Floor)
double DoubleCeiling = Just (Math Ceiling)
double _ = Nothing

||| A cast between types that exist at runtime; `Char` and `Double` are not
||| cast to each other.
runtimeCast : Scalar -> Scalar -> Maybe Prim
runtimeCast SChar SDouble = Nothing
runtimeCast SDouble SChar = Nothing
runtimeCast a b = Just (Cast a b)

arith : PrimFn k -> Maybe (ArithOp, PrimType)
arith (Add t) = Just (Add, t)
arith (Sub t) = Just (Sub, t)
arith (Mul t) = Just (Mul, t)
arith (Div t) = Just (Div, t)
arith (Mod t) = Just (Mod, t)
arith (BAnd t) = Just (And, t)
arith (BOr t) = Just (Or, t)
arith (BXOr t) = Just (Xor, t)
arith _ = Nothing

comparison : PrimFn k -> Maybe (Cmp, PrimType)
comparison (LT t) = Just (CLt, t)
comparison (LTE t) = Just (CLte, t)
comparison (EQ t) = Just (CEq, t)
comparison (GTE t) = Just (CGte, t)
comparison (GT t) = Just (CGt, t)
comparison _ = Nothing

||| Integer primitives: `idr.big.*`.
integer : PrimFn k -> Maybe Prim
integer (Add IntegerType) = Just (Op BigAdd)
integer (Sub IntegerType) = Just (Op BigSub)
integer (Mul IntegerType) = Just (Op BigMul)
integer (Div IntegerType) = Just (Op BigDiv)
integer (Mod IntegerType) = Just (Op BigMod)
integer (BAnd IntegerType) = Just (Op BigAnd)
integer (BOr IntegerType) = Just (Op BigOr)
integer (BXOr IntegerType) = Just (Op BigXor)
integer (ShiftL IntegerType) = Just (Op BigShl)
integer (ShiftR IntegerType) = Just (Op BigShr)
integer (Neg IntegerType) = Just (Op BigNeg)
integer (Cast IntegerType StringType) = Just (Op BigShow)
integer (Cast StringType IntegerType) = Just (Op BigFromStr)
integer (Cast IntegerType to) = FromBig <$> scalar to
integer (Cast from IntegerType) = ToBig <$> scalar from
integer p = case comparison p of
  Just (op, IntegerType) => Just (BigCompare op)
  _ => Nothing

||| A cast from a string: to a number. A string has no `Char` cast.
fromString : PrimType -> Maybe Prim
fromString CharType = Nothing
fromString to = FromStr <$> scalar to

export
primOp : PrimFn k -> Maybe Prim
primOp p = case (integer p, double p, arith p, comparison p, p) of
  (Just b, _, _, _, _) => Just b
  (_, Just d, _, _, _) => Just d
  (_, _, Just (op, t), _, _) => IntOp op <$> intTy t
  (_, _, _, _, ShiftL t) => IntShift ShiftLeft <$> intTy t
  (_, _, _, _, ShiftR t) => IntShift ShiftRight <$> intTy t
  (_, _, _, Just (op, StringType), _) => Just (StrCompare op)
  (_, _, _, Just (op, t), _) => Compare op <$> scalar t
  (_, _, _, _, Cast StringType to) => fromString to
  (_, _, _, _, Cast from StringType) => ToStr <$> scalar from
  (_, _, _, _, Cast from to) => join (runtimeCast <$> scalar from <*> scalar to)
  (_, _, _, _, StrLength) => Just (Op Idr.StrLength)
  (_, _, _, _, StrHead) => Just (Op Idr.StrHead)
  (_, _, _, _, StrTail) => Just (Op Idr.StrTail)
  (_, _, _, _, StrIndex) => Just (Op Idr.StrIndex)
  (_, _, _, _, StrCons) => Just (Op Idr.StrCons)
  (_, _, _, _, StrAppend) => Just (Op Idr.StrAppend)
  (_, _, _, _, StrReverse) => Just (Op Idr.StrReverse)
  (_, _, _, _, StrSubstr) => Just (Op Idr.StrSubstr)
  _ => Nothing

||| Idris's arguments of a primitive in the order its op takes them:
||| `prim__strSubstr` takes the start, the length and then the string,
||| which `idr.str.substr` takes first.
export
opOrder : PrimFn k -> List a -> List a
opOrder StrSubstr [start, len, s] = [s, start, len]
opOrder _ xs = xs
