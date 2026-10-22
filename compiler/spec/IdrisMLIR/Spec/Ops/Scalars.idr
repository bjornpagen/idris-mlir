-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The ops on fixed-width integers and Doubles. Idris's IntN and BitsN
||| share one signless integer type and differ in their operations, so an
||| operation that reads a sign is one op per signedness where the
||| computation differs, as arith's are: a shift's amount read signed turns a
||| negative shift, read unsigned it is a huge count, so the four shifts stay
||| four. Unsigned division is arith's own (`arith.divui`, `arith.remui`,
||| behind `idr.check.nonzero`), which the frontend writes; signed division
||| is Euclidean, which arith's is not.
|||
||| Euclidean division, the shifts and the char conversions are inline
||| arithmetic: each op's meaning is one C++ template (`Inline`), its folder,
||| ranges and expansion; the heads of a number's text and a Double's
||| truncation are the runtime's functions.
module IdrisMLIR.Spec.Ops.Scalars

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Effects.Declaration
import IdrisMLIR.Spec.Runtime.Endings
import IdrisMLIR.Spec.Ops.Numeric
import IdrisMLIR.Spec.Ops.Shapes

import Data.List1

%default total

------------------------------------------------------------------------------
-- Euclidean division
------------------------------------------------------------------------------

divisionName : Part -> Mnemonic
divisionName Quotient = "int.div_s"
divisionName Remainder = "int.mod_s"

divisionDoc : Part -> Doc
divisionDoc Quotient = says "Idris div of a signed integer: Euclidean, by a divisor that is not zero"
divisionDoc Remainder = says "Idris mod of a signed integer: Euclidean, by a divisor that is not zero"

||| The quotient or remainder of a signed integer by one that is not zero,
||| which `idr.check.nonzero` guards: the op stays below its check by data
||| dependence, and folds only where the guard holds on its constants. The
||| least value over -1 wraps to the least value, remainder 0.
public export
division : Part -> Op 2 1 0 0
division part = MkOp
  { home = InIdr
  , mnemonic = divisionName part
  , ins = [single "lhs" int, single "rhs" int]
  , outs = [result "result" int]
  , attrs = []
  , regions = []
  , traits = [SameOperandsAndResultType]
  , interfaces = [Declares InferIntRange []]
  , effects = computes
  , speculation = Conditionally
  , stages = Always
  , meaning = inline (EuclidOf part)
  , verify = DeclarationOnly
  , format = plain 2
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = [MkGuard "check.nonzero" (1 ::: []) (caseRef causeClosed DivisionByZero)]
  , specializations = []
  , laws = []
  , doc = divisionDoc part
  }

public export
divs : Op 2 1 0 0
divs = division Quotient

public export
mods : Op 2 1 0 0
mods = division Remainder

------------------------------------------------------------------------------
-- Shifts
------------------------------------------------------------------------------

shiftName : ShiftDirection -> Signedness -> Mnemonic
shiftName Leftward Signed = "int.shl_s"
shiftName Leftward Unsigned = "int.shl_u"
shiftName Rightward Signed = "int.shr_s"
shiftName Rightward Unsigned = "int.shr_u"

shiftDoc : ShiftDirection -> Signedness -> Doc
shiftDoc Leftward Signed = says "Idris shiftL of a signed integer: defined for every amount, wrapped to the width"
shiftDoc Leftward Unsigned = says "Idris shiftL of an unsigned integer: defined for every amount, wrapped to the width"
shiftDoc Rightward Signed = says "Idris shiftR of a signed integer: filling with its sign, defined for every amount"
shiftDoc Rightward Unsigned = says "Idris shiftR of an unsigned integer: filling with zeros, defined for every amount"

||| Idris's shift of a fixed-width integer: the value moved, then wrapped to
||| its width, so from the width on only the fill is left; a signed amount
||| that is negative turns the direction. Defined for every amount, where
||| arith's shifts are poison from the width up: the expansion never builds
||| one at the width.
public export
shift : ShiftDirection -> Signedness -> Op 2 1 0 0
shift dir sign = MkOp
  { home = InIdr
  , mnemonic = shiftName dir sign
  , ins = [single "lhs" int, single "rhs" int]
  , outs = [result "result" int]
  , attrs = []
  , regions = []
  , traits = [SameOperandsAndResultType]
  , interfaces = [Declares InferIntRange []]
  , effects = computes
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = inline (ShiftOf dir sign)
  , verify = DeclarationOnly
  , format = plain 2
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = shiftDoc dir sign
  }

public export
shls : Op 2 1 0 0
shls = shift Leftward Signed

