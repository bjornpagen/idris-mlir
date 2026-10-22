-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The ops on Integers and naturals. Each is a runtime function, which the
||| folder computes by calling it (`ComputedByRuntime`): an Integer's
||| arithmetic is the runtime's, its small case inline in the runtime's
||| bitcode, so the tagged arithmetic exists once. A builder of a new
||| Integer acquires nothing before counting: two equal sums are one sum,
||| and an unused one goes. The runtime's big temporaries are memory no
||| value names.
module IdrisMLIR.Spec.Ops.Bigs

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Effects.Declaration
import IdrisMLIR.Spec.Runtime.Endings
import IdrisMLIR.Spec.Control.Flow
import IdrisMLIR.Spec.Ops.Shapes
import IdrisMLIR.Spec.Ops.Values
import IdrisMLIR.Spec.Ops.Strings

import Data.List1
import Data.Vect

%default total

------------------------------------------------------------------------------
-- The literal
------------------------------------------------------------------------------

||| `#idr.big<-12>`, C++ `BigAttr`: an Integer or a natural as a literal,
||| an integer of any size. Its hand storage (`idr/IR/Ops/BigStorage.h`)
||| keys it at its fewest signed bits whatever width it is given at, so
||| equal integers are one attribute and no reader compares widths.
public export
bigAttr : AttrDef 1
bigAttr = MkAttrDef
  { mnemonic = "big"
  , params = [MkParameter "value" IntegerValue AlwaysWritten "the integer, at its fewest signed bits"]
  , syntax = Declarative [Keyword "<", ParamAt 0, Keyword ">"]
  , typed = Untyped
  , interfaces = []
  , verifier = AnyParameters
  , bytecode = Derived
  , storage = HandStorage
  , members = []
  , doc = says "an integer of any size"
  }

------------------------------------------------------------------------------
-- What the ops share
------------------------------------------------------------------------------

||| An op with no runtime form: its result is its operand's word, under
||| another type, which the lowering gives by one pattern for every op with
||| the trait.
public export
noRuntimeForm : TraitDef
noRuntimeForm = MkTraitDef "NoRuntimeForm" (says "its result is its first operand's word at run time")

||| An op the fold of which has a condition beyond its guards: the size of
||| the constant it would make, or a precondition its type does not carry.
foldable : Member
foldable = MkMember OnClass "bool" "foldable" [param "::llvm::ArrayRef<::mlir::Attribute>" "constants"]

||| What a big op computes on words where its bigs all fit, which idr-narrow
||| makes it: the word itself, for an op whose result is its operand's word
||| (a natural as an Integer); an arith op on its operands' words; or one on
||| its first operand's word and a constant. The pass reads it as the
||| generated `BigToWord<Op>`, and an op with none keeps its bigs.
data WordForm = TheWord | OnWords Admitted | OnWordAnd Admitted Integer

bigToWord : WordForm -> Specialized
bigToWord TheWord = MkSpecialized "BigToWord" [("Op", NoClass)]
bigToWord (OnWords a) = MkSpecialized "BigToWord" [("Op", UpstreamClass a)]
bigToWord (OnWordAnd a k) = MkSpecialized "BigToWord" [("Op", UpstreamClass a), ("constant", IntConstant k)]

||| An Integer's function of two Integers, `idris_rt_big_<stem>`.
twoBigs : Symbol -> RuntimeCall 2 1
twoBigs s = MkRuntimeCall s [TakesBig, TakesBig] (Returns GivesBig)

||| An op of two Integers that builds an Integer: Integer's sub, and, or,
||| xor, its shifts, its division.
binary : Mnemonic -> Symbol -> List Member -> Doc -> Op 2 1 0 0
binary m s ms d = MkOp
  { home = InIdr
  , mnemonic = m
  , ins = [single "lhs" bigRead, single "rhs" bigRead]
  , outs = [result "result" bigValue]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = []
  , effects = builds 0 Touched
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = ComputedByRuntime (twoBigs s)
  , verify = DeclarationOnly
  , format = plain 2
  , builders = []
  , defaultBuilders = WithDefaults
  , members = ms
  , guards = []
  , specializations = []
  , laws = []
  , doc = d
  }

------------------------------------------------------------------------------
-- Arithmetic
------------------------------------------------------------------------------

