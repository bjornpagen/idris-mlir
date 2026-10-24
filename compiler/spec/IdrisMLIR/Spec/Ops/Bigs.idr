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
import IdrisMLIR.Spec.Grades.Grade
import IdrisMLIR.Spec.Ops.Numeric
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
  , stages = between Higher Owned
  , params = [MkParameter "value" IntegerValue AlwaysWritten "the integer, at its fewest signed bits"]
  , syntax = Declarative [Keyword "<", ParamAt 0, Keyword ">"]
  , interfaces =
      [ Implements constantAttrInterface ["isBuildableAt", "getStaticForm", "verifyParts", "getFoldValue"]
      , Implements integerKeyAttrInterface ["getKeyInteger"] ]
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

||| An op that leaves a natural as it is: its result is its first operand
||| wherever that operand is not negative (an Integer made a natural), so
||| idr-narrow takes the operand's word as it is where nothing is negative.
public export
leavesNaturals : TraitDef
leavesNaturals = MkTraitDef "LeavesNaturals" (says "its result is its first operand wherever that operand is not negative")

||| `BigWordOpInterface`: a conversion between a big and its word, either
||| way, and the value it converts (`getValue`, the operand's own accessor).
||| A big made of an integer, its word its operand, takes
||| `BigOfIntegerOpInterface` besides, which says how the word is read; an
||| integer read out of a big, its word its result, takes this alone. A
||| pass that takes bigs back to their words finds every conversion by
||| asking this, and lists none.
public export
bigWordInterface : InterfaceDef
bigWordInterface = MkInterfaceDef
  { name = "BigWordOpInterface"
  , subject = OverOps
  , bases = []
  , methods =
      [ MkMethod PerObject "::mlir::Value" "getValue" [] EveryImplementer
          "the value it converts: the integer a big is made of, or the big an integer is read out of" ]
  , verifier = Unverified
  , doc = says "a conversion between a big and its word, either way"
  }

||| `BigOfIntegerOpInterface`: an Integer or a natural made of an integer,
||| the word side of the conversion its operand, the integer
||| (`BigWordOpInterface`'s `getValue`), and how the integer is read
||| (`getSignedness`, the constant of its class, `BigOfInteger<Op>`), so a
||| pass that takes a big back to its word asks the op and lists none.
public export
bigOfIntegerInterface : InterfaceDef
bigOfIntegerInterface = MkInterfaceDef
  { name = "BigOfIntegerOpInterface"
  , subject = OverOps
  , bases = [bigWordInterface]
  , methods =
      [ MkMethod PerObject "::idr::numeric::Signedness" "getSignedness" [] (DelegatesByClass "signednessOfOp")
          "how the integer is read: its top bit its sign, or the natural its bits are" ]
  , verifier = Unverified
  , doc = says "a big made of an integer, and how the integer is read"
  }

||| The constant of a big made of an integer: how it reads the integer.
bigOfInteger : Signedness -> Specialized
bigOfInteger sign = MkSpecialized "BigOfInteger" [("signedness", EnumConstant (caseRef signednessClosed sign))]

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

||| An Integer's function of two Integers, `idris_rt_big_<stem>`, each read
||| in place as `read` takes it, its result as `made` gives it.
twoBigs : (read : Ident -> Taken) -> (made : Ident -> FunctionGives 1) -> Symbol -> RuntimeFunction 2 1
twoBigs read made s = MkRuntimeFunction s [read "lhs", read "rhs"] (made "result")

||| An op of two Integers that builds an Integer: Integer's sub, and, or,
||| xor, its shifts, its division.
public export
binary : Mnemonic -> Symbol -> List Member -> Doc -> Op 2 1 0 0
binary m s ms d = MkOp
  { home = InIdr
  , mnemonic = m
  , ins = operandsOf runtime
  , outs = resultsOf runtime
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = []
  , effects = builds 0 Touched
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = ComputedByRuntime runtime
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
  where
    runtime : RuntimeFunction 2 1
    runtime = twoBigs bigInt returnsBig s

------------------------------------------------------------------------------
-- Arithmetic
------------------------------------------------------------------------------

||| The sum and the product of two naturals are natural, so these take
||| Integers or naturals, and give what they take: Nat's plus and mult are
||| these ops. An Integer's sum and product are exact, never wrapped, so each
||| is associative, with 0 and 1 its identities: laws the e-graph and the
||| accumulator read.
public export
naturalBinary : Mnemonic -> Symbol -> Admitted -> List Law -> Doc -> Op 2 1 0 0
naturalBinary m s word ls d = MkOp
  { home = InIdr
  , mnemonic = m
  , ins = operandsOf runtime
  , outs = resultsOf runtime
  , attrs = []
  , regions = []
  , traits = [SameCarrierOperands]
  , interfaces = [Declares InferIntRange ["inferResultRanges"]]
  , effects = builds 0 Touched
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = ComputedByRuntime runtime
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
  where
    runtime : RuntimeFunction 2 1
    runtime = twoBigs bigOrNat returnsBigOrNat s

||| A natural's successor is a sum with a constant one, so asked how its
||| result is built, a sum one of whose operands is a constant one answers
||| the successor of the other, read off its own operands, and any other
||| sum answers that it builds none.
public export
bigAdd : Op 2 1 0 0
bigAdd =
  { interfaces := [Declares InferIntRange ["inferResultRanges"], Implements structureInterface ["getStructure"]] }
  (naturalBinary "big.add" "big_add" addI [Associative, Identity 0] (says "the sum of two bigs or two naturals"))

public export
bigMul : Op 2 1 0 0
bigMul = naturalBinary "big.mul" "big_mul" mulI [Associative, Identity 1] (says "the product of two bigs or two naturals")

public export
bigSub : Op 2 1 0 0
bigSub =
  { interfaces := [Declares InferIntRange ["inferResultRanges"]]
  , specializations := [bigToWord (OnWords subI)] }
  (binary "big.sub" "big_sub" [] (says "the difference of two bigs"))

-- The bitwise ops are the runtime's, on the infinite two's complement of
-- each Integer, so each is associative bit by bit, and its identity is the
-- Integer whose every bit leaves the other's: -1, every bit set, for and;
-- 0, none set, for or and xor.

public export
bigAnd : Op 2 1 0 0
bigAnd =
  { laws := [Associative, Identity (-1)] }
  (binary "big.and" "big_and" [] (says "the bitwise and of two bigs"))

public export
bigOr : Op 2 1 0 0
bigOr =
  { laws := [Associative, Identity 0] }
  (binary "big.or" "big_or" [] (says "the bitwise or of two bigs"))

public export
bigXor : Op 2 1 0 0
bigXor =
  { laws := [Associative, Identity 0] }
  (binary "big.xor" "big_xor" [] (says "the bitwise xor of two bigs"))

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
public export
division : Mnemonic -> Symbol -> Doc -> Op 2 1 0 0
division m s d =
  { guards := [MkGuard NonZero [1] DivisionByZero]
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
  , ins = operandsOf runtime
  , outs = resultsOf runtime
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = []
  , effects = builds 0 Touched
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = ComputedByRuntime runtime
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
  where
    runtime : RuntimeFunction 1 1
    runtime = MkRuntimeFunction "big_neg" [bigInt "value"] (returnsBig "result")

||| The predecessor of a natural that is not zero, which the frontend writes
||| where a match on a natural found it is not zero, so the value visibly
||| shrinks. A constant zero is on a path the match excludes: no fold makes
||| its predecessor (`foldable`). Asked how its result is built, it answers
||| the predecessor of its operand.
public export
natPred : Op 1 1 0 0
natPred = MkOp
  { home = InIdr
  , mnemonic = "nat.pred"
  , ins = operandsOf runtime
  , outs = resultsOf runtime
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = [Declares InferIntRange ["inferResultRanges"], Implements structureInterface ["getStructure"]]
  , effects = builds 0 Touched
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = ComputedByRuntime runtime
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
  where
    runtime : RuntimeFunction 1 1
    runtime = MkRuntimeFunction "big_pred" [nat "value"] (returnsNat "result")

||| Two Integers or two naturals compared, as the runtime orders them, by
||| the op's predicate: Nat's equalNat and compareNat are this op.
public export
bigCmp : Op 2 1 1 0
bigCmp = MkOp
  { home = InIdr
  , mnemonic = "big.cmp"
  , ins = operandsOf runtime
  , outs = resultsOf runtime
  , attrs = [property "predicate" (EnumProperty comparisonEnum)]
  , regions = []
  , traits = [SameCarrierOperands]
  , interfaces = [Declares InferIntRange ["inferResultRanges"]]
  , effects = computes
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = ComputedByRuntime runtime
  , verify = DeclarationOnly
  , format = attrFirst 2 0
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = [bigToWord (OnWords cmpI)]
  , laws = []
  , doc = says "compares two bigs or two naturals"
  , typing = fixedTypes (resultsOf runtime)
  }
  where
    runtime : RuntimeFunction 2 1
    runtime = MkRuntimeFunction "big_cmp" [bigOrNat "lhs", bigOrNat "rhs"] (returnsOrder "result")

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
  , members = [compositeMeaning "::idr::NatToBigOp"]
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
  , ins = operandsOf runtime
  , outs = resultsOf runtime
  , attrs = []
  , regions = []
  , traits = [OurTrait leavesNaturals]
  , interfaces = [Declares InferIntRange ["inferResultRanges"]]
  , effects = Executes [OnValues Write Count (Results 0)] [] Covered Untouched
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = ComputedByRuntime runtime
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
  where
    runtime : RuntimeFunction 1 1
    runtime = MkRuntimeFunction "nat_from_big" [bigInt "value"] (returnsNat "result")

public export
fromIntName : Signedness -> Mnemonic
fromIntName Signed = "big.from_sint"
fromIntName Unsigned = "big.from_uint"

fromIntSymbol : Signedness -> Symbol
fromIntSymbol Signed = "big_from_int_s"
fromIntSymbol Unsigned = "big_from_int_u"

||| An integer as an Integer, read as the op's signedness says. The runtime
||| writes a large one's limbs straight into the result's cell, so the cell
||| the result names is all the memory it acquires.
public export
bigFromInt : Signedness -> Op 1 1 0 0
bigFromInt sign = MkOp
  { home = InIdr
  , mnemonic = fromIntName sign
  , ins = operandsOf runtime
  , outs = resultsOf runtime
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = [Declares InferIntRange ["inferResultRanges"], Implements bigOfIntegerInterface []]
  , effects = builds 0 Untouched
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = ComputedByRuntime runtime
  , verify = DeclarationOnly
  , format = plain 1
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = [bigOfInteger sign]
  , laws = []
  , doc = says "an integer as a big"
  }
  where
    runtime : RuntimeFunction 1 1
    runtime = MkRuntimeFunction (fromIntSymbol sign) [extended sign "value"] (returnsBigOf sign "result")

||| A small's grade: static data, which nothing frees and no count writes,
||| used any number of times. `big.small` fixes it on its result, and the
||| frontend's value of the op is held at it.
public export
smallGrade : FixedGrade
smallGrade = MkFixedGrade Many Static

||| The big or natural of a word proved to fit the small range: idr-narrow
||| writes it where values it proved small meet a big. A small is a word
||| with no cell: it holds no reference and acquires nothing, so its type
||| is static data's (`smallGrade`), and a use that asks for a value its
||| count frees is given it by a share. Its one builder, the C++ one and
||| the frontend's alike, takes the carrier, the big or the natural, and
||| gives it that grade, so no writer states the type. A word outside the
||| range has no big here, as an overflowing nsw add has no sum: the pass
||| that writes the op is the proof, so its fold, the runtime's function of
||| a word it holds, meets only words that fit.
public export
bigSmall : Op 1 1 0 0
bigSmall = MkOp
  { home = InIdr
  , mnemonic = "big.small"
  , ins = operandsOf runtime
  , outs = resultsOf runtime
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = [Declares InferIntRange ["inferResultRanges"], Implements bigOfIntegerInterface []]
  , effects = computes
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = ComputedByRuntime runtime
  , verify = DeclarationOnly
  , format = plain 1
  , builders = [MkBuilder [param "::mlir::Type" "carrier", param "::mlir::Value" "value"]]
  , defaultBuilders = DeclaredOnly
  , members = []
  , guards = []
  , specializations = [bigOfInteger Signed]
  , laws = []
  , doc = says "the small big or natural of a word that fits"
  , typing = CarriersAt [smallGrade]
  }
  where
    runtime : RuntimeFunction 1 1
    runtime = MkRuntimeFunction "small_word" [word64 "value"] (returnsSmall "result")

||| A big or a natural as an integer, wrapped to the width.
public export
bigToInt : Op 1 1 0 0
bigToInt = MkOp
  { home = InIdr
  , mnemonic = "big.to_int"
  , ins = operandsOf runtime
  , outs = resultsOf runtime
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = [Declares InferIntRange ["inferResultRanges"], Implements bigWordInterface []]
  , effects = computes
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = ComputedByRuntime runtime
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
  where
    runtime : RuntimeFunction 1 1
    runtime = MkRuntimeFunction "big_to_int" [bigOrNat "value"] (returnsWrapped "result")

||| A finite Double truncated to a big. The Double is finite:
||| `idr.check.finite` guards it.
public export
bigFromDouble : Op 1 1 0 0
bigFromDouble = MkOp
  { home = InIdr
  , mnemonic = "big.from_double"
  , ins = operandsOf runtime
  , outs = resultsOf runtime
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = []
  , effects = builds 0 Touched
  , speculation = Conditionally
  , stages = Always
  , meaning = ComputedByRuntime runtime
  , verify = DeclarationOnly
  , format = plain 1
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = [MkGuard Finite [0] NonFiniteCast]
  , specializations = []
  , laws = []
  , doc = says "a finite Double truncated to a big"
  }
  where
    runtime : RuntimeFunction 1 1
    runtime = MkRuntimeFunction "big_from_double" [float64 "value"] (returnsBig "result")

public export
bigToDouble : Op 1 1 0 0
bigToDouble = MkOp
  { home = InIdr
  , mnemonic = "big.to_double"
  , ins = operandsOf runtime
  , outs = resultsOf runtime
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = []
  , effects = computes
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = ComputedByRuntime runtime
  , verify = DeclarationOnly
  , format = plain 1
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = says "a big as the nearest Double"
  , typing = fixedTypes (resultsOf runtime)
  }
  where
    runtime : RuntimeFunction 1 1
    runtime = MkRuntimeFunction "big_to_double" [bigInt "value"] (returnsFloat64 "result")

showBig : RuntimeFunction 1 1
showBig = MkRuntimeFunction "big_show" [bigInt "value"] (returnsStr "result")

||| What writes a big's decimal text where the output stands, by the
||| formatter big_show uses, into the output buffer: no string, and of a big
||| beyond a small only the runtime's own temporaries.
public export
putBig : RuntimeHelper
putBig = writerOf "ioPutBig" "io_put_big" showBig "writes the decimal text of a big to standard output"

||| The decimal text of a big, which has a digit at least.
public export
bigShow : Op 1 1 0 0
bigShow = MkOp
  { home = InIdr
  , mnemonic = "big.show"
  , ins = operandsOf showBig
  , outs = resultsOf showBig
  , attrs = []
  , regions = []
  , traits = [OurTrait neverEmpty]
  , interfaces = []
  , effects = builds 0 Touched
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = ComputedByRuntime showBig
  , verify = DeclarationOnly
  , format = plain 1
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = [shownOutput putBig]
  , laws = []
  , doc = says "the decimal text of a big"
  }

||| A string as a big, as prim__cast_StringInteger reads it.
public export
bigFromStr : Op 1 1 0 0
bigFromStr = MkOp
  { home = InIdr
  , mnemonic = "big.from_str"
  , ins = operandsOf runtime
  , outs = resultsOf runtime
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = []
  , effects = builds 0 Touched
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = ComputedByRuntime runtime
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
  where
    runtime : RuntimeFunction 1 1
    runtime = MkRuntimeFunction "big_from_str" [str "str"] (returnsBig "result")

public export
bigOps : List AnyOp
bigOps =
  [ SomeOp bigAdd, SomeOp bigMul, SomeOp bigSub, SomeOp bigAnd, SomeOp bigOr, SomeOp bigXor
  , SomeOp bigShl, SomeOp bigShr, SomeOp bigDiv, SomeOp bigMod, SomeOp bigNeg, SomeOp natPred
  , SomeOp bigCmp, SomeOp natToBig, SomeOp natFromBig, SomeOp (bigFromInt Signed)
  , SomeOp (bigFromInt Unsigned), SomeOp bigSmall, SomeOp bigToInt, SomeOp bigFromDouble
  , SomeOp bigToDouble, SomeOp bigShow, SomeOp bigFromStr ]
