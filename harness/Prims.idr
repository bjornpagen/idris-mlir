-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The builtins of Idris, as the tests know them: one table, each builtin
||| with what is the test's own, its spelling as a program writes it and its
||| meaning, the oracle's, written from upstream's language and the
||| runtime's documentation (runtime/idris_rt.h, runtime/Big, runtime/End),
||| never read from the compiler; and the op of the dialect's specification
||| it names, from which everything it is in the dialect is read: its
||| family, whether the compiler computes it of constants, and the guard
||| where it crashes, with the cause its crash names. The specification
||| keeps base's names out, and the harness imports neither the checker
||| nor the frontend, so the spelling is held here and nowhere else. Then the
||| closed expressions over the table, as a program writes them, and what
||| the oracle predicts of one: its value, or the crash its evaluation
||| reaches. Fuzz and Sem are written on it.
module Prims

import Prelude
import Data.Bits
import Data.Fin
import Data.List
import Data.List1
import Data.Maybe
import Data.String
import Data.Vect
import Decidable.Equality

import IdrisMLIR.Spec.Core.Admitted
import IdrisMLIR.Spec.Core.Op
import IdrisMLIR.Spec.Ops.Bigs
import IdrisMLIR.Spec.Ops.Checks
import IdrisMLIR.Spec.Ops.Numeric
import IdrisMLIR.Spec.Ops.Scalars
import IdrisMLIR.Spec.Ops.Shapes
import IdrisMLIR.Spec.Ops.Strings
import IdrisMLIR.Spec.Runtime.Endings

import Facts

%default total

------------------------------------------------------------------------------
-- Types
------------------------------------------------------------------------------

||| The integer types of a fixed width.
public export
data FixedTy = FInt | FInt8 | FInt16 | FInt32 | FInt64 | FBits8 | FBits16 | FBits32 | FBits64

||| The integer types: one of a fixed width, or Integer, which has none.
public export
data IntTy = Sized FixedTy | Big

||| The types of primitive values.
public export
data Ty = TIntegral IntTy | TDouble | TChar | TString

public export
tInt : Ty
tInt = TIntegral (Sized FInt)

public export
tInteger : Ty
tInteger = TIntegral Big

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

||| A type as a program writes it, and as builtins' names carry it.
public export
tyName : Ty -> String
tyName (TIntegral (Sized f)) = fixedName f
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
intIndex (Sized f) = fixedIndex f
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
sameTy (TIntegral (Sized a)) (TIntegral (Sized b)) = case decEq (fixedIndex a) (fixedIndex b) of
  Yes same => Just (cong (TIntegral . Sized) (sameIndex a b same))
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

||| A fixed-width integer type's width, and how its bits read: as two's
||| complement, or as the natural they are.
public export
record Width where
  constructor MkWidth
  bits : Nat
  signedness : Signedness

public export
width : FixedTy -> Width
width FInt = MkWidth 64 Signed
width FInt8 = MkWidth 8 Signed
width FInt16 = MkWidth 16 Signed
width FInt32 = MkWidth 32 Signed
width FInt64 = MkWidth 64 Signed
width FBits8 = MkWidth 8 Unsigned
width FBits16 = MkWidth 16 Unsigned
width FBits32 = MkWidth 32 Unsigned
width FBits64 = MkWidth 64 Unsigned

------------------------------------------------------------------------------
-- What the integer builtins mean
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
  in case t.signedness of
       Signed => if m >= pow2 (pred t.bits) then m - pow2 t.bits else m
       Unsigned => m

||| A fixed-width type's least and greatest values.
public export
bounds : FixedTy -> (Integer, Integer)
bounds f =
  let w = width f in
  case w.signedness of
    Signed => (negate (pow2 (pred w.bits)), pow2 (pred w.bits) - 1)
    Unsigned => (0, pow2 w.bits - 1)

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
quotient t a b = case t.signedness of
  Signed => wrap t (fst (euclid a b))
  Unsigned => a `div` b

public export
remainder : Width -> Integer -> Integer -> Integer
remainder t a b = case t.signedness of
  Signed => wrap t (snd (euclid a b))
  Unsigned => a `mod` b

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

||| An Integer shift, as Scheme's ash moves a value: `a` moved `s` places
||| the shift's way, the other way when `s` is negative; a move to the low
||| bits rounds down, so it fills with the sign.
public export
bigShifted : ShiftDirection -> Integer -> Integer -> Integer
bigShifted dir a s =
  let places = case dir of
        Leftward => s
        Rightward => negate s
  in if places >= 0 then a * pow2 (integerToNat places)
                    else floorDiv a (pow2 (integerToNat (negate places)))