||| The sum and the product of two naturals are natural, so these take
||| Integers or naturals, and give what they take: Nat's plus and mult are
||| these ops. A sum with 0 is the other operand, a law the e-graph reads.
naturalBinary : Mnemonic -> Symbol -> Admitted -> List Law -> Doc -> Op 2 1 0 0
naturalBinary m s word ls d = MkOp
  { home = InIdr
  , mnemonic = m
  , ins = [single "lhs" bigOrNatRead, single "rhs" bigOrNatRead]
  , outs = [result "result" bigOrNatValue]
  , attrs = []
  , regions = []
  , traits = [SameTypeOperands]
  , interfaces = [Declares InferIntRange ["inferResultRanges"]]
  , effects = builds 0 Touched
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = ComputedByRuntime (twoBigs s)
  , verify = DeclarationOnly
  , format = plain 2
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = [bigToWord (OnWords word)]
  , laws = ls
  , doc = d
  }

public export
bigAdd : Op 2 1 0 0
bigAdd = naturalBinary "big.add" "big_add" addI [Associative, Identity 0] (says "the sum of two bigs or two naturals")

public export
bigMul : Op 2 1 0 0
bigMul = naturalBinary "big.mul" "big_mul" mulI [] (says "the product of two bigs or two naturals")

public export
bigSub : Op 2 1 0 0
bigSub =
  { interfaces := [Declares InferIntRange ["inferResultRanges"]]
  , specializations := [bigToWord (OnWords subI)] }
  (binary "big.sub" "big_sub" [] (says "the difference of two bigs"))

public export
bigAnd : Op 2 1 0 0
bigAnd = binary "big.and" "big_and" [] (says "the bitwise and of two bigs")

public export
bigOr : Op 2 1 0 0
bigOr = binary "big.or" "big_or" [] (says "the bitwise or of two bigs")

public export
bigXor : Op 2 1 0 0
bigXor = binary "big.xor" "big_xor" [] (says "the bitwise xor of two bigs")

||| Integer's shifts: every amount has a value, the runtime's; one too large
||| to hold is memory exhausted, as for a product. A shift away from zero
||| folds only where the constant it makes is a small, held in the big's own
||| word, so a fold makes no static datum (`foldable`).
public export
bigShl : Op 2 1 0 0
bigShl = binary "big.shl" "big_shl" [foldable] (says "a big shifted left, Integer's shiftL")

public export
bigShr : Op 2 1 0 0
bigShr = binary "big.shr" "big_shr" [foldable] (says "a big shifted right, Integer's shiftR, filling with its sign")

||| Integer's div and mod, Euclidean, by a divisor that is not zero, which
||| `idr.check.nonzero` guards.
division : Mnemonic -> Symbol -> Doc -> Op 2 1 0 0
division m s d =
  { guards := [MkGuard "check.nonzero" (1 ::: []) (caseRef causeClosed DivisionByZero)]
  , speculation := Conditionally }
  (binary m s [] d)

public export
bigDiv : Op 2 1 0 0
bigDiv = division "big.div" "big_div" (says "the quotient of two bigs, as Integer's div, by a divisor that is not zero")

public export
bigMod : Op 2 1 0 0
bigMod = division "big.mod" "big_mod" (says "the remainder of two bigs, as Integer's mod, by a divisor that is not zero")

public export
bigNeg : Op 1 1 0 0
bigNeg = MkOp
  { home = InIdr
  , mnemonic = "big.neg"
  , ins = [single "value" bigRead]
  , outs = [result "result" bigValue]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = []
  , effects = builds 0 Touched
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = ComputedByRuntime (MkRuntimeCall "big_neg" [TakesBig] (Returns GivesBig))
  , verify = DeclarationOnly
  , format = plain 1
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = says "the negation of a big"
  }

||| The predecessor of a natural that is not zero, which the frontend writes
||| where a match on a natural found it is not zero, so the value visibly
||| shrinks. A constant zero is on a path the match excludes: no fold makes
||| its predecessor (`foldable`).
public export
natPred : Op 1 1 0 0
natPred = MkOp
  { home = InIdr
  , mnemonic = "nat.pred"
  , ins = [single "value" natRead]
  , outs = [result "result" natValue]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = [Declares InferIntRange ["inferResultRanges"]]
  , effects = builds 0 Touched
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = ComputedByRuntime (MkRuntimeCall "big_pred" [TakesBig] (Returns GivesBig))
  , verify = DeclarationOnly
  , format = plain 1
  , builders = []
  , defaultBuilders = WithDefaults
  , members = [foldable]
  , guards = []
  , specializations = [bigToWord (OnWordAnd subI 1)]
  , laws = []
  , doc = says "the predecessor of a natural that is not zero"
  }

