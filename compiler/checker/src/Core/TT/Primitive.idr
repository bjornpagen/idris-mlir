-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Core.TT.Primitive

import Core.Name

import Data.String

import Idris.Pretty.Annotations

import Libraries.Data.Ordering.Extra
import Libraries.Text.PrettyPrint.Prettyprinter

%default total

public export
data PrimType
    = IntType
    | Int8Type
    | Int16Type
    | Int32Type
    | Int64Type
    | IntegerType
    | Bits8Type
    | Bits16Type
    | Bits32Type
    | Bits64Type
    | StringType
    | CharType
    | DoubleType
    | WorldType

%name PrimType pty

public export
data Constant
    = I   Int
    | I8  Int8
    | I16 Int16
    | I32 Int32
    | I64 Int64
    | BI  Integer
    | B8  Bits8
    | B16 Bits16
    | B32 Bits32
    | B64 Bits64
    | Str String
    | Ch  Char
    | Db  Double
    | PrT PrimType
    | WorldVal

%name Constant cst

-- Return the primitive type of a constant.
-- For PrT, return Nothing.
export
primType : Constant -> Maybe PrimType
primType (I {})   = Just IntType
primType (I8 {})  = Just Int8Type
primType (I16 {}) = Just Int16Type
primType (I32 {}) = Just Int32Type
primType (I64 {}) = Just Int64Type
primType (BI {})  = Just IntegerType
primType (B8 {})  = Just Bits8Type
primType (B16 {}) = Just Bits16Type
primType (B32 {}) = Just Bits32Type
primType (B64 {}) = Just Bits64Type
primType (Str {}) = Just StringType
primType (Ch {})  = Just CharType
primType (Db {})  = Just DoubleType
primType (PrT {}) = Nothing
primType WorldVal = Just WorldType

||| The primitive type a name in no namespace names: `primTypeKnown`, read
||| back.
export
isConstantType : Name -> Maybe PrimType
isConstantType n = case knownRoot n of
  Just KInt          => Just IntType
  Just KInt8         => Just Int8Type
  Just KInt16        => Just Int16Type
  Just KInt32        => Just Int32Type
  Just KInt64        => Just Int64Type
  Just KInteger      => Just IntegerType
  Just KBits8        => Just Bits8Type
  Just KBits16       => Just Bits16Type
  Just KBits32       => Just Bits32Type
  Just KBits64       => Just Bits64Type
  Just KString       => Just StringType
  Just KChar         => Just CharType
  Just KDouble       => Just DoubleType
  Just KPercentWorld => Just WorldType
  _ => Nothing

export
primTypeEq : (x, y : PrimType) -> Maybe (x = y)
primTypeEq IntType IntType = Just Refl
primTypeEq Int8Type Int8Type = Just Refl
primTypeEq Int16Type Int16Type = Just Refl
primTypeEq Int32Type Int32Type = Just Refl
primTypeEq Int64Type Int64Type = Just Refl
primTypeEq IntegerType IntegerType = Just Refl
primTypeEq StringType StringType = Just Refl
primTypeEq CharType CharType = Just Refl
primTypeEq DoubleType DoubleType = Just Refl
primTypeEq WorldType WorldType = Just Refl
primTypeEq _ _ = Nothing

||| The identifier a primitive type is named by (`isConstantType` reads it
||| back), whose spelling is the type's printed form.
export
primTypeKnown : PrimType -> Known
primTypeKnown IntType = KInt
primTypeKnown Int8Type = KInt8
primTypeKnown Int16Type = KInt16
primTypeKnown Int32Type = KInt32
primTypeKnown Int64Type = KInt64
primTypeKnown IntegerType = KInteger
primTypeKnown Bits8Type = KBits8
primTypeKnown Bits16Type = KBits16
primTypeKnown Bits32Type = KBits32
primTypeKnown Bits64Type = KBits64
primTypeKnown StringType = KString
primTypeKnown CharType = KChar
primTypeKnown DoubleType = KDouble
primTypeKnown WorldType = KPercentWorld

