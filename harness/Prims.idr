-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The primitives of Idris, as the tests know them: one table of each
||| primitive's name as a program writes it, its operation (whose family and
||| host dependence follow from it), its parameters with the values each may
||| take, and its result; the integer types' widths, and what the integer
||| primitives mean, as the runtime documents them (runtime/idris_rt.h); and
||| the closed expressions over the table, as a program writes them. The
||| meanings are the oracle's own, written from the documentation, never
||| read from the compiler. Fuzz, Sem and TwoLevels are written on it.
module Prims

import Prelude
import Data.Bits
import Data.List
import Data.List.Elem
import Data.Maybe
import Data.String
import Decidable.Equality

%default total

------------------------------------------------------------------------------
-- Types
------------------------------------------------------------------------------

||| The integer types of a fixed width.
public export
data FixedTy = FInt | FInt8 | FInt16 | FInt32 | FInt64 | FBits8 | FBits16 | FBits32 | FBits64

||| The integer types: one of a fixed width, or Integer, which has none.
public export
data IntTy = Fixed FixedTy | Big

||| The types of primitive values.
public export
data Ty = TIntegral IntTy | TDouble | TChar | TString

public export
int : Ty
int = TIntegral (Fixed FInt)

public export
integer : Ty
integer = TIntegral Big

fixedName : FixedTy -> String
fixedName FInt = "Int"
fixedName FInt8 = "Int8"
fixedName FInt16 = "Int16"
fixedName FInt32 = "Int32"
fixedName FInt64 = "Int64"
fixedName FBits8 = "Bits8"
fixedName FBits16 = "Bits16"
fixedName FBits32 = "Bits32"
fixedName FBits64 = "Bits64"

||| A type as a program writes it, and as primitives' names carry it.
public export
tyName : Ty -> String
tyName (TIntegral (Fixed f)) = fixedName f
tyName (TIntegral Big) = "Integer"
tyName TDouble = "Double"
tyName TChar = "Char"
tyName TString = "String"

||| A fixed-width type's position in `FixedTy`: its identity.
public export
fixedIndex : FixedTy -> Nat
fixedIndex FInt = 0
fixedIndex FInt8 = 1
fixedIndex FInt16 = 2
fixedIndex FInt32 = 3
fixedIndex FInt64 = 4
fixedIndex FBits8 = 5
fixedIndex FBits16 = 6
fixedIndex FBits32 = 7
fixedIndex FBits64 = 8

||| An integer type's identity: a fixed width's, then Integer's.
public export
intIndex : IntTy -> Nat
intIndex (Fixed f) = fixedIndex f
intIndex Big = 9

||| A type's identity: an integer type's, then the others'.
public export
tyIndex : Ty -> Nat
tyIndex (TIntegral i) = intIndex i
tyIndex TDouble = 10
tyIndex TChar = 11
tyIndex TString = 12

public export
Eq FixedTy where
  a == b = fixedIndex a == fixedIndex b

public export
Eq IntTy where
  a == b = intIndex a == intIndex b

public export
Eq Ty where
  a == b = tyIndex a == tyIndex b

||| Two fixed-width types of one index are one type. The coverage of these
||| clauses is the proof: no two types share an index.
sameIndex : (a, b : FixedTy) -> (0 _ : fixedIndex a = fixedIndex b) -> a = b
sameIndex FInt FInt _ = Refl
sameIndex FInt8 FInt8 _ = Refl
sameIndex FInt16 FInt16 _ = Refl
sameIndex FInt32 FInt32 _ = Refl
sameIndex FInt64 FInt64 _ = Refl
sameIndex FBits8 FBits8 _ = Refl
sameIndex FBits16 FBits16 _ = Refl
sameIndex FBits32 FBits32 _ = Refl
sameIndex FBits64 FBits64 _ = Refl

||| Whether two types are one, with the proof when they are.
public export
sameTy : (a, b : Ty) -> Maybe (a = b)
sameTy (TIntegral (Fixed a)) (TIntegral (Fixed b)) = case decEq (fixedIndex a) (fixedIndex b) of
  Yes same => Just (cong (TIntegral . Fixed) (sameIndex a b same))
  No _ => Nothing
