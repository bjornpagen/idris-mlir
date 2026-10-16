-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The primitives of Idris, as the tests know them: one table, made in the
||| order and the shape of Idris's own list of them (Core.Primitives), of
||| each primitive's name, its operation (whose family and host dependence
||| follow from it), its arguments with the values each may take, and its
||| result; and the integer types' widths, and what the integer primitives
||| mean, as the runtime documents them (runtime/idris_rt.h). Fuzz, Sem and
||| TwoLevels are written on it.
module Prims

import Prelude
import Data.Bits
import Data.List
import Data.String

%default total

------------------------------------------------------------------------------
-- Types
------------------------------------------------------------------------------

||| The types of primitive values.
public export
data Ty = TInt | TInt8 | TInt16 | TInt32 | TInt64 | TBits8 | TBits16 | TBits32 | TBits64
        | TInteger | TDouble | TChar | TString

||| A type as a program writes it, and as primitives' names carry it.
public export
tyName : Ty -> String
tyName TInt = "Int"
tyName TInt8 = "Int8"
tyName TInt16 = "Int16"
tyName TInt32 = "Int32"
tyName TInt64 = "Int64"
tyName TBits8 = "Bits8"
tyName TBits16 = "Bits16"
tyName TBits32 = "Bits32"
tyName TBits64 = "Bits64"
tyName TInteger = "Integer"
tyName TDouble = "Double"
tyName TChar = "Char"
tyName TString = "String"

||| A type's position in `Ty`: its identity.
public export
tyIndex : Ty -> Nat
tyIndex TInt = 0
tyIndex TInt8 = 1
tyIndex TInt16 = 2
tyIndex TInt32 = 3
tyIndex TInt64 = 4
tyIndex TBits8 = 5
tyIndex TBits16 = 6
tyIndex TBits32 = 7
tyIndex TBits64 = 8
tyIndex TInteger = 9
tyIndex TDouble = 10
tyIndex TChar = 11
tyIndex TString = 12

public export
Eq Ty where
  a == b = tyIndex a == tyIndex b

||| The integer types of a fixed width.
public export
fixedTys : List Ty
fixedTys = [TInt, TInt8, TInt16, TInt32, TInt64, TBits8, TBits16, TBits32, TBits64]

||| A fixed-width integer type's width.
public export
record Width where
  constructor MkWidth
  bits : Nat
  signed : Bool

||| A fixed-width integer type's width; no other type has one.
public export
widthOf : Ty -> Maybe Width
widthOf TInt = Just (MkWidth 64 True)
widthOf TInt8 = Just (MkWidth 8 True)
widthOf TInt16 = Just (MkWidth 16 True)
widthOf TInt32 = Just (MkWidth 32 True)
widthOf TInt64 = Just (MkWidth 64 True)
widthOf TBits8 = Just (MkWidth 8 False)
widthOf TBits16 = Just (MkWidth 16 False)
widthOf TBits32 = Just (MkWidth 32 False)
widthOf TBits64 = Just (MkWidth 64 False)
widthOf TInteger = Nothing
widthOf TDouble = Nothing
widthOf TChar = Nothing
widthOf TString = Nothing

||| The ten integer types: the fixed ones and Integer.
public export
data IsInteger : Ty -> Type where
  IInt : IsInteger TInt
  IInt8 : IsInteger TInt8
  IInt16 : IsInteger TInt16
  IInt32 : IsInteger TInt32
  IInt64 : IsInteger TInt64
  IBits8 : IsInteger TBits8
  IBits16 : IsInteger TBits16
  IBits32 : IsInteger TBits32
  IBits64 : IsInteger TBits64
  IInteger : IsInteger TInteger

------------------------------------------------------------------------------
-- What the integer primitives mean
------------------------------------------------------------------------------

public export
pow2 : Nat -> Integer
pow2 k = shiftL 1 k