public export
shlu : Op 2 1 0 0
shlu = shift Leftward Unsigned

public export
shrs : Op 2 1 0 0
shrs = shift Rightward Signed

public export
shru : Op 2 1 0 0
shru = shift Rightward Unsigned

------------------------------------------------------------------------------
-- Characters
------------------------------------------------------------------------------

toCharName : Signedness -> Mnemonic
toCharName Signed = "int.to_char_s"
toCharName Unsigned = "int.to_char_u"

toCharDoc : Signedness -> Doc
toCharDoc Signed = says "a signed integer as a Char: itself if a scalar value, else 0"
toCharDoc Unsigned = says "an unsigned integer as a Char: itself if a scalar value, else 0"

||| An integer as a Char: itself, if it is a scalar value read as the op's
||| signedness says, else 0. A negative signed integer is no scalar value;
||| the integer is widened before the test, so no bits are cut first.
public export
toChar : Signedness -> Op 1 1 0 0
toChar sign = MkOp
  { home = InIdr
  , mnemonic = toCharName sign
  , ins = [single "value" int]
  , outs = [result "result" i32]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = [Declares InferIntRange []]
  , effects = computes
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = inline (ToCharOf sign)
  , verify = DeclarationOnly
  , format = plain 1
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = toCharDoc sign
  }

public export
toCharS : Op 1 1 0 0
toCharS = toChar Signed

public export
toCharU : Op 1 1 0 0
toCharU = toChar Unsigned

------------------------------------------------------------------------------
-- The runtime's scalar functions
------------------------------------------------------------------------------

headName : Signedness -> Mnemonic
headName Signed = "int.head_s"
headName Unsigned = "int.head_u"

headCall : Signedness -> RuntimeCall 1 1
headCall Signed = MkRuntimeCall "int_head_s" [TakesSigned] (Returns GivesInt32)
headCall Unsigned = MkRuntimeCall "int_head_u" [TakesUnsigned] (Returns GivesInt32)

||| The first character of the decimal text of an integer, read as the op's
||| signedness says, by the runtime's function of that signedness: the head
||| of a shown number, which a rule reads off the show.
public export
intHead : Signedness -> Op 1 1 0 0
intHead sign = MkOp
  { home = InIdr
  , mnemonic = headName sign
  , ins = [single "value" int]
  , outs = [result "result" i32]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = [Declares InferIntRange ["inferResultRanges"]]
  , effects = computes
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = ComputedByRuntime (headCall sign)
  , verify = DeclarationOnly
  , format = plain 1
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = says "the first character of an integer's decimal text"
  }

public export
intHeadS : Op 1 1 0 0
intHeadS = intHead Signed

public export
intHeadU : Op 1 1 0 0
intHeadU = intHead Unsigned

||| A finite Double as an integer, truncated toward zero and wrapped to the
||| result's width. The Double is finite: `idr.check.finite` guards it.
public export
f64ToInt : Op 1 1 0 0
f64ToInt = MkOp
  { home = InIdr
  , mnemonic = "f64.to_int"
  , ins = [single "value" f64]
  , outs = [result "result" int]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = []
  , effects = computes
  , speculation = Conditionally
  , stages = Always
  , meaning = ComputedByRuntime (MkRuntimeCall "to_int" [TakesDouble] (Returns GivesWrapped))
  , verify = DeclarationOnly
  , format = plain 1
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = [MkGuard "check.finite" (0 ::: []) (caseRef causeClosed NonFiniteCast)]
  , specializations = []
  , laws = []
  , doc = says "a finite Double as an integer, truncated and wrapped"
  }

||| The first character of a Double's text, as prim__cast_DoubleString
||| writes it.
public export
f64Head : Op 1 1 0 0
f64Head = MkOp
  { home = InIdr
  , mnemonic = "f64.head"
  , ins = [single "value" f64]
  , outs = [result "result" i32]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = [Declares InferIntRange ["inferResultRanges"]]
  , effects = computes
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = ComputedByRuntime (MkRuntimeCall "double_head" [TakesDouble] (Returns GivesInt32))
  , verify = DeclarationOnly
  , format = plain 1
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = says "the first character of a Double's text"
  }

public export
scalarOps : List AnyOp
scalarOps =
  [ SomeOp divs, SomeOp mods, SomeOp shls, SomeOp shlu, SomeOp shrs, SomeOp shru
  , SomeOp toCharS, SomeOp toCharU, SomeOp intHeadS, SomeOp intHeadU
  , SomeOp f64ToInt, SomeOp f64Head ]