||| A shift of a value of a width: the Integer shift, wrapped to the width.
||| Moved as many places as the width has, either way, a value of it has
||| no bit left that a longer move would take, so the amount is cut there
||| and a huge one builds no huge Integer.
public export
shifted : Width -> ShiftDirection -> Integer -> Integer -> Integer
shifted t dir a s =
  let most = natToInteger t.bits
  in wrap t (bigShifted dir a (max (negate most) (min most s)))

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
bigBitwise op a b = bitwise (MkWidth (2 + max (bitLength a) (bitLength b)) Signed) op a b

||| A value as a value of an integer type: wrapped to a fixed width, any
||| for Integer.
public export
inRange : IntTy -> Integer -> Integer
inRange (Sized f) v = wrap (width f) v
inRange Big v = v

divide : IntTy -> Integer -> Integer -> Integer
divide (Sized f) a b = quotient (width f) a b
divide Big a b = fst (euclid a b)

modulus : IntTy -> Integer -> Integer -> Integer
modulus (Sized f) a b = remainder (width f) a b
modulus Big a b = snd (euclid a b)

bitwiseIn : IntTy -> (Integer -> Integer -> Integer) -> Integer -> Integer -> Integer
bitwiseIn (Sized f) = bitwise (width f)
bitwiseIn Big = bigBitwise

shiftIn : IntTy -> ShiftDirection -> Integer -> Integer -> Integer
shiftIn (Sized f) = shifted (width f)
shiftIn Big = bigShifted

------------------------------------------------------------------------------
-- Literals
------------------------------------------------------------------------------

||| A Double literal's sign: a negative one is written in parentheses.
public export
data Sign = NonNegative | Negative

||| A Double literal's magnitude: a finite value as written ("0.1",
||| "1.0e300"), or one past the largest finite Double, which a program
||| reads as infinity.
public export
data Magnitude = Written String | PastLargest

||| A literal of a type, held as its value.
public export
data Literal : Ty -> Type where
  ||| Inside its type's bounds (Integer's: any).
  IntLit : (i : IntTy) -> Integer -> Literal (TIntegral i)
  DoubleLit : Sign -> Magnitude -> Literal TDouble
  CharLit : Char -> Literal TChar
  StringLit : String -> Literal TString

||| A literal of some type, as a guard reads it: by its value alone.
public export
data AnyLit : Type where
  MkAnyLit : {0 t : Ty} -> Literal t -> AnyLit

||| A literal of an integer as written: in parentheses when negative.
public export
integerText : Integer -> String
integerText n = if n < 0 then "(" ++ show n ++ ")" else show n

magnitudeText : Magnitude -> String
magnitudeText (Written m) = m
magnitudeText PastLargest = "1.0e309"

||| A literal as a program writes it: an integer in parentheses when
||| negative, a Double likewise, a Char or a String as `show` writes it (a
||| scalar past ASCII as its decimal escape on both hosts).
public export
literalSource : Literal t -> String
literalSource (IntLit _ v) = integerText v
literalSource (DoubleLit NonNegative m) = magnitudeText m
literalSource (DoubleLit Negative m) = "(-" ++ magnitudeText m ++ ")"
literalSource (CharLit c) = show c
literalSource (StringLit s) = show s

||| A literal as a line of stdin holds it: the value as text, a negative
||| Double with its sign, a Char or a String as itself.
public export
literalInput : Literal t -> String
literalInput (IntLit _ v) = show v
literalInput (DoubleLit NonNegative m) = magnitudeText m
literalInput (DoubleLit Negative m) = "-" ++ magnitudeText m
literalInput (CharLit c) = pack [c]
literalInput (StringLit s) = s

------------------------------------------------------------------------------
-- What a builtin is in the dialect
------------------------------------------------------------------------------

||| The op of the specification a builtin is: an op of the dialect's, an
||| upstream op the dialect admits, or its operand retyped, which the
||| dialect's signless integers make of a cast between two types of one
||| width, with no op at all.
public export
data DialectOp = OurOp AnyOp | AdmittedOp Admitted | Retyped

||| Where a builtin of constants is computed: while the program compiles,
||| by a fold, or where it runs.
public export
data Computed = WhileCompiling | WhereItRuns

||| Where an op of constants is computed, as the specification states it:
||| an op of ours by its meaning, so one that calls the runtime for its
||| effects or has no fold runs where the program runs; an admitted op by
||| its fold, so a C library's function, whose last digits IEEE leaves to
||| each library, runs on the target; a retyped value is no computation.
public export
computedOf : DialectOp -> Computed
computedOf (OurOp (SomeOp op)) = case op.meaning of
  CallsRuntime _ => WhereItRuns
  CallsRuntimeByCase _ _ => WhereItRuns
  NoFold => WhereItRuns
  _ => WhileCompiling
computedOf (AdmittedOp a) = case a.folding of
  NeverFolded => WhereItRuns
  UpstreamFold => WhileCompiling
  ComputedOnDoubles => WhileCompiling
computedOf Retyped = WhileCompiling

||| Of two parts of one computation, where the whole is computed.
both : Computed -> Computed -> Computed
both WhileCompiling c = c
both WhereItRuns _ = WhereItRuns