sameTy (TIntegral Big) (TIntegral Big) = Just Refl
sameTy TDouble TDouble = Just Refl
sameTy TChar TChar = Just Refl
sameTy TString TString = Just Refl
sameTy _ _ = Nothing

||| The integer types of a fixed width, in the order the tests make them.
public export
fixedTys : List FixedTy
fixedTys = [FInt, FInt8, FInt16, FInt32, FInt64, FBits8, FBits16, FBits32, FBits64]

||| A fixed-width integer type's width.
public export
record Width where
  constructor MkWidth
  bits : Nat
  signed : Bool

public export
width : FixedTy -> Width
width FInt = MkWidth 64 True
width FInt8 = MkWidth 8 True
width FInt16 = MkWidth 16 True
width FInt32 = MkWidth 32 True
width FInt64 = MkWidth 64 True
width FBits8 = MkWidth 8 False
width FBits16 = MkWidth 16 False
width FBits32 = MkWidth 32 False
width FBits64 = MkWidth 64 False

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
bounds : FixedTy -> (Integer, Integer)
bounds f =
  let w = width f in
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
||| structural bound, never what stops them. The bound is essential:
||| Integer is a primitive, with no lemma relating its halving to a
||| measure that Nat could carry, and a view of the magnitude as a Nat
||| (halfRec) would take as many steps as the value has units, 2^128 in
||| the pools.
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

||| What a parameter offers the parameters after it: a string drawn
||| non-empty, whose scalars an index may point into, or nothing.
public export
data Earlier = IndexableString | Opaque

||| The values a parameter may take, given what the parameters before it
||| offer (the latest first): the primitive's documented precondition,
||| whose breach ends the program, and nothing else.
public export
data Domain : List Earlier -> Type where
  Anything : Domain before
  NonZero : Domain before
  Finite : Domain before
  NonEmpty : Domain before
  SmallShift : Domain before
  ||| An index into the scalars of the string that `Elem` points at.
  IndexInto : Elem IndexableString before -> Domain before

||| What a parameter of a type and a domain offers the parameters after it:
||| a NonEmpty string its scalars, anything else nothing. The domain is
||| matched first, so that every domain but NonEmpty offers nothing
||| whatever the type.
public export
offers : Ty -> Domain before -> Earlier
offers t NonEmpty = stringOffers t
  where
    stringOffers : Ty -> Earlier
    stringOffers TString = IndexableString
    stringOffers _ = Opaque
offers _ _ = Opaque

||| A primitive's parameters, each with its type and its domain, the domain
||| knowing what the parameters before it offer.
public export
data Params : List Earlier -> Type where
  Done : Params before
  Param : (t : Ty) -> (d : Domain before) -> Params (offers t d :: before) -> Params before

||| The parameters' types, left to right.
public export
paramTys : Params before -> List Ty
paramTys Done = []
paramTys (Param t _ rest) = t :: paramTys rest

||| How many parameters there are.
public export
arity : Params before -> Nat
arity Done = 0
arity (Param _ _ rest) = S (arity rest)

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

public export
Ord Op where
  compare a b = compare (opIndex a) (opIndex b)

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
export
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
  args : Params []
  result : Ty

-- Idris's lists of types, in its order.
integralTypes : List IntTy
integralTypes = [Fixed FInt, Fixed FInt8, Fixed FInt16, Fixed FInt32, Fixed FInt64, Big, Fixed FBits8, Fixed FBits16, Fixed FBits32, Fixed FBits64]

numTypes : List Ty
numTypes = map TIntegral integralTypes ++ [TDouble]

primTypes : List Ty
primTypes = numTypes ++ [TString, TChar]

||| Two values of a type to one, the second in its domain.
public export
binary : Op -> (t : Ty) -> Domain [Opaque] -> Prim
binary op t second = MkPrim (named op t) op (Param t Anything (Param t second Done)) t

compareOn : Op -> Ty -> Prim
compareOn op t = MkPrim (named op t) op (Param t Anything (Param t Anything Done)) int

||| A primitive of no one type: `prim__<word>`.
whole : Op -> Params [] -> Ty -> Prim
whole op = MkPrim ("prim__" ++ spelling op) op

||| Idris's divisions by 0 of an integer type crash, at the division's
||| site; a Double's give an infinity or NaN.
public export
divisor : Ty -> Domain before
divisor (TIntegral _) = NonZero
divisor _ = Anything