||| Two Integers or two naturals compared, as the runtime orders them, by
||| the op's predicate: Nat's equalNat and compareNat are this op.
public export
bigCmp : Op 2 1 1 0
bigCmp = MkOp
  { home = InIdr
  , mnemonic = "big.cmp"
  , ins = [single "lhs" bigOrNatRead, single "rhs" bigOrNatRead]
  , outs = [result "result" i1]
  , attrs = [property "predicate" (EnumProperty (enumDef comparisonClosed))]
  , regions = []
  , traits = [SameTypeOperands]
  , interfaces = [Declares InferIntRange ["inferResultRanges"]]
  , effects = computes
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = ComputedByRuntime (MkRuntimeCall "big_cmp" [TakesBig, TakesBig] (Returns GivesOrder))
  , verify = DeclarationOnly
  , format = attrFirst 2 0
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = [bigToWord (OnWords cmpI)]
  , laws = []
  , doc = says "compares two bigs or two naturals"
  }

------------------------------------------------------------------------------
-- Conversions
------------------------------------------------------------------------------

||| A natural as the Integer it is: the same word under another type, so it
||| has no runtime form, and it hands its operand's reference to its result.
public export
natToBig : Op 1 1 0 0
natToBig = MkOp
  { home = InIdr
  , mnemonic = "nat.to_big"
  , ins = [single "value" natValue]
  , outs = [result "result" bigValue]
  , attrs = []
  , regions = []
  , traits = [OurTrait noRuntimeForm]
  , interfaces =
      [ Implements flowInterface ["getFlowEdges"]
      , Declares InferIntRange ["inferResultRanges"] ]
  , effects = Executes [] [Consumes 0] Covered Untouched
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = HandFolder
  , verify = DeclarationOnly
  , format = plain 1
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = [bigToWord TheWord]
  , laws = []
  , doc = says "a natural as an Integer"
  }

||| The one op that makes a natural of an Integer, so the one that keeps it
||| non-negative: a negative Integer is 0, as Nat's integerToNat says. The
||| runtime gives the operand with one more reference, or a small: a count
||| written, nothing acquired.
public export
natFromBig : Op 1 1 0 0
natFromBig = MkOp
  { home = InIdr
  , mnemonic = "nat.from_big"
  , ins = [single "value" bigRead]
  , outs = [result "result" natValue]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = [Declares InferIntRange ["inferResultRanges"]]
  , effects = Executes [OnValues Write Count (Results 0)] [] Covered Untouched
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = ComputedByRuntime (MkRuntimeCall "nat_from_big" [TakesBig] (Returns GivesBig))
  , verify = DeclarationOnly
  , format = plain 1
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = [bigToWord (OnWordAnd maxSI 0)]
  , laws = []
  , doc = says "an Integer as a natural, 0 if it is negative"
  }

fromIntName : Signedness -> Mnemonic
fromIntName Signed = "big.from_sint"
fromIntName Unsigned = "big.from_uint"

fromIntCall : Signedness -> RuntimeCall 1 1
fromIntCall Signed = MkRuntimeCall "big_from_int_s" [TakesSigned] (Returns GivesBig)
fromIntCall Unsigned = MkRuntimeCall "big_from_int_u" [TakesUnsigned] (Returns GivesBig)

||| An unsigned integer is never negative, so its big may be a natural; a
||| natural of a signed integer cannot be written.
fromIntResult : Signedness -> TypeC
fromIntResult Signed = bigValue
fromIntResult Unsigned = bigOrNatValue

||| An integer as an Integer, read as the op's signedness says.
public export
bigFromInt : Signedness -> Op 1 1 0 0
bigFromInt sign = MkOp
  { home = InIdr
  , mnemonic = fromIntName sign
  , ins = [single "value" int]
  , outs = [result "result" (fromIntResult sign)]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = [Declares InferIntRange ["inferResultRanges"]]
  , effects = builds 0 Touched
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = ComputedByRuntime (fromIntCall sign)
  , verify = DeclarationOnly
  , format = plain 1
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = says "an integer as a big"
  }