------------------------------------------------------------------------------
-- The guards
------------------------------------------------------------------------------

||| An op's guards as the specification states them, each argument by its
||| position among the builtin's: the kind of check it makes, the
||| arguments it is given, one per operand of the kind's op (the one it
||| guards first; a guarded builtin takes its arguments in its op's order),
||| and the cause its crash names. A guard's kind is its reading, so every
||| guard has one.
export
guardings : DialectOp -> List (Guard Nat)
guardings (OurOp (SomeOp op)) = map (\g => MkGuard g.check (map finToNat g.given) g.cause) op.guards
guardings (AdmittedOp a) = a.guards
guardings Retyped = []

||| What a guard says of the arguments it is given: it lets them through,
||| it fails (the program crashes there), or it cannot be read, for an
||| argument that is no literal of the type its condition reads.
data Verdict = Holds | Fails | Unreadable

||| Each kind of guard's condition, the oracle's own, on the literals it is
||| given, as many as the kind's op takes: a value that is not 0; a string
||| that is not empty; an index within a string; a Double that is neither
||| infinite nor NaN; a range of bytes, its offset and count at least 0,
||| ending within the size. Whether a handle holds a string is the run's
||| handle table's to say, and a closed expression has no literal of a
||| handle, so the oracle reads none.
judge : (kind : GuardKind) -> Vect (S (guardOthers kind)) (Maybe AnyLit) -> Verdict
judge NonZero [Just (MkAnyLit (IntLit _ v))] = if v == 0 then Fails else Holds
judge NonEmpty [Just (MkAnyLit (StringLit s))] = if s == "" then Fails else Holds
judge InBounds [Just (MkAnyLit (IntLit _ k)), Just (MkAnyLit (StringLit s))] =
  if 0 <= k && k < natToInteger (length (unpack s)) then Holds else Fails
judge Finite [Just (MkAnyLit (DoubleLit _ (Written _)))] = Holds
judge Finite [Just (MkAnyLit (DoubleLit _ PastLargest))] = Fails
judge Range [Just (MkAnyLit (IntLit _ offset)), Just (MkAnyLit (IntLit _ count)), Just (MkAnyLit (IntLit _ size))] =
  if 0 <= offset && 0 <= count && offset + count <= size then Holds else Fails
judge HoldsString _ = Unreadable
judge _ _ = Unreadable

------------------------------------------------------------------------------
-- The builtins
------------------------------------------------------------------------------

||| A builtin's name as a program writes it: `prim__`, Idris's word for it,
||| its stem, then, after `_`, the types the name carries, if any
||| (`prim__add_Int`, `prim__cast_IntInt8`, `prim__strHead`).
public export
record Spelling where
  constructor MkSpelling
  stem : String
  named : List Ty

public export
spellingText : Spelling -> String
spellingText (MkSpelling w []) = "prim__" ++ w
spellingText (MkSpelling w ts) = "prim__" ++ w ++ "_" ++ concatMap tyName ts

||| The name of a cast, as a program writes it: `prim__cast_<from><to>`.
public export
castNamed : Ty -> Ty -> String
castNamed from to = spellingText (MkSpelling "cast" [from, to])