export
Show PrimType where
  show t = spelling (primTypeKnown t)

export
Show Constant where
  show (I x) = show x
  show (I8 x) = show x
  show (I16 x) = show x
  show (I32 x) = show x
  show (I64 x) = show x
  show (BI x) = show x
  show (B8 x) = show x
  show (B16 x) = show x
  show (B32 x) = show x
  show (B64 x) = show x
  show (Str x) = show x
  show (Ch x) = show x
  show (Db x) = show x
  show (PrT x) = show x
  show WorldVal = "%MkWorld"

Pretty IdrisSyntax PrimType where
  pretty c = annotate (TCon Nothing) $ pretty0 $ show c

export
Pretty IdrisSyntax Constant where
  pretty (PrT x) = pretty x
  pretty v = annotate (DCon Nothing) $ pretty0 $ show v


-- Public, as `Eq Constant` is.
public export
Eq PrimType where
  IntType == IntType = True
  Int8Type == Int8Type = True
  Int16Type == Int16Type = True
  Int32Type == Int32Type = True
  Int64Type == Int64Type = True
  IntegerType == IntegerType = True
  Bits8Type == Bits8Type = True
  Bits16Type == Bits16Type = True
  Bits32Type == Bits32Type = True
  Bits64Type == Bits64Type = True
  StringType == StringType = True
  CharType == CharType = True
  DoubleType == DoubleType = True
  WorldType == WorldType = True
  _ == _ = False

-- Public, so that a proof reads off the evaluator's comparison of
-- constants: each type's own equality, a double's the runtime's. It is the
-- program's comparison, which a match on a constant makes; definitional
-- equality compares constants by `identicalConstants` instead, since by
-- `==` 0.0 is -0.0.
public export
Eq Constant where
  (I x) == (I y) = x == y
  (I8 x) == (I8 y) = x == y
  (I16 x) == (I16 y) = x == y
  (I32 x) == (I32 y) = x == y
  (I64 x) == (I64 y) = x == y
  (BI x) == (BI y) = x == y
  (B8 x) == (B8 y) = x == y
  (B16 x) == (B16 y) = x == y
  (B32 x) == (B32 y) = x == y
  (B64 x) == (B64 y) = x == y
  (Str x) == (Str y) = x == y
  (Ch x) == (Ch y) = x == y
  (Db x) == (Db y) = x == y
  (PrT x) == (PrT y) = x == y
  WorldVal == WorldVal = True
  _ == _ = False

||| Whether two doubles are one double, the same IEEE 754 binary64 bits:
||| they are equal by `==`, and so are their reciprocals. Binary64 has one
||| encoding for each number but zero, so two numbers `==` finds equal are
||| one encoding, but for the two zeros, which `==` finds equal and whose
||| reciprocals, by IEEE 754 the infinity of each zero's sign, it does not;
||| no number's reciprocal is a NaN, so of every other pair the first test
||| holds of, the second holds too. That is exact on every Double a term
||| can hold, since a NaN, which `==` finds unequal to every double, itself
||| included, is no constant: no literal is one, the evaluator's folds leave
||| an operation whose result is a NaN applied, and it reads no String's
||| number. Were one to appear, the comparison would refuse it as itself,
||| never take two doubles that differ for one. It is pure, so the quick
||| syntactic check (`eqTerm`) and conversion make the one comparison.
export
sameDouble : Double -> Double -> Bool
sameDouble x y = x == y && 1.0 / x == 1.0 / y

||| Whether two constants are one constant, the comparison definitional
||| equality makes of them: a double by `sameDouble`, by which 0.0 is not
||| -0.0 though `==` finds them equal, every other constant by its type's
||| `==`, which is its value's identity.
export
identicalConstants : Constant -> Constant -> Bool
identicalConstants (Db x) (Db y) = sameDouble x y
identicalConstants c c' = c == c'