||| A left shift past what any integer can hold ends the process (the
||| runtime's ash), and a right shift by a negative amount is one: Integer,
||| which has no width to wrap to, shifts by small amounts. A fixed width's
||| shift is defined for every amount.
amount : IntTy -> Domain before
amount (Fixed _) = Anything
amount Big = SmallShift

||| A Double cast to an integer type crashes on NaN and the infinities
||| (a crash at the cast's site). Every other cast is total: from String
||| it reads 0 from text that is no literal, and to Char it gives 0 for a
||| value that is not a scalar.
operand : Ty -> Ty -> Domain before
operand TDouble (TIntegral _) = Finite
operand _ _ = Anything

||| A type's negation, `prim__negate_<t>`.
public export
negateOn : Ty -> Prim
negateOn t = MkPrim (named Neg t) Neg (Param t Anything Done) t

||| A type's division, `prim__div_<t>`.
public export
divOn : Ty -> Prim
divOn t = binary Div t (divisor t)

||| `n` Doubles, each any.
doubles : Nat -> Params before
doubles Z = Done
doubles (S n) = Param TDouble Anything (doubles n)

doubleFn : Op -> Nat -> Prim
doubleFn op n = whole op (doubles n) TDouble

||| Every primitive but `believe_me` and `crash`, in Idris's order.
public export
prims : List Prim
prims =
     [ binary Add t Anything | t <- numTypes ]
  ++ [ binary Sub t Anything | t <- numTypes ]
  ++ [ binary Mul t Anything | t <- numTypes ]
  ++ [ negateOn t | t <- numTypes ]
  ++ [ divOn t | t <- numTypes ]
  ++ [ binary Mod (TIntegral i) NonZero | i <- integralTypes ]
  ++ [ binary op (TIntegral i) (amount i) | (op, _) <- shifts, i <- integralTypes ]
  ++ [ binary op (TIntegral i) Anything | (op, _) <- logical, i <- integralTypes ]
  ++ [ compareOn op t | (op, _) <- comparisons, t <- primTypes ]
  ++ [ whole StrLength (Param TString Anything Done) int
     -- A string's first scalar, its rest and one at an index need a scalar
     -- there (an empty string, and an index outside it, crash at the
     -- primitive's site).
     , whole StrHead (Param TString NonEmpty Done) TChar
     , whole StrTail (Param TString NonEmpty Done) TString
     , whole StrIndex (Param TString NonEmpty (Param int (IndexInto Here) Done)) TChar
     , whole StrCons (Param TChar Anything (Param TString Anything Done)) TString
     , whole StrAppend (Param TString Anything (Param TString Anything Done)) TString
     , whole StrReverse (Param TString Anything Done) TString
     -- Any start and length: the runtime counts a negative one as 0.
     , whole StrSubstr (Param int Anything (Param int Anything (Param TString Anything Done))) TString
     ]
  ++ [ doubleFn op 1 | op <- [DoubleExp, DoubleLog] ]
  ++ [ doubleFn DoublePow 2 ]
  ++ [ doubleFn op 1 | op <- [DoubleSin, DoubleCos, DoubleTan, DoubleASin, DoubleACos, DoubleATan, DoubleSqrt, DoubleFloor, DoubleCeiling] ]
  -- Every cast but String to Char, Double to Char and Char to Double,
  -- which Idris does not have.
  ++ [ MkPrim (castNamed from to) Convert (Param from (operand from to) Done) to
     | from <- primTypes, to <- primTypes
     , from /= to && not (from == TString && to == TChar)
         && not (from == TDouble && to == TChar) && not (from == TChar && to == TDouble) ]

------------------------------------------------------------------------------
-- Expressions
------------------------------------------------------------------------------

||| A Double literal's sign: a negative one is written in parentheses.
public export
data Sign = NonNegative | Negative

mutual
  ||| A primitive's arguments: an expression of each parameter's type.
  public export
  data Args : Params before -> Type where
    Nil : Args Done
    (::) : {0 t : Ty} -> {0 d : Domain before} -> {0 rest : Params (offers t d :: before)} ->
           Expr t -> Args rest -> Args (Param t d rest)

  ||| A closed expression, well typed by construction: a literal, held as
  ||| its value, a primitive applied, or the fuzzer's sum type's helper.
  public export
  data Expr : Ty -> Type where
    ||| Inside its type's bounds (Integer's: any).
    IntLit : (i : IntTy) -> Integer -> Expr (TIntegral i)
    ||| A Double as written, its magnitude a literal: "0.1", "1.0e300".
    DoubleLit : Sign -> (magnitude : String) -> Expr TDouble
    CharLit : Char -> Expr TChar
    StringLit : String -> Expr TString
    App : (p : Prim) -> Args p.args -> Expr p.result
    ||| The sum type's helper; `k` is a literal from 0 to 2, its constructor.
    SData : (k : Expr Prims.int) -> Expr Prims.int -> Expr TDouble -> Expr Prims.int

||| A literal of an integer as written: in parentheses when negative.
public export
integerText : Integer -> String
integerText n = if n < 0 then "(" ++ show n ++ ")" else show n

||| A function applied, as a program writes it.
public export
applied : String -> List String -> String
applied f as = "(" ++ f ++ foldr (\a, rest => " " ++ a ++ rest) ")" as

mutual
  ||| An expression as a program writes it: an integer in parentheses when
  ||| negative, a Double likewise, a Char or a String as `show` writes it
  ||| (a scalar past ASCII as its decimal escape on both hosts), and an
  ||| application in parentheses.
  public export
  source : Expr t -> String
  source (IntLit _ v) = integerText v
  source (DoubleLit NonNegative m) = m
  source (DoubleLit Negative m) = "(-" ++ m ++ ")"
  source (CharLit c) = show c
  source (StringLit s) = show s
  source (App p as) = applied p.name (sources as)
  source (SData k i x) = applied "sdata" [source k, source i, source x]

  sources : Args ps -> List String
  sources [] = []
  sources (e :: es) = source e :: sources es

mutual
  ||| What stdin holds for an expression read from it: a literal's line, the
  ||| value as text (a negative Double with its sign, a Char or a String
  ||| as itself); an expression's lines, its literals' in order.
  public export
  input : Expr t -> String
  input (IntLit _ v) = show v
  input (DoubleLit NonNegative m) = m
  input (DoubleLit Negative m) = "-" ++ m
  input (CharLit c) = singleton c
  input (StringLit s) = s
  input (App _ as) = joinBy "\n" (inputs as)
  input (SData k i x) = joinBy "\n" [input k, input i, input x]

  inputs : Args ps -> List String
  inputs [] = []
  inputs (e :: es) = input e :: inputs es

mutual
  ||| Why an expression's value depends on the host, when it does: the
  ||| first primitive of it whose operation's value is the host's, by name.
  public export
  hostReason : Expr t -> Maybe String
  hostReason (App p as) = map (\why => p.name ++ ": " ++ why) (hostOf p.op) <|> hostReasonArgs as
  hostReason (SData k i x) = hostReason k <|> hostReason i <|> hostReason x
  hostReason (IntLit _ _) = Nothing
  hostReason (DoubleLit _ _) = Nothing
  hostReason (CharLit _) = Nothing
  hostReason (StringLit _) = Nothing

  hostReasonArgs : Args ps -> Maybe String
  hostReasonArgs [] = Nothing
  hostReasonArgs (e :: es) = hostReason e <|> hostReasonArgs es

||| Whether an expression's value is the host's: some primitive of it is.
public export
onHost : Expr t -> Bool
onHost e = isJust (hostReason e)

||| How a value of a type is printed: as a string, written by output fusion.
public export
printer : Ty -> String -> String
printer TString e = e
printer TChar e = "(" ++ castNamed int TString ++ " (" ++ castNamed TChar int ++ " " ++ e ++ "))"
printer t e = "(" ++ castNamed t TString ++ " " ++ e ++ ")"

||| The statement a generated program prints a value with: its label, a
||| space and the value, a line of its own.
public export
printLine : (label : String) -> Ty -> String -> String
printLine label t e = "putStrLn (prim__strAppend \"" ++ label ++ " \" " ++ printer t e ++ ")"

||| A line `printLine` printed, read back: its label and its value.
public export
labelled : String -> (String, String)
labelled l =
  let (label, rest) = break (== ' ') l in
  (label, maybe "" snd (strUncons rest))
