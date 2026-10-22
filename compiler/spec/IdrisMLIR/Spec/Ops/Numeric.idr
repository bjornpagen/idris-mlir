-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The vocabulary of the inline arithmetic: the constants its meanings are
||| generic over (a signedness, a direction, a part of a division), the
||| meanings an op may name, and the laws the rules on those ops rest on.
||| The meanings themselves are C++ templates over a numeric domain
||| (`include/idr/IR/Numeric/Inline.h`): one function each, instantiated as
||| the folder, the integer ranges and the expansion into arith, and
||| included by the runtime. This module names them; it never states their
||| arithmetic, which would be the second copy the template removes.
|||
||| A law is the one place a family of rules comes from (`Spec.Ops.Rewrites`
||| makes every rule from a law), and the C++ checks every law against the
||| meanings, exhaustively over 8-bit words, when the compiler is built
||| (`Numeric/Checks.h` reads `allLaws`), so a rule cannot exist without its
||| check, and a law cannot be added without its statement there.
module IdrisMLIR.Spec.Ops.Numeric

import IdrisMLIR.Spec.Core.Vocabulary

import Data.List.Elem
import Data.List1

%default total

------------------------------------------------------------------------------
-- The constants of the meanings
------------------------------------------------------------------------------

||| How an operation reads an integer: arith's school, signless types and
||| the sign on the op where the computation differs.
public export
data Signedness = Signed | Unsigned

public export
signednessClosed : Closed Signedness
signednessClosed = MkClosed
  { name = "Signedness"
  , shape = OneOf
  , every = Signed ::: [Unsigned]
  , complete = \case
      Signed => Here
      Unsigned => There Here
  , describe = \case
      Signed => MkCase "Signed" ("signed" ::: []) "its top bit is its sign"
      Unsigned => MkCase "Unsigned" ("unsigned" ::: []) "the natural its bits are"
  , doc = brief "how an operation reads an integer"
  }

||| Which way a shift moves.
public export
data ShiftDirection = Leftward | Rightward

public export
directionClosed : Closed ShiftDirection
directionClosed = MkClosed
  { name = "Direction"
  , shape = OneOf
  , every = Leftward ::: [Rightward]
  , complete = \case
      Leftward => Here
      Rightward => There Here
  , describe = \case
      Leftward => MkCase "Left" ("left" ::: []) "toward the high bits"
      Rightward => MkCase "Right" ("right" ::: []) "toward the low bits"
  , doc = brief "which way a shift moves"
  }

||| Which part of a Euclidean division an op gives.
public export
data Part = Quotient | Remainder

public export
partClosed : Closed Part
partClosed = MkClosed
  { name = "Part"
  , shape = OneOf
  , every = Quotient ::: [Remainder]
  , complete = \case
      Quotient => Here
      Remainder => There Here
  , describe = \case
      Quotient => MkCase "Quotient" ("quotient" ::: []) "the quotient"
      Remainder => MkCase "Remainder" ("remainder" ::: []) "the remainder, in [0, |divisor|)"
  , doc = brief "which part of a Euclidean division an op gives"
  }

------------------------------------------------------------------------------
-- The meanings an op may have
------------------------------------------------------------------------------

||| The function objects of `Numeric/Inline.h` an op of inline arithmetic
||| names as its meaning (`Inline`): each is one template instantiated at
||| the op's family constants, so the op's class says nothing of its
||| arithmetic. Its C++ name is `::idr::numeric::<name>`.
public export
data InlineMeaning
  = EuclidOf Part
  | ShiftOf ShiftDirection Signedness
  | ToCharOf Signedness

||| The name the C++ gives the meaning: the template at its constants, as
||| `Inline.h` spells its aliases.
public export
inlineName : InlineMeaning -> Ident
inlineName (EuclidOf Quotient) = "EuclidQuotient"
inlineName (EuclidOf Remainder) = "EuclidRemainder"
inlineName (ShiftOf Leftward Signed) = "ShiftLeftSigned"
inlineName (ShiftOf Leftward Unsigned) = "ShiftLeftUnsigned"
inlineName (ShiftOf Rightward Signed) = "ShiftRightSigned"
inlineName (ShiftOf Rightward Unsigned) = "ShiftRightUnsigned"
inlineName (ToCharOf Signed) = "ToCharSigned"
inlineName (ToCharOf Unsigned) = "ToCharUnsigned"

||| An op's meaning from its inline function.
public export
inline : InlineMeaning -> Meaning i o
inline m = Inline (inlineName m)

||| The conditions of `Numeric/Inline.h` a guard names as its meaning
||| (`InlineCondition`): its operand passes where the condition holds, so
||| its folder, its decision on intervals and its test in the lowering are
||| one template's instances. A condition is over what the guard tests,
||| which is its operand or what the operand determines: a string's length,
||| a Double's bits. Its C++ name is `::idr::numeric::<name>`.
public export
data GuardCondition = DivisorNonzero | IndexInBounds | BytesInRange | LengthNonzero | BitsFinite

||| The name the C++ gives the condition's function object.
public export
conditionName : GuardCondition -> Ident
conditionName DivisorNonzero = "Nonzero"
conditionName IndexInBounds = "InBounds"
conditionName BytesInRange = "InRange"
conditionName LengthNonzero = "Nonempty"
conditionName BitsFinite = "Finite"

