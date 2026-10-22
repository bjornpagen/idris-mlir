-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Idris's primitives as Core's: each has one meaning, the runtime's, so
||| this only names them: the op of the dialect each is, or the operation
||| its types choose.
module IdrisMLIR.Frontend.Translate.Primitives

import Core.TT

import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Registry
import IdrisMLIR.Spec.Core.Rules
import IdrisMLIR.Spec.Ops.Bigs
import IdrisMLIR.Spec.Ops.Strings
import IdrisMLIR.Spec.Ops.Values
import IdrisMLIR.Term
import IdrisMLIR.Types

import Data.Vect

%default total

||| The fixed-width integer or character a primitive type is, if it is
||| one.
integral : PrimTy -> Maybe IntLike
integral (IntP it) = Just (SInt it)
integral CharP = Just SChar
integral _ = Nothing

||| The fixed-width scalar a primitive type is, if it is one.
scalar : PrimTy -> Maybe Scalar
scalar DoubleP = Just SDouble
scalar t = SIntegral <$> integral t

||| What a string is read as, if it can be read as this type: a number.
numeric : PrimTy -> Maybe Numeric
numeric (IntP it) = Just (NInt it)
numeric DoubleP = Just NDouble
numeric _ = Nothing

||| Arithmetic of two operands of one type, by the type: a fixed width's
||| op, Integer's (`integer`), or Double's when it has one.
arith : ArithOp -> Maybe FArith -> (integer : Prim 2) -> PrimType -> Maybe (Prim 2)
arith op double integer t = case primTy t of
  IntP it => Just (IntOp op it)
  IntegerP => Just integer
  DoubleP => FloatOp <$> double
  _ => Nothing

||| A shift, by the type: a fixed width's op or Integer's.
shift : Shift -> (integer : Prim 2) -> PrimType -> Maybe (Prim 2)
shift s integer t = case primTy t of
  IntP it => Just (IntShift s it)
  IntegerP => Just integer
  _ => Nothing

||| A comparison, by the type of its operands.
comparison : Comparison -> PrimType -> Maybe (Prim 2)
comparison op t = case primTy t of
  IntegerP => Just (BigCompare op)
  StringP => Just (StrCompare op)
  WorldP => Nothing
  ty => Compare op <$> scalar ty

||| A cast, by the types it is between, giving a value of `result`:
||| Integer's to and from a string and a scalar, a string's to a number and
||| from a scalar, and a scalar's to another (`Conversion`, which has no
||| cast between a `Char` and a `Double`).
conversion : (result : Ty) -> PrimTy -> PrimTy -> Maybe (Prim 1)
conversion result IntegerP StringP = Just (Op bigShow result made)
conversion result StringP IntegerP = Just (Op bigFromStr result made)
conversion result IntegerP to = FromBig <$> scalar to
conversion result from IntegerP = ToBig <$> scalar from
conversion result StringP to = FromStr <$> numeric to
conversion result from StringP = ToStr <$> scalar from
conversion result (IntP a) DoubleP = Just (Cast (IntToDouble a))
conversion result DoubleP (IntP b) = Just (Cast (DoubleToInt b))
conversion result from to = (\a, b => Cast (IntToInt a b)) <$> integral from <*> integral to

||| Each primitive's op, by its operation and the type it is at, of the
||| result type given. A fixed width has no negation of one operand:
||| `primTerm` subtracts it from 0.
primOp : (result : Ty) -> PrimFn k -> Maybe (Prim k)
primOp result (Add t) = arith Add (Just FAdd) (Op bigAdd result made) t
primOp result (Sub t) = arith Sub (Just FSub) (Op bigSub result made) t
primOp result (Mul t) = arith Mul (Just FMul) (Op bigMul result made) t
primOp result (Div t) = arith Div (Just FDiv) (Op bigDiv result made) t
primOp result (Mod t) = arith Mod Nothing (Op bigMod result made) t
primOp result (BAnd t) = arith And Nothing (Op bigAnd result made) t
primOp result (BOr t) = arith Or Nothing (Op bigOr result made) t
primOp result (BXOr t) = arith Xor Nothing (Op bigXor result made) t
primOp result (ShiftL t) = shift ShiftLeft (Op bigShl result made) t
primOp result (ShiftR t) = shift ShiftRight (Op bigShr result made) t
primOp result (Neg t) = case primTy t of
  IntegerP => Just (Op bigNeg result made)
  DoubleP => Just Negate
  _ => Nothing
primOp result (LT t) = comparison Values.Lt t
primOp result (LTE t) = comparison Values.Lte t
primOp result (EQ t) = comparison Values.Eq t
primOp result (GTE t) = comparison Values.Gte t
primOp result (GT t) = comparison Values.Gt t
primOp result StrLength = Just (Op strLength result made)
primOp result StrHead = Just (Op strHead result made)
primOp result StrTail = Just (Op strTail result made)
primOp result StrIndex = Just (Op strIndex result made)
primOp result StrCons = Just (Op strCons result made)
primOp result StrAppend = Just (Op strAppend result made)
primOp result StrReverse = Just (Op strReverse result made)
primOp result StrSubstr = Just (Op strSubstr result made)
primOp result DoubleExp = Just (Math1 Exp)
primOp result DoubleLog = Just (Math1 Log)
primOp result DoublePow = Just Pow
primOp result DoubleSin = Just (Math1 Sin)
primOp result DoubleCos = Just (Math1 Cos)
primOp result DoubleTan = Just (Math1 Tan)
primOp result DoubleASin = Just (Math1 ASin)
primOp result DoubleACos = Just (Math1 ACos)
primOp result DoubleATan = Just (Math1 ATan)
primOp result DoubleSqrt = Just (Math1 Sqrt)
primOp result DoubleFloor = Just (Math1 Floor)
primOp result DoubleCeiling = Just (Math1 Ceiling)
primOp result (Cast from to) = conversion result (primTy from) (primTy to)
-- The escape hatches are no op: the translation decides each where it
-- meets it.
primOp result BelieveMe = Nothing
primOp result Crash = Nothing

||| A primitive's op on its operands, in Idris's order.
applied : {k : Nat} -> Loc -> Maybe (Prim k) -> Maybe ({0 m : Nat} -> Vect k (Term m) -> Term m)
applied loc (Just p) = Just (\xs => PrimApp loc p Nothing xs)
applied loc Nothing = Nothing

||| The one translation of an Idris primitive, on its operands in Idris's
||| order, of the result type given. A fixed width's negation is its
||| subtraction from 0, as the prelude's `negate` writes it, and
||| `prim__strSubstr` takes the start, the length and then the string,
||| which `idr.str.substr` takes first. `Nothing` only for what Idris
||| never builds.
export
primTerm : {k : Nat} -> Loc -> (result : Ty) -> PrimFn k -> Maybe ({0 m : Nat} -> Vect k (Term m) -> Term m)
primTerm loc result (Neg t) with (primTy t)
  primTerm loc result (Neg t) | IntP it = Just (\[x] => PrimApp loc (IntOp Sub it) Nothing [Literal loc (LInt it 0), x])
  primTerm loc result (Neg t) | _ = applied loc (primOp result (Neg t))
primTerm loc result StrSubstr = Just (\[start, len, s] => PrimApp loc (Op strSubstr result made) Nothing [s, start, len])
primTerm loc result op = applied loc (primOp result op)