||| The big or natural of a word proved to fit the small range: idr-narrow
||| writes it where values it proved small meet a big. A small holds no
||| reference and acquires nothing. A word outside the range has no big
||| here, as an overflowing nsw add has no sum: the pass that writes the op
||| is the proof, so its fold, the runtime's function of a word it holds,
||| meets only words that fit.
public export
bigSmall : Op 1 1 0 0
bigSmall = MkOp
  { home = InIdr
  , mnemonic = "big.small"
  , ins = [single "value" i64]
  , outs = [result "result" bigOrNatValue]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = [Declares InferIntRange ["inferResultRanges"]]
  , effects = computes
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = ComputedByRuntime (MkRuntimeCall "small_word" [TakesInt64] (Returns GivesBig))
  , verify = DeclarationOnly
  , format = plain 1
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = says "the small big or natural of a word that fits"
  }

||| A big or a natural as an integer, wrapped to the width.
public export
bigToInt : Op 1 1 0 0
bigToInt = MkOp
  { home = InIdr
  , mnemonic = "big.to_int"
  , ins = [single "value" bigOrNatRead]
  , outs = [result "result" int]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = [Declares InferIntRange ["inferResultRanges"]]
  , effects = computes
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = ComputedByRuntime (MkRuntimeCall "big_to_int" [TakesBig] (Returns GivesWrapped))
  , verify = DeclarationOnly
  , format = plain 1
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = [bigToWord (OnWords truncI)]
  , laws = []
  , doc = says "a big or a natural as an integer, wrapped to its width"
  }

||| A finite Double truncated to a big. The Double is finite:
||| `idr.check.finite` guards it.
public export
bigFromDouble : Op 1 1 0 0
bigFromDouble = MkOp
  { home = InIdr
  , mnemonic = "big.from_double"
  , ins = [single "value" f64]
  , outs = [result "result" bigValue]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = []
  , effects = builds 0 Touched
  , speculation = Conditionally
  , stages = Always
  , meaning = ComputedByRuntime (MkRuntimeCall "big_from_double" [TakesDouble] (Returns GivesBig))
  , verify = DeclarationOnly
  , format = plain 1
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = [MkGuard "check.finite" (0 ::: []) (caseRef causeClosed NonFiniteCast)]
  , specializations = []
  , laws = []
  , doc = says "a finite Double truncated to a big"
  }

public export
bigToDouble : Op 1 1 0 0
bigToDouble = MkOp
  { home = InIdr
  , mnemonic = "big.to_double"
  , ins = [single "value" bigRead]
  , outs = [result "result" f64]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = []
  , effects = computes
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = ComputedByRuntime (MkRuntimeCall "big_to_double" [TakesBig] (Returns GivesDouble))
  , verify = DeclarationOnly
  , format = plain 1
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = says "a big as the nearest Double"
  }

||| The decimal text of a big, which has a digit at least.
public export
bigShow : Op 1 1 0 0
bigShow = MkOp
  { home = InIdr
  , mnemonic = "big.show"
  , ins = [single "value" bigRead]
  , outs = [result "result" strValue]
  , attrs = []
  , regions = []
  , traits = [OurTrait neverEmpty]
  , interfaces = []
  , effects = builds 0 Touched
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = ComputedByRuntime (MkRuntimeCall "big_show" [TakesBig] (Returns GivesStr))
  , verify = DeclarationOnly
  , format = plain 1
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = says "the decimal text of a big"
  }

||| A string as a big, as prim__cast_StringInteger reads it.
public export
bigFromStr : Op 1 1 0 0
bigFromStr = MkOp
  { home = InIdr
  , mnemonic = "big.from_str"
  , ins = [single "str" strRead]
  , outs = [result "result" bigValue]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = []
  , effects = builds 0 Touched
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = ComputedByRuntime (MkRuntimeCall "big_from_str" [TakesStr] (Returns GivesBig))
  , verify = DeclarationOnly
  , format = plain 1
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = says "a string as a big, as prim__cast_StringInteger reads it"
  }

public export
bigOps : List AnyOp
bigOps =
  [ SomeOp bigAdd, SomeOp bigMul, SomeOp bigSub, SomeOp bigAnd, SomeOp bigOr, SomeOp bigXor
  , SomeOp bigShl, SomeOp bigShr, SomeOp bigDiv, SomeOp bigMod, SomeOp bigNeg, SomeOp natPred
  , SomeOp bigCmp, SomeOp natToBig, SomeOp natFromBig, SomeOp (bigFromInt Signed)
  , SomeOp (bigFromInt Unsigned), SomeOp bigSmall, SomeOp bigToInt, SomeOp bigFromDouble
  , SomeOp bigToDouble, SomeOp bigShow, SomeOp bigFromStr ]