export
Ord PrimType where
  compare = compare `on` tag
    where
      tag : PrimType -> Int
      tag IntType     = 1
      tag Int8Type    = 2
      tag Int16Type   = 3
      tag Int32Type   = 4
      tag Int64Type   = 5
      tag IntegerType = 6
      tag Bits8Type   = 7
      tag Bits16Type  = 8
      tag Bits32Type  = 9
      tag Bits64Type  = 10
      tag StringType  = 11
      tag CharType    = 12
      tag DoubleType  = 13
      tag WorldType   = 14

export
Ord Constant where
    I x `compare` I y = compare x y
    I8 x `compare` I8 y = compare x y
    I16 x `compare` I16 y = compare x y
    I32 x `compare` I32 y = compare x y
    I64 x `compare` I64 y = compare x y
    BI x `compare` BI y = compare x y
    B8 x `compare` B8 y = compare x y
    B16 x `compare` B16 y = compare x y
    B32 x `compare` B32 y = compare x y
    B64 x `compare` B64 y = compare x y
    Str x `compare` Str y = compare x y
    Ch x `compare` Ch y = compare x y
    Db x `compare` Db y = compare x y
    PrT x `compare` PrT y = compare x y
    compare x y = compare (tag x) (tag y)
      where
        tag : Constant -> Int
        tag (I _) = 0
        tag (I8 _) = 1
        tag (I16 _) = 2
        tag (I32 _) = 3
        tag (I64 _) = 4
        tag (BI _) = 5
        tag (B8 _) = 6
        tag (B16 _) = 7
        tag (B32 _) = 8
        tag (B64 _) = 9
        tag (Str _) = 10
        tag (Ch _) = 11
        tag (Db _) = 12
        tag (PrT _) = 13
        tag WorldVal = 14

||| Precision of integral types.
public export
data Precision = P Int | Unlimited

%name Precision prec

export
Eq Precision where
  (P m) == (P n)         = m == n
  Unlimited == Unlimited = True
  _         == _         = False

export
Ord Precision where
  compare (P m) (P n)         = compare m n
  compare Unlimited Unlimited = EQ
  compare Unlimited _         = GT
  compare _         Unlimited = LT

-- so far, we only support limited precision
-- unsigned integers
public export
data IntKind = Signed Precision | Unsigned Int

-- All the internal operators, parameterised by their arity
public export
data PrimFn : Nat -> Type where
     Add : (ty : PrimType) -> PrimFn 2
     Sub : (ty : PrimType) -> PrimFn 2
     Mul : (ty : PrimType) -> PrimFn 2
     Div : (ty : PrimType) -> PrimFn 2
     Mod : (ty : PrimType) -> PrimFn 2
     Neg : (ty : PrimType) -> PrimFn 1
     ShiftL : (ty : PrimType) -> PrimFn 2
     ShiftR : (ty : PrimType) -> PrimFn 2

     BAnd : (ty : PrimType) -> PrimFn 2
     BOr : (ty : PrimType) -> PrimFn 2
     BXOr : (ty : PrimType) -> PrimFn 2

     LT  : (ty : PrimType) -> PrimFn 2
     LTE : (ty : PrimType) -> PrimFn 2
     EQ  : (ty : PrimType) -> PrimFn 2
     GTE : (ty : PrimType) -> PrimFn 2
     GT  : (ty : PrimType) -> PrimFn 2

     StrLength : PrimFn 1
     StrHead : PrimFn 1
     StrTail : PrimFn 1
     StrIndex : PrimFn 2
     StrCons : PrimFn 2
     StrAppend : PrimFn 2
     StrReverse : PrimFn 1
     StrSubstr : PrimFn 3

     DoubleExp : PrimFn 1
     DoubleLog : PrimFn 1
     DoublePow : PrimFn 2
     DoubleSin : PrimFn 1
     DoubleCos : PrimFn 1
     DoubleTan : PrimFn 1
     DoubleASin : PrimFn 1
     DoubleACos : PrimFn 1
     DoubleATan : PrimFn 1
     DoubleSqrt : PrimFn 1
     DoubleFloor : PrimFn 1
     DoubleCeiling : PrimFn 1

     Cast : PrimType -> PrimType -> PrimFn 1
     BelieveMe : PrimFn 3
     Crash : PrimFn 2