------------------------------------------------------------------------------
-- The laws
------------------------------------------------------------------------------

||| The families of one-way rules the inline ops and Integer's division
||| admit, each constant-triggered, which no upstream pattern knows because
||| upstream has no Euclidean division and no total shift. Each is checked
||| against the meanings when the compiler is built (`Numeric/Laws.h`).
public export
data NumericLaw
  = QuotientByOne
  | QuotientByMinusOne
  | RemainderByUnit
  | QuotientByPowerOfTwo
  | RemainderByPowerOfTwo
  | RemainderByNegativePowerOfTwo
  | ShiftByZero
  | ShiftByNegative
  | CharOfChar
  | IntegerRemainderByPowerOfTwo
  | IntegerQuotientByPowerOfTwo

public export
lawClosed : Closed NumericLaw
lawClosed = MkClosed
  { name = "Law"
  , shape = OneOf
  , every =
      QuotientByOne :::
      [ QuotientByMinusOne, RemainderByUnit, QuotientByPowerOfTwo, RemainderByPowerOfTwo
      , RemainderByNegativePowerOfTwo, ShiftByZero, ShiftByNegative, CharOfChar
      , IntegerRemainderByPowerOfTwo, IntegerQuotientByPowerOfTwo ]
  , complete = \case
      QuotientByOne => Here
      QuotientByMinusOne => There Here
      RemainderByUnit => There (There Here)
      QuotientByPowerOfTwo => There (There (There Here))
      RemainderByPowerOfTwo => There (There (There (There Here)))
      RemainderByNegativePowerOfTwo => There (There (There (There (There Here))))
      ShiftByZero => There (There (There (There (There (There Here)))))
      ShiftByNegative => There (There (There (There (There (There (There Here))))))
      CharOfChar => There (There (There (There (There (There (There (There Here)))))))
      IntegerRemainderByPowerOfTwo => There (There (There (There (There (There (There (There (There Here))))))))
      IntegerQuotientByPowerOfTwo => There (There (There (There (There (There (There (There (There (There Here)))))))))
  , describe = \case
      QuotientByOne => MkCase "QuotientByOne" ("quotient_by_one" ::: []) "a quotient by 1 is the dividend"
      QuotientByMinusOne => MkCase "QuotientByMinusOne" ("quotient_by_minus_one" ::: []) "a quotient by -1 is the negation, wrapping at the least value"
      RemainderByUnit => MkCase "RemainderByUnit" ("remainder_by_unit" ::: []) "a remainder by 1 or -1 is 0"
      QuotientByPowerOfTwo => MkCase "QuotientByPowerOfTwo" ("quotient_by_power_of_two" ::: []) "a quotient by 2^k is the arithmetic shift right by k"
      RemainderByPowerOfTwo => MkCase "RemainderByPowerOfTwo" ("remainder_by_power_of_two" ::: []) "a remainder by 2^k is the low k bits"
      RemainderByNegativePowerOfTwo => MkCase "RemainderByNegativePowerOfTwo" ("remainder_by_negative_power_of_two" ::: []) "a remainder by -2^k is the low k bits"
      ShiftByZero => MkCase "ShiftByZero" ("shift_by_zero" ::: []) "a shift by 0 is its value"
      ShiftByNegative => MkCase "ShiftByNegative" ("shift_by_negative" ::: []) "a signed shift by -k is the shift the other way by k"
      CharOfChar => MkCase "CharOfChar" ("char_of_char" ::: []) "a char conversion of a char is that char"
      IntegerRemainderByPowerOfTwo => MkCase "IntegerRemainderByPowerOfTwo" ("integer_remainder_by_power_of_two" ::: []) "an Integer's remainder by 2^k is its low k bits"
      IntegerQuotientByPowerOfTwo => MkCase "IntegerQuotientByPowerOfTwo" ("integer_quotient_by_power_of_two" ::: []) "an Integer's quotient by 2^k is its shift right by k"
  , doc = brief "a family of rules on the inline ops, checked against their meanings"
  }

------------------------------------------------------------------------------
-- The header the meanings include
------------------------------------------------------------------------------

||| `NumericEnums.h.inc`: the constants and the laws as plain enums in
||| `::idr::numeric`, and every law in order, which the template's checks
||| walk. Freestanding, as the template is: the runtime includes it.
public export
numericHeader : Header
numericHeader = MkHeader
  { name = "NumericEnums"
  , blocks =
      [ (Nested ("numeric" ::: []),
          [ EnumOf (enumDef signednessClosed)
          , EnumOf (enumDef directionClosed)
          , EnumOf (enumDef partClosed)
          , EnumOf (enumDef lawClosed)
          , Array1 "allLaws" (EnumColumn (enumDef lawClosed))
              (map (CaseCell . caseRef lawClosed) (forget lawClosed.every))
              "every law, in order, each of which the meanings are checked against"
          ])
      ]
  , doc = MkDoc "the vocabulary of the inline arithmetic"
      "The constants the meanings of Numeric/Inline.h are generic over, and the laws\nthe rules on the inline ops rest on, which Numeric/Checks.h checks."
  }