||| Where the generator takes an argument from when no guard reads it: any
||| expression of its type; or a literal of a pool, where the meaning reads
||| few values of the type meaningfully (a code point, a number's text) or
||| the machine holds only a few (an Integer's shift, whose result grows
||| with its amount and whose amount past memory is the machine's end, not
||| the language's).
public export
data Source : Ty -> Type where
  AnyOf : Source t
  Pooled : (first : Literal t) -> (rest : List (Literal t)) -> Source t

-- Its own namespace, since Args below spells its arguments with the same
-- Nil and (::), and one namespace holds one of each.
namespace Sources
  public export
  data Sources : List Ty -> Type where
    Nil : Sources []
    (::) : Source t -> Sources ts -> Sources (t :: ts)

||| What the oracle computes of a builtin: of integers to an integer (a
||| comparison's truth as 0 or 1); or nothing, for a value of a Double, a
||| Char or a String, which the renderings of a case are held to among
||| themselves. A meaning is of arguments inside the builtin's guards,
||| which the oracle reads first.
public export
data Model : List Ty -> Ty -> Type where
  Unary : (Integer -> Integer) -> Model [TIntegral i] (TIntegral r)
  Binary : (Integer -> Integer -> Integer) -> Model [TIntegral i, TIntegral j] (TIntegral r)
  Unmodelled : Model ts r

||| A builtin: its spelling, the types it takes and gives, where the
||| generator takes each argument from, its meaning, and the op of the
||| specification it is.
public export
record Builtin where
  constructor MkBuiltin
  spelling : Spelling
  takes : List Ty
  gives : Ty
  sources : Sources takes
  meaning : Model takes gives
  op : DialectOp

||| `prim__<word>_<i>` of two values of the integer type `i` to one, `f`
||| what it means.
ints : String -> (Integer -> Integer -> Integer) -> (i : IntTy) -> DialectOp -> Builtin
ints w f i = MkBuiltin (MkSpelling w [TIntegral i]) [TIntegral i, TIntegral i] (TIntegral i) [AnyOf, AnyOf] (Binary f)

||| An operation that wraps its integer result to the type.
wrapped : IntTy -> (Integer -> Integer -> Integer) -> Integer -> Integer -> Integer
wrapped i f a b = inRange i (f a b)

||| The amounts an Integer's shift takes: within and past the fixed widths,
||| both ways, so that a value of the pools still fits in a few words.
amounts : Source Prims.tInteger
amounts =
  Pooled (IntLit Big 1)
    (map (IntLit Big) [3, 31, 32, 63, 64, 65, 100, -1, -3, -64, -100])

||| An Integer's shift `prim__<word>_Integer`, of an amount of the pool.
bigShift : String -> ShiftDirection -> DialectOp -> Builtin
bigShift w dir =
  MkBuiltin (MkSpelling w [Prims.tInteger]) [Prims.tInteger, Prims.tInteger] Prims.tInteger [AnyOf, amounts] (Binary (bigShifted dir))

||| `prim__<word>_Double` of two Doubles to one.
doubles : String -> DialectOp -> Builtin
doubles w = MkBuiltin (MkSpelling w [TDouble]) [TDouble, TDouble] TDouble [AnyOf, AnyOf] Unmodelled

||| `prim__<word>`, a Double's function of one Double.
doubleFn : String -> DialectOp -> Builtin
doubleFn w = MkBuiltin (MkSpelling w []) [TDouble] TDouble [AnyOf] Unmodelled

||| A comparison of two values of a type, its truth an Int: 1 or 0.
compareOn : String -> (Integer -> Integer -> Bool) -> (t : Ty) -> DialectOp -> Builtin
compareOn w f t = MkBuiltin (MkSpelling w [t]) [t, t] Prims.tInt [AnyOf, AnyOf] (truth t)
  where
    truth : (u : Ty) -> Model [u, u] Prims.tInt
    truth (TIntegral _) = Binary (\a, b => if f a b then 1 else 0)
    truth _ = Unmodelled

||| A type's negation, `prim__negate_<t>`.
negateOn : (t : Ty) -> DialectOp -> Builtin
negateOn t = MkBuiltin (MkSpelling "negate" [t]) [t] t [AnyOf] (negation t)
  where
    negation : (u : Ty) -> Model [u] u
    negation (TIntegral i) = Unary (\a => inRange i (negate a))
    negation _ = Unmodelled

||| The code points a value of an integer type holds: scalar values
||| across UTF-8's lengths and at the edges of the surrogates and of
||| Unicode, and values that are no scalar (a negative one, a surrogate,
||| one past U+10FFFF), which cast to 0. Every integer type holds 65 and 0.
codePoints : (i : IntTy) -> Source (TIntegral i)
codePoints i =
  Pooled (IntLit i 65)
    (map (IntLit i) (filter holds [233, 955, 8364, 128512, 0, 55295, 57344, 1114111, -1, 55296, 57343, 1114112]))
  where
    holds : Integer -> Bool
    holds v = case i of
      Sized f => let (lo, hi) = bounds f in lo <= v && v <= hi
      Big => True

||| Where a cast's operand comes from: for a cast to Char, a code point
||| (almost every other integer is no scalar and casts to 0); for a cast
||| from String, a number's text (almost every other string reads as 0).
castSource : (from, to : Ty) -> Source from
castSource (TIntegral i) TChar = codePoints i
castSource TString (TIntegral _) =
  Pooled (StringLit "0") (map StringLit ["42", "-17", "9223372036854775807", "123456"])
castSource TString TDouble = Pooled (StringLit "0.5") (map StringLit ["-2.25", "1e10", "3.0", "0.1"])
castSource _ _ = AnyOf

||| A cast, `prim__cast_<from><to>`: an integer's value wrapped to an
||| integer type.
castFrom : (from, to : Ty) -> DialectOp -> Builtin
castFrom from to = MkBuiltin (MkSpelling "cast" [from, to]) [from] to [castSource from to] (conversion from to)
  where
    conversion : (a, b : Ty) -> Model [a] b
    conversion (TIntegral _) (TIntegral r) = Unary (inRange r)
    conversion _ _ = Unmodelled

||| A builtin of no one type, `prim__<word>`, of what it takes to what it
||| gives, any argument of its type.
whole : String -> (ts : List Ty) -> (r : Ty) -> DialectOp -> Builtin
whole w ts r = MkBuiltin (MkSpelling w []) ts r (anyOf ts) Unmodelled
  where
    anyOf : (us : List Ty) -> Sources us
    anyOf [] = []
    anyOf (_ :: us) = AnyOf :: anyOf us

||| A family's builtins, each made the op it is: so a builtin never names
||| another op than its family's.
family : DialectOp -> List (DialectOp -> Builtin) -> List Builtin
family op = map (\b => b op)

fixedInts : List IntTy
fixedInts = map Sized fixedTys

||| The fixed-width types whose bits read as `s` says, in the order the
||| tests make them.
readAs : Signedness -> List FixedTy
readAs s = filter (\f => sameReading s (width f).signedness) fixedTys
  where
    sameReading : Signedness -> Signedness -> Bool
    sameReading Signed Signed = True
    sameReading Unsigned Unsigned = True
    sameReading _ _ = False

signedInts : List IntTy
signedInts = map Sized (readAs Signed)

unsignedInts : List IntTy
unsignedInts = map Sized (readAs Unsigned)

fixed : FixedTy -> Ty
fixed f = TIntegral (Sized f)

bitsOf : FixedTy -> Nat
bitsOf f = (width f).bits

signedTys : List FixedTy
signedTys = readAs Signed

unsignedTys : List FixedTy
unsignedTys = readAs Unsigned

||| Idris's comparisons, each by its word and what it decides.
comparisons : List (String, Integer -> Integer -> Bool)
comparisons = [("lt", (<)), ("lte", (<=)), ("eq", (==)), ("gte", (>=)), ("gt", (>))]

||| A Char's width, which a cast to or from a fixed width meets as a word's.
charBits : Nat
charBits = 32

||| The casts, every one Idris has (none from String or Double to Char, nor
||| from Char to Double), each in the family of the op it is.
casts : List (List Builtin)
casts =
  [ family Retyped
      ([ castFrom (fixed a) (fixed b) | a <- fixedTys, b <- fixedTys, a /= b, bitsOf a == bitsOf b ]
       ++ [ castFrom TChar (fixed b) | b <- fixedTys, bitsOf b == charBits ])
  , family (AdmittedOp truncI)
      ([ castFrom (fixed a) (fixed b) | a <- fixedTys, b <- fixedTys, bitsOf a > bitsOf b ]
       ++ [ castFrom TChar (fixed b) | b <- fixedTys, bitsOf b < charBits ])
  , family (AdmittedOp extSI) [ castFrom (fixed a) (fixed b) | a <- signedTys, b <- fixedTys, bitsOf a < bitsOf b ]
  , family (AdmittedOp extUI)
      ([ castFrom (fixed a) (fixed b) | a <- unsignedTys, b <- fixedTys, bitsOf a < bitsOf b ]
       ++ [ castFrom TChar (fixed b) | b <- fixedTys, bitsOf b > charBits ])
  -- An Integer is a Char as a signed word is: the scalar it is, or 0.
  , family (OurOp (SomeOp toCharS)) ([ castFrom (fixed a) TChar | a <- signedTys ] ++ [castFrom Prims.tInteger TChar])
  , family (OurOp (SomeOp toCharU)) [ castFrom (fixed a) TChar | a <- unsignedTys ]
  , family (AdmittedOp siToFP) [ castFrom (fixed a) TDouble | a <- signedTys ]
  , family (AdmittedOp uiToFP) [ castFrom (fixed a) TDouble | a <- unsignedTys ]
  , family (OurOp (SomeOp f64ToInt)) [ castFrom TDouble (fixed b) | b <- fixedTys ]
  , family (OurOp (SomeOp Strings.strShowSint)) [ castFrom (fixed a) TString | a <- signedTys ]
  , family (OurOp (SomeOp Strings.strShowUint)) [ castFrom (fixed a) TString | a <- unsignedTys ]
  , family (OurOp (SomeOp Strings.strToInt)) [ castFrom TString (fixed b) | b <- fixedTys ]
  , family (OurOp (SomeOp Strings.strFromChar)) [castFrom TChar TString]
  , family (OurOp (SomeOp Strings.strShowDouble)) [castFrom TDouble TString]
  , family (OurOp (SomeOp Strings.strToDouble)) [castFrom TString TDouble]
  , family (OurOp (SomeOp bigShow)) [castFrom Prims.tInteger TString]
  , family (OurOp (SomeOp bigFromStr)) [castFrom TString Prims.tInteger]
  , family (OurOp (SomeOp bigToInt)) [ castFrom Prims.tInteger (fixed b) | b <- fixedTys ]
  , family (OurOp (SomeOp (bigFromInt Signed))) [ castFrom (fixed a) Prims.tInteger | a <- signedTys ]
  , family (OurOp (SomeOp (bigFromInt Unsigned)))
      ([ castFrom (fixed a) Prims.tInteger | a <- unsignedTys ] ++ [castFrom TChar Prims.tInteger])
  , family (OurOp (SomeOp bigFromDouble)) [castFrom TDouble Prims.tInteger]
  , family (OurOp (SomeOp bigToDouble)) [castFrom Prims.tInteger TDouble]
  ]

||| Every builtin but `believe_me` and `crash`, by the op of the dialect
||| each is: a family is the builtins of one op, the unit the fuzzer's
||| swarm keeps or drops. A fixed width's negation is its subtraction from
||| 0, so it is in subtraction's family.
public export
families : List1 (List Builtin)
families =
  family (AdmittedOp addI) [ ints "add" (wrapped i (+)) i | i <- fixedInts ]
  ::: ([ family (AdmittedOp subI)
           ([ ints "sub" (wrapped i (-)) i | i <- fixedInts ] ++ [ negateOn (TIntegral i) | i <- fixedInts ])
       , family (AdmittedOp mulI) [ ints "mul" (wrapped i (*)) i | i <- fixedInts ]
       , family (OurOp (SomeOp divs)) [ ints "div" (divide i) i | i <- signedInts ]
       , family (OurOp (SomeOp mods)) [ ints "mod" (modulus i) i | i <- signedInts ]
       , family (AdmittedOp divUI) [ ints "div" (divide i) i | i <- unsignedInts ]
       , family (AdmittedOp remUI) [ ints "mod" (modulus i) i | i <- unsignedInts ]
       , family (AdmittedOp andI) [ ints "and" (bitwiseIn i (.&.)) i | i <- fixedInts ]
       , family (AdmittedOp orI) [ ints "or" (bitwiseIn i (.|.)) i | i <- fixedInts ]
       , family (AdmittedOp xorI) [ ints "xor" (bitwiseIn i xor) i | i <- fixedInts ]
       , family (OurOp (SomeOp shls)) [ ints "shl" (shiftIn i Leftward) i | i <- signedInts ]
       , family (OurOp (SomeOp shlu)) [ ints "shl" (shiftIn i Leftward) i | i <- unsignedInts ]
       , family (OurOp (SomeOp shrs)) [ ints "shr" (shiftIn i Rightward) i | i <- signedInts ]
       , family (OurOp (SomeOp shru)) [ ints "shr" (shiftIn i Rightward) i | i <- unsignedInts ]
       , family (AdmittedOp cmpI)
           [ compareOn w f t | (w, f) <- comparisons, t <- map TIntegral fixedInts ++ [TChar] ]
       , family (OurOp (SomeOp bigAdd)) [ints "add" (+) Big]
       , family (OurOp (SomeOp bigSub)) [ints "sub" (-) Big]
       , family (OurOp (SomeOp bigMul)) [ints "mul" (*) Big]
       , family (OurOp (SomeOp bigNeg)) [negateOn Prims.tInteger]
       , family (OurOp (SomeOp bigDiv)) [ints "div" (divide Big) Big]
       , family (OurOp (SomeOp bigMod)) [ints "mod" (modulus Big) Big]
       , family (OurOp (SomeOp bigAnd)) [ints "and" (bigBitwise (.&.)) Big]
       , family (OurOp (SomeOp bigOr)) [ints "or" (bigBitwise (.|.)) Big]
       , family (OurOp (SomeOp bigXor)) [ints "xor" (bigBitwise xor) Big]
       , family (OurOp (SomeOp bigShl)) [bigShift "shl" Leftward]
       , family (OurOp (SomeOp bigShr)) [bigShift "shr" Rightward]
       , family (OurOp (SomeOp bigCmp)) [ compareOn w f Prims.tInteger | (w, f) <- comparisons ]
       , family (AdmittedOp addF) [doubles "add"]
       , family (AdmittedOp subF) [doubles "sub"]
       , family (AdmittedOp mulF) [doubles "mul"]
       , family (AdmittedOp divF) [doubles "div"]
       , family (AdmittedOp negF) [negateOn TDouble]
       , family (AdmittedOp cmpF) [ compareOn w f TDouble | (w, f) <- comparisons ]
       , family (AdmittedOp expF) [doubleFn "doubleExp"]
       , family (AdmittedOp logF) [doubleFn "doubleLog"]
       , family (AdmittedOp powF) [whole "doublePow" [TDouble, TDouble] TDouble]
       , family (AdmittedOp sinF) [doubleFn "doubleSin"]
       , family (AdmittedOp cosF) [doubleFn "doubleCos"]
       , family (AdmittedOp tanF) [doubleFn "doubleTan"]
       , family (AdmittedOp asinF) [doubleFn "doubleASin"]
       , family (AdmittedOp acosF) [doubleFn "doubleACos"]
       , family (AdmittedOp atanF) [doubleFn "doubleATan"]
       , family (AdmittedOp sqrtF) [doubleFn "doubleSqrt"]
       , family (AdmittedOp floorF) [doubleFn "doubleFloor"]
       , family (AdmittedOp ceilF) [doubleFn "doubleCeiling"]
       , family (OurOp (SomeOp Strings.strCmp)) [ compareOn w f TString | (w, f) <- comparisons ]
       , family (OurOp (SomeOp Strings.strLength)) [whole "strLength" [TString] Prims.tInt]
       , family (OurOp (SomeOp Strings.strHead)) [whole "strHead" [TString] TChar]
       , family (OurOp (SomeOp Strings.strTail)) [whole "strTail" [TString] TString]
       , family (OurOp (SomeOp Strings.strIndex)) [whole "strIndex" [TString, Prims.tInt] TChar]
       , family (OurOp (SomeOp Strings.strCons)) [whole "strCons" [TChar, TString] TString]
       , family (OurOp (SomeOp Strings.strAppend)) [whole "strAppend" [TString, TString] TString]
       , family (OurOp (SomeOp Strings.strReverse)) [whole "strReverse" [TString] TString]
       , family (OurOp (SomeOp Strings.strSubstr)) [whole "strSubstr" [Prims.tInt, Prims.tInt, TString] TString]
       ] ++ casts)

||| Every builtin, family by family.
public export
builtins : List Builtin
builtins = concat (forget families)

------------------------------------------------------------------------------
-- Expressions
------------------------------------------------------------------------------

mutual
  ||| A builtin's arguments: an expression of each type it takes.
  public export
  data Args : List Ty -> Type where
    Nil : Args []
    (::) : Expr t -> Args ts -> Args (t :: ts)

  ||| A closed expression, well typed by construction: a literal, a builtin
  ||| applied, or the fuzzer's sum type's helper.
  public export
  data Expr : Ty -> Type where
    Lit : Literal t -> Expr t
    App : (b : Builtin) -> Args b.takes -> Expr b.gives
    ||| The sum type's helper; `k` is a literal from 0 to 2, its constructor.
    SData : (k : Expr Prims.tInt) -> Expr Prims.tInt -> Expr TDouble -> Expr Prims.tInt

||| A function applied, as a program writes it.
public export
appliedText : String -> List String -> String
appliedText f as = "(" ++ f ++ foldr (\a, rest => " " ++ a ++ rest) ")" as

mutual
  ||| An expression as a program writes it: a literal as written, an
  ||| application in parentheses.
  public export
  source : Expr t -> String
  source (Lit l) = literalSource l
  source (App b as) = appliedText (spellingText b.spelling) (argTexts as)
  source (SData k i x) = appliedText "sdata" [source k, source i, source x]

  argTexts : Args ps -> List String
  argTexts [] = []
  argTexts (e :: es) = source e :: argTexts es

mutual
  ||| What stdin holds for an expression read from it: a literal's line;
  ||| an expression's lines, its literals' in order.
  public export
  input : Expr t -> String
  input (Lit l) = literalInput l
  input (App _ as) = joinBy "\n" (inputs as)
  input (SData k i x) = joinBy "\n" [input k, input i, input x]

  inputs : Args ps -> List String
  inputs [] = []
  inputs (e :: es) = input e :: inputs es

mutual
  ||| Where an expression of constants is computed: while compiling when
  ||| every builtin of it is folded, else where the program runs.
  public export
  whereComputed : Expr t -> Computed
  whereComputed (Lit _) = WhileCompiling
  whereComputed (App b as) = both (computedOf b.op) (whereComputedArgs as)
  whereComputed (SData k i x) = both (whereComputed k) (both (whereComputed i) (whereComputed x))

  whereComputedArgs : Args ps -> Computed
  whereComputedArgs [] = WhileCompiling
  whereComputedArgs (e :: es) = both (whereComputed e) (whereComputedArgs es)

||| How a value of a type is printed: as a string, written by output fusion.
public export
printer : Ty -> String -> String
printer TString e = e
printer TChar e = "(" ++ castNamed Prims.tInt TString ++ " (" ++ castNamed TChar Prims.tInt ++ " " ++ e ++ "))"
printer t e = "(" ++ castNamed t TString ++ " " ++ e ++ ")"

||| The statement a generated program prints a value with: its label, a
||| space and the value, a line of its own.
public export
printLine : (label : String) -> Ty -> String -> String
printLine label t e =
  "putStrLn (" ++ spellingText (MkSpelling "strAppend" []) ++ " \"" ++ label ++ " \" " ++ printer t e ++ ")"

||| A line `printLine` printed, read back: its label and its value.
public export
labelled : String -> (String, String)
labelled l =
  let (label, rest) = break (== ' ') l in
  (label, maybe "" snd (strUncons rest))

------------------------------------------------------------------------------
-- The oracle
------------------------------------------------------------------------------

||| What an expression's evaluation does, as the oracle predicts it: it
||| runs to its value; it reaches a guard that fails, the crash naming one
||| of the causes (the language leaves the order of a call's arguments
||| open, so of two that fail, either may be met first); or the oracle
||| cannot say, where a guard is given an argument it cannot read.
public export
data Outcome = Runs | Crashes (List1 Cause) | Undecided

||| Two parts of one evaluation, each evaluated whole unless the other's
||| crash came first.
together : Outcome -> Outcome -> Outcome
together Undecided _ = Undecided
together _ Undecided = Undecided
together (Crashes a) (Crashes b) = Crashes (a ++ b)
together (Crashes a) Runs = Crashes a
together Runs o = o

||| The literal argument at a position, if it is one.
argAt : Nat -> Args ts -> Maybe AnyLit
argAt Z (Lit l :: _) = Just (MkAnyLit l)
argAt Z (_ :: _) = Nothing
argAt (S k) (_ :: rest) = argAt k rest
argAt _ [] = Nothing

||| What a builtin's own guards do on its arguments, once these ran.
guarded : DialectOp -> Args ts -> Outcome
guarded op as = foldr (\g, o => together (verdict g) o) Runs (guardings op)
  where
    verdict : Guard Nat -> Outcome
    verdict g = case judge g.check (map (\k => argAt k as) g.given) of
      Holds => Runs
      Fails => Crashes (g.cause ::: [])
      Unreadable => Undecided

mutual
  ||| What an expression does: its arguments are evaluated before the
  ||| builtin, every one of them, so the builtin's guards are reached only
  ||| when they all run.
  public export
  outcome : Expr t -> Outcome
  outcome (Lit _) = Runs
  outcome (App b as) = case outcomeArgs as of
    Runs => guarded b.op as
    other => other
  outcome (SData k i x) = together (outcome k) (together (outcome i) (outcome x))

  outcomeArgs : Args ts -> Outcome
  outcomeArgs [] = Runs
  outcomeArgs (e :: es) = together (outcome e) (outcomeArgs es)

mutual
  ||| The value of an expression over the integers alone, where it runs.
  public export
  modelled : Expr t -> Maybe Integer
  modelled (Lit (IntLit _ v)) = Just v
  modelled (Lit _) = Nothing
  modelled (App b as) = case guarded b.op as of
    Runs => computed b.meaning as
    _ => Nothing
  modelled (SData _ _ _) = Nothing

  computed : Model ts r -> Args ts -> Maybe Integer
  computed (Unary f) [a] = f <$> modelled a
  computed (Binary f) [a, c] = [| f (modelled a) (modelled c) |]
  computed Unmodelled _ = Nothing

||| What a builtin applied to integer literals gives: its value, or the
||| crash its guard meets.
public export
data Answer = Gives Integer | CrashesBy (List1 Cause)

||| Integers as the literals of the integer types a builtin takes.
integerArgs : (ts : List Ty) -> List Integer -> Maybe (Args ts)
integerArgs [] [] = Just []
integerArgs (TIntegral i :: ts) (v :: rest) = (Lit (IntLit i v) ::) <$> integerArgs ts rest
integerArgs _ _ = Nothing

||| A builtin applied to integer literals, where it takes integers alone.
public export
appliedTo : (b : Builtin) -> List Integer -> Maybe (Expr b.gives)
appliedTo b vs = App b <$> integerArgs b.takes vs

||| A builtin on integers, as Sem tabulates it; nothing for a builtin that
||| takes no integers, or one the oracle does not compute.
public export
answer : Builtin -> List Integer -> Maybe Answer
answer b vs = do
  e <- appliedTo b vs
  case outcome e of
    Runs => Gives <$> modelled e
    Crashes why => Just (CrashesBy why)
    Undecided => Nothing

------------------------------------------------------------------------------
-- The table's own checks
------------------------------------------------------------------------------

||| Whether a kind of guard's condition reads the types of the arguments it
||| is given: an integer for a divisor, a string, an index and the string it
||| indexes, a Double, the three integers of a range. No type of a closed
||| expression is a handle, so a guard of one reads none.
reads : (kind : GuardKind) -> Vect (S (guardOthers kind)) (Maybe Ty) -> Bool
reads NonZero [Just (TIntegral _)] = True
reads NonEmpty [Just TString] = True
reads InBounds [Just (TIntegral _), Just TString] = True
reads Finite [Just TDouble] = True
reads Range [Just (TIntegral _), Just (TIntegral _), Just (TIntegral _)] = True
reads HoldsString _ = False
reads _ _ = False

||| The table held to the specification: every builtin's guard is given
||| arguments of the types its condition reads, at positions the builtin
||| has; and no two builtins are spelled alike.
export
checks : List (String, Bool)
checks =
  [ ("every guard is given arguments of the types its condition reads", all typed builtins)
  , ("no two builtins are spelled alike", unique (map (spellingText . (.spelling)) builtins)) ]
  where
    typed : Builtin -> Bool
    typed b = all (\g => reads g.check (map (\k => getAt k b.takes) g.given)) (guardings b.op)
    unique : List String -> Bool
    unique [] = True
    unique (x :: xs) = not (elem x xs) && unique xs