||| `n mod m` for `m > 0`, never negative (Python's `%`).
public export
modulo : Integer -> Integer -> Integer
modulo n m =
  if n >= 0 then n `mod` m
     else let r = negate n `mod` m in if r == 0 then 0 else m - r

||| `n` as a value of the width: modulo 2^bits, and read as two's
||| complement when the width is signed.
public export
wrap : Width -> Integer -> Integer
wrap t n =
  let m = modulo n (pow2 t.bits)
  in if t.signed && m >= pow2 (pred t.bits) then m - pow2 t.bits else m

||| A fixed-width type's least and greatest values.
public export
bounds : Ty -> Maybe (Integer, Integer)
bounds t = map range (widthOf t)
  where
    range : Width -> (Integer, Integer)
    range w =
      if w.signed
         then (negate (pow2 (pred w.bits)), pow2 (pred w.bits) - 1)
         else (0, pow2 w.bits - 1)

||| Euclidean division: the remainder is never negative.
public export
euclid : Integer -> Integer -> (Integer, Integer)
euclid a b =
  let q0 = abs a `div` abs b
      q = if (a < 0) == (b < 0) then q0 else negate q0
      r = a - b * q
  in if r < 0 then (if b > 0 then (q - 1, r + b) else (q + 1, r - b))
              else (q, r)

||| A fixed-width division: Euclidean and wrapped when signed (so the least
||| value divided by -1 is itself), else of the two naturals.
public export
quotient : Width -> Integer -> Integer -> Integer
quotient t a b = if t.signed then wrap t (fst (euclid a b)) else a `div` b

public export
remainder : Width -> Integer -> Integer -> Integer
remainder t a b = if t.signed then wrap t (snd (euclid a b)) else a `mod` b

||| A bitwise operation of a width, on the values' two's complement: `op`
||| is applied to their representatives modulo 2^bits, which are never
||| negative, so only the bits of naturals are ever asked of the host.
public export
bitwise : Width -> (Integer -> Integer -> Integer) -> Integer -> Integer -> Integer
bitwise t op a b = wrap t (op (modulo a (pow2 t.bits)) (modulo b (pow2 t.bits)))

||| `n` divided by `m > 0`, rounded down.
public export
floorDiv : Integer -> Integer -> Integer
floorDiv n m = if n >= 0 then n `div` m else negate ((negate n + m - 1) `div` m)

||| An Integer shift, as Scheme's ash moves a value: `a` moved `s` places,
||| left or right, the other way when `s` is negative; a right shift
||| rounds down, so it fills with the sign.
public export
bigShifted : (left : Bool) -> Integer -> Integer -> Integer
bigShifted left a s =
  let places = if left then s else negate s
  in if places >= 0 then a * pow2 (cast places)
                    else floorDiv a (pow2 (cast (negate places)))

||| A shift of a value of a width: the Integer shift, wrapped to the width.
||| Moved as many places as the width has, either way, a value of it has
||| no bit left that a longer move would take, so the amount is cut there
||| and a huge one builds no huge Integer.
public export
shifted : Width -> (left : Bool) -> Integer -> Integer -> Integer
shifted t left a s =
  let most = natToInteger t.bits
  in wrap t (bigShifted left a (max (negate most) (min most s)))

||| The number of binary digits of `n`'s magnitude. The magnitude bounds
||| the halvings, each of which takes at least 1 from it, so it is their
||| structural bound, never what stops them.
bitLength : Integer -> Nat
bitLength n = halvings (integerToNat (abs n)) (abs n)
  where
    halvings : Nat -> Integer -> Nat
    halvings Z _ = 0
    halvings (S fuel) m = if m == 0 then 0 else S (halvings fuel (m `div` 2))

||| An Integer bitwise operation, on the infinite two's complement: both
||| values, and so the result, fit a signed width of two bits more than
||| either's magnitude has, where `bitwise` computes it.
public export
bigBitwise : (Integer -> Integer -> Integer) -> Integer -> Integer -> Integer
bigBitwise op a b = bitwise (MkWidth (2 + max (bitLength a) (bitLength b)) True) op a b

------------------------------------------------------------------------------
-- The primitives
------------------------------------------------------------------------------

||| The values an argument may take: the primitive's documented
||| precondition, whose breach ends the program, and nothing else.
public export
data Domain = Anything | NonZero | Finite | NonEmpty | IndexInto Nat | SmallShift

public export
data Family = Arith | Negate | DivMod | Bitwise | Shift | Compare | Cast | Text | DoubleFn

||| What a primitive does: Idris's own operations (its PrimFn), the types
||| aside, which are a primitive's arguments and result. `Convert` is
||| Idris's Cast.
public export
data Op = Add | Sub | Mul | Neg | Div | Mod | Shl | Shr | And | Or | Xor
        | Lt | Lte | Eq | Gte | Gt
        | StrLength | StrHead | StrTail | StrIndex | StrCons | StrAppend | StrReverse | StrSubstr
        | DoubleExp | DoubleLog | DoublePow | DoubleSin | DoubleCos | DoubleTan
        | DoubleASin | DoubleACos | DoubleATan | DoubleSqrt | DoubleFloor | DoubleCeiling
        | Convert

||| An operation's position in `Op`: its identity.
public export
opIndex : Op -> Nat
opIndex Add = 0
opIndex Sub = 1
opIndex Mul = 2
opIndex Neg = 3
opIndex Div = 4
opIndex Mod = 5
opIndex Shl = 6
opIndex Shr = 7
opIndex And = 8
opIndex Or = 9
opIndex Xor = 10
opIndex Lt = 11
opIndex Lte = 12
opIndex Eq = 13
opIndex Gte = 14
opIndex Gt = 15
opIndex StrLength = 16
opIndex StrHead = 17
opIndex StrTail = 18
opIndex StrIndex = 19
opIndex StrCons = 20
opIndex StrAppend = 21
opIndex StrReverse = 22
opIndex StrSubstr = 23
opIndex DoubleExp = 24
opIndex DoubleLog = 25
opIndex DoublePow = 26
opIndex DoubleSin = 27
opIndex DoubleCos = 28
opIndex DoubleTan = 29
opIndex DoubleASin = 30
opIndex DoubleACos = 31
opIndex DoubleATan = 32
opIndex DoubleSqrt = 33
opIndex DoubleFloor = 34
opIndex DoubleCeiling = 35
opIndex Convert = 36

public export
Eq Op where
  a == b = opIndex a == opIndex b

||| The family of an operation.
public export
family : Op -> Family
family Add = Arith
family Sub = Arith
family Mul = Arith
family Neg = Negate
family Div = DivMod
family Mod = DivMod
family Shl = Shift
family Shr = Shift
family And = Bitwise
family Or = Bitwise
family Xor = Bitwise
family Lt = Compare
family Lte = Compare
family Eq = Compare
family Gte = Compare
family Gt = Compare
family StrLength = Text
family StrHead = Text
family StrTail = Text
family StrIndex = Text
family StrCons = Text
family StrAppend = Text
family StrReverse = Text
family StrSubstr = Text
family DoubleExp = DoubleFn
family DoubleLog = DoubleFn
family DoublePow = DoubleFn
family DoubleSin = DoubleFn
family DoubleCos = DoubleFn
family DoubleTan = DoubleFn
family DoubleASin = DoubleFn
family DoubleACos = DoubleFn
family DoubleATan = DoubleFn
family DoubleSqrt = DoubleFn
family DoubleFloor = DoubleFn
family DoubleCeiling = DoubleFn
family Convert = Cast

||| Why an operation's value depends on the host, when it does: Exp, Log,
||| Pow and the trigonometric functions are libm's, which is not correctly
||| rounded, so the last places of their values are the platform's.
public export
hostOf : Op -> Maybe String
hostOf DoubleExp = Just "libm"
hostOf DoubleLog = Just "libm"
hostOf DoublePow = Just "libm"
hostOf DoubleSin = Just "libm"
hostOf DoubleCos = Just "libm"
hostOf DoubleTan = Just "libm"
hostOf DoubleASin = Just "libm"
hostOf DoubleACos = Just "libm"
hostOf DoubleATan = Just "libm"
hostOf _ = Nothing

||| The word Idris spells an operation's primitives with.
spelling : Op -> String
spelling Add = "add"
spelling Sub = "sub"
spelling Mul = "mul"
spelling Neg = "negate"
spelling Div = "div"
spelling Mod = "mod"
spelling Shl = "shl"
spelling Shr = "shr"
spelling And = "and"
spelling Or = "or"
spelling Xor = "xor"
spelling Lt = "lt"
spelling Lte = "lte"
spelling Eq = "eq"
spelling Gte = "gte"
spelling Gt = "gt"
spelling StrLength = "strLength"
spelling StrHead = "strHead"
spelling StrTail = "strTail"
spelling StrIndex = "strIndex"
spelling StrCons = "strCons"
spelling StrAppend = "strAppend"
spelling StrReverse = "strReverse"
spelling StrSubstr = "strSubstr"
spelling DoubleExp = "doubleExp"
spelling DoubleLog = "doubleLog"
spelling DoublePow = "doublePow"
spelling DoubleSin = "doubleSin"
spelling DoubleCos = "doubleCos"
spelling DoubleTan = "doubleTan"
spelling DoubleASin = "doubleASin"
spelling DoubleACos = "doubleACos"
spelling DoubleATan = "doubleATan"
spelling DoubleSqrt = "doubleSqrt"
spelling DoubleFloor = "doubleFloor"
spelling DoubleCeiling = "doubleCeiling"
spelling Convert = "cast"

||| The name of an operation's primitive on one type, as a program writes
||| it: `prim__<word>_<type>`.
public export
named : Op -> Ty -> String
named op t = "prim__" ++ spelling op ++ "_" ++ tyName t

||| The name of a cast, as a program writes it: `prim__cast_<from><to>`.
public export
castNamed : Ty -> Ty -> String
castNamed from to = "prim__" ++ spelling Convert ++ "_" ++ tyName from ++ tyName to

||| What the integer operations mean on the integers, by operation.
public export
arithmetic : List (Op, Integer -> Integer -> Integer)
arithmetic = [(Add, (+)), (Sub, (-)), (Mul, (*))]

public export
logical : List (Op, Integer -> Integer -> Integer)
logical = [(And, (.&.)), (Or, (.|.)), (Xor, xor)]

public export
comparisons : List (Op, Integer -> Integer -> Bool)
comparisons = [(Lt, (<)), (Lte, (<=)), (Eq, (==)), (Gte, (>=)), (Gt, (>))]

||| The shifts: whether each moves left.
public export
shifts : List (Op, Bool)
shifts = [(Shl, True), (Shr, False)]

public export
record Prim where
  constructor MkPrim
  ||| As a program writes it: "prim__add_Int", "prim__strLength", "prim__doubleExp".
  name : String
  op : Op
  args : List (Ty, Domain)
  result : Ty

-- Idris's lists of types, in its order.
integralTypes : List Ty
integralTypes = [TInt, TInt8, TInt16, TInt32, TInt64, TInteger, TBits8, TBits16, TBits32, TBits64]

numTypes : List Ty
numTypes = integralTypes ++ [TDouble]

primTypes : List Ty
primTypes = numTypes ++ [TString, TChar]

||| Two values of a type to one.
binary : Op -> (Ty -> Domain) -> Ty -> Prim
binary op second t = MkPrim (named op t) op [(t, Anything), (t, second t)] t

compareOn : Op -> Ty -> Prim
compareOn op t = MkPrim (named op t) op [(t, Anything), (t, Anything)] TInt

||| A primitive of no one type: `prim__<word>`.
whole : Op -> List (Ty, Domain) -> Ty -> Prim
whole op = MkPrim ("prim__" ++ spelling op) op

||| Idris's divisions by 0 of an integer type crash (idr-lower checks the
||| divisor); a Double's give an infinity or NaN.
divisor : Ty -> Domain
divisor t = if t `elem` integralTypes then NonZero else Anything