%name PrimFn f

export
Show (PrimFn arity) where
  show (Add ty) = "+" ++ show ty
  show (Sub ty) = "-" ++ show ty
  show (Mul ty) = "*" ++ show ty
  show (Div ty) = "/" ++ show ty
  show (Mod ty) = "%" ++ show ty
  show (Neg ty) = "neg " ++ show ty
  show (ShiftL ty) = "shl " ++ show ty
  show (ShiftR ty) = "shr " ++ show ty
  show (BAnd ty) = "and " ++ show ty
  show (BOr ty) = "or " ++ show ty
  show (BXOr ty) = "xor " ++ show ty
  show (LT ty) = "<" ++ show ty
  show (LTE ty) = "<=" ++ show ty
  show (EQ ty) = "==" ++ show ty
  show (GTE ty) = ">=" ++ show ty
  show (GT ty) = ">" ++ show ty
  show StrLength = "op_strlen"
  show StrHead = "op_strhead"
  show StrTail = "op_strtail"
  show StrIndex = "op_strindex"
  show StrCons = "op_strcons"
  show StrAppend = "++"
  show StrReverse = "op_strrev"
  show StrSubstr = "op_strsubstr"
  show DoubleExp = "op_doubleExp"
  show DoubleLog = "op_doubleLog"
  show DoublePow = "op_doublePow"
  show DoubleSin = "op_doubleSin"
  show DoubleCos = "op_doubleCos"
  show DoubleTan = "op_doubleTan"
  show DoubleASin = "op_doubleASin"
  show DoubleACos = "op_doubleACos"
  show DoubleATan = "op_doubleATan"
  show DoubleSqrt = "op_doubleSqrt"
  show DoubleFloor = "op_doubleFloor"
  show DoubleCeiling = "op_doubleCeiling"
  show (Cast x y) = "cast-" ++ show x ++ "-" ++ show y
  show BelieveMe = "believe_me"
  show Crash = "crash"

export
[Sugared] Show (PrimFn arity) where
  show (Add ty) = "+"
  show (Sub ty) = "-"
  show (Mul ty) = "*"
  show (Div ty) = "div"
  show (Mod ty) = "mod"
  show (Neg ty) = "-"
  show (ShiftL ty) = "shiftl"
  show (ShiftR ty) = "shiftr"
  show (BAnd ty) = "&&"
  show (BOr ty) = "||"
  show (BXOr ty) = "xor"
  show (LT ty) = "<"
  show (LTE ty) = "<="
  show (EQ ty) = "=="
  show (GTE ty) = ">="
  show (GT ty) = ">"
  show StrLength = "length"
  show StrHead = "head"
  show StrTail = "tail"
  show StrIndex = "op_strindex"
  show StrCons = "::"
  show StrAppend = "++"
  show StrReverse = "reverse"
  show StrSubstr = "op_strsubstr"
  show DoubleExp = "exp"
  show DoubleLog = "log"
  show DoublePow = "pow"
  show DoubleSin = "sin"
  show DoubleCos = "cos"
  show DoubleTan = "tan"
  show DoubleASin = "asin"
  show DoubleACos = "acos"
  show DoubleATan = "atan"
  show DoubleSqrt = "sqrt"
  show DoubleFloor = "floor"
  show DoubleCeiling = "ceiling"
  show (Cast x y) = "cast-" ++ show x ++ "-" ++ show y
  show BelieveMe = "believe_me"
  show Crash = "crash"