||| A left shift past what any integer can hold ends the process (the
||| runtime's ash), and a right shift by a negative amount is one: Integer,
||| which has no width to wrap to, shifts by small amounts. A fixed width's
||| shift is defined for every amount.
amount : Ty -> Domain
amount t = maybe SmallShift (const Anything) (widthOf t)

||| A Double cast to an integer type crashes on NaN and the infinities
||| (idr-lower checks it is finite). Every other cast is total: from String
||| it reads 0 from text that is no literal, and to Char it gives 0 for a
||| value that is not a scalar.
operand : Ty -> Ty -> Domain
operand TDouble to = if to `elem` integralTypes then Finite else Anything
operand _ _ = Anything

doubleFn : Op -> Nat -> Prim
doubleFn op arity = whole op (replicate arity (TDouble, Anything)) TDouble

||| Every primitive but `believe_me` and `crash`, in Idris's order.
public export
prims : List Prim
prims =
     [ binary Add (const Anything) t | t <- numTypes ]
  ++ [ binary Sub (const Anything) t | t <- numTypes ]
  ++ [ binary Mul (const Anything) t | t <- numTypes ]
  ++ [ MkPrim (named Neg t) Neg [(t, Anything)] t | t <- numTypes ]
  ++ [ binary Div divisor t | t <- numTypes ]
  ++ [ binary Mod divisor t | t <- integralTypes ]
  ++ [ binary op amount t | (op, _) <- shifts, t <- integralTypes ]
  ++ [ binary op (const Anything) t | (op, _) <- logical, t <- integralTypes ]
  ++ [ compareOn op t | (op, _) <- comparisons, t <- primTypes ]
  ++ [ whole StrLength [(TString, Anything)] TInt
     -- A string's first scalar, its rest and one at an index need a scalar
     -- there (idr-lower checks, and crashes on, an empty string and an
     -- index outside it).
     , whole StrHead [(TString, NonEmpty)] TChar
     , whole StrTail [(TString, NonEmpty)] TString
     , whole StrIndex [(TString, NonEmpty), (TInt, IndexInto 0)] TChar
     , whole StrCons [(TChar, Anything), (TString, Anything)] TString
     , whole StrAppend [(TString, Anything), (TString, Anything)] TString
     , whole StrReverse [(TString, Anything)] TString
     -- Any start and length: the runtime counts a negative one as 0.
     , whole StrSubstr [(TInt, Anything), (TInt, Anything), (TString, Anything)] TString
     ]
  ++ [ doubleFn op 1 | op <- [DoubleExp, DoubleLog] ]
  ++ [ doubleFn DoublePow 2 ]
  ++ [ doubleFn op 1 | op <- [DoubleSin, DoubleCos, DoubleTan, DoubleASin, DoubleACos, DoubleATan, DoubleSqrt, DoubleFloor, DoubleCeiling] ]
  -- Every cast but String to Char, Double to Char and Char to Double,
  -- which Idris does not have.
  ++ [ MkPrim (castNamed from to) Convert [(from, operand from to)] to
     | from <- primTypes, to <- primTypes
     , from /= to && not (from == TString && to == TChar)
         && not (from == TDouble && to == TChar) && not (from == TChar && to == TDouble) ]
