-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What ends a run by a crash, and the guards whose conditions the total
||| ops need: a crash of a cause of the closed set (`idr.crash.cause`) and a
||| trusted library's crash of a string it computed (`idr.crash.message`).
||| Each source of a crash's message is its own op, since the runtime takes
||| each its own way: a cause by its position in the runtime's table, a
||| string as itself. A loop that may not end carries its divergence in its
||| own effects, so no op marks it.
|||
||| A crash's site is an inherent property, written by the frontend from
||| the source and never read from the op's location, which an equivalence
||| ignores and a rewrite may replace: two crashes of one cause at two sites
||| stay two. A partial primitive is a guard and a total op: the guard
||| crashes with its cause at its site where its condition fails, and gives
||| its operand otherwise, which the total op takes, so the op stays below
||| its check by data dependence and a proof is the absence of the guard.
||| The upstream ops one of these guards guards (arith's unsigned division) are
||| admitted here, since each names its guard op by value.
module IdrisMLIR.Spec.Ops.Checks

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Effects.Declaration
import IdrisMLIR.Spec.Runtime.Endings
import IdrisMLIR.Spec.Control.Flow
import IdrisMLIR.Spec.Ops.Numeric
import IdrisMLIR.Spec.Ops.Shapes

import Data.List1
import Data.So
import Data.Vect

%default total

------------------------------------------------------------------------------
-- Sites
------------------------------------------------------------------------------

||| `#idr.site<"Main.idr", 10, 1, "Main.name">`, C++ `SiteAttr`: the file,
||| line and column of a crash's place in the source, and the function its
||| place lies in, which the message names for a cause that names one. The
||| file and the function are uniqued text, so the lowering makes one
||| global for each, shared by every site that names it.
public export
siteAttr : AttrDef 4
siteAttr = MkAttrDef
  { mnemonic = "site"
  , params =
      [ MkParameter "file" StringValue AlwaysWritten "the source file"
      , MkParameter "line" CountValue AlwaysWritten "the line, from 1"
      , MkParameter "column" CountValue AlwaysWritten "the column, from 1"
      , MkParameter "function" StringValue AlwaysWritten "the function the place lies in, as Idris names it" ]
  , syntax = Declarative
      [ Keyword "<", ParamAt 0, Keyword ",", ParamAt 1, Keyword ",", ParamAt 2, Keyword ","
      , ParamAt 3, Keyword ">" ]
  , typed = Untyped
  , interfaces = []
  , verifier = AnyParameters
  , bytecode = Derived
  , members = []
  , doc = says "the place in the source a crash is at"
  }

causeSlot : Attr
causeSlot = property "cause" (EnumProperty (imported causeClosed
  (MkSource ("IdrisMLIR" ::: ["Spec", "Runtime", "Endings"]) "Cause"
            ("IdrisMLIR" ::: ["Spec", "Runtime", "Endings"]) "causeClosed")))

siteSlot : Attr
siteSlot = attr "site" (OurAttr (SomeAttr siteAttr))

------------------------------------------------------------------------------
-- The ends of a run
------------------------------------------------------------------------------

||| The run ends by a crash.
endsByCrash : Declaration i o
endsByCrash = Executes [OnState Write Crash] [] Covered Untouched

||| A crash of a cause of the closed set at its site: a terminator with no
||| successor, so nothing after it in its region runs. The runtime writes
||| the cause's phrase from its table, after the site, and the site's
||| function where the cause names one.
public export
crashOp : Op 0 0 2 0
crashOp = MkOp
  { home = InIdr
  , mnemonic = "crash.cause"
  , ins = []
  , outs = []
  , attrs = [causeSlot, siteSlot]
  , regions = []
  , traits = [Terminator]
  , interfaces = []
  , effects = endsByCrash
  , speculation = NotSpeculatable
  , stages = Always
  , meaning = NoFold
  , verify = DeclarationOnly
  , format = Declared [ValueOf (AttrRef 0), Lit "at", ValueOf (AttrRef 1), AttrDict]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = says "ends the program with a crash of a cause at a site"
  }

||| idr.crash.cause ends the run: its declaration writes the crash.
export
0 crashStops : Stops (effects Checks.crashOp)
crashStops = StopsByCrash

||| A trusted library's crash of a string it computed, `idris_crash`, at its
||| site: the message is the string's text.
public export
crashMessageOp : Op 1 0 1 0
crashMessageOp = MkOp
  { home = InIdr
  , mnemonic = "crash.message"
  , ins = [single "message" strRead]
  , outs = []
  , attrs = [siteSlot]
  , regions = []
  , traits = [Terminator]
  , interfaces = []
  , effects = endsByCrash
  , speculation = NotSpeculatable
  , stages = Always
  , meaning = NoFold
  , verify = DeclarationOnly
  , format = Declared [ValueOf (OperandRef 0), Lit "at", ValueOf (AttrRef 0), AttrDict, Lit ":", TypeOf (OfGroup (OperandRef 0))]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = says "ends the program with a string's text at a site"
  }

export
0 crashMessageStops : Stops (effects Checks.crashMessageOp)
crashMessageStops = StopsByCrash

------------------------------------------------------------------------------
-- The guards
------------------------------------------------------------------------------

||| What every guard is: the operand it guards, its first, which it gives
||| as its result; its cause and its site, its own properties; its
||| condition decided on what the e-graph knows of its operands, which its
||| rule asks (a guard that holds goes, one that fails is a crash of its
||| cause at its site, with no test at run time): each operand's interval,
||| an integer the graph knows being its one value whether an op holds it or
||| the graph computed it, and the constant an op holds of one an interval
||| says nothing of (a string, a Double, an Integer past i64).
public export
guardInterface : InterfaceDef
guardInterface = MkInterfaceDef
  { name = "GuardOpInterface"
  , subject = OverOps
  , bases = []
  , methods =
      [ MkMethod PerObject "::mlir::Value" "getGuarded" [] (Delegates "guardedOperand")
          "the operand the guard guards, its first, which it gives as its result"
      , MkMethod PerObject "::idr::CrashCause" "getCause" [] EveryImplementer
          "the cause its crash names"
      , MkMethod PerObject "::idr::SiteAttr" "getSite" [] EveryImplementer
          "the place in the source its crash is at"
      , MkMethod PerClass "::idr::numeric::Known" "decide"
          [ param "::llvm::ArrayRef<::mlir::ConstantIntRanges>" "ranges"
          , param "::llvm::ArrayRef<::mlir::Attribute>" "constants" ] EveryImplementer
          "whether its condition holds, fails, or is unknown on its operands' intervals and the constants ops hold of them"
      ]
  , verifier = Unverified
  , doc = says "a guard of a partial primitive's operands"
  }

||| Whether a guard's condition holds of the constants its fold adaptor
||| holds: what its folder and, through GuardedOp, every folder of the ops
||| it guards ask before computing.
holds : Member
holds = MkMember OnClass "bool" "holds" [param "FoldAdaptor" "adaptor"]

||| Its condition on its operands' intervals and the constants ops hold of
||| them, the interface's `decide`: each guard's own, its operands'
||| structure being its own. Its cause and site are its generated
||| accessors, which the interface's methods are.
decideMember : Member
decideMember = MkMember OnClass "::idr::numeric::Known" "decide"
  [ param "::llvm::ArrayRef<::mlir::ConstantIntRanges>" "ranges"
  , param "::llvm::ArrayRef<::mlir::Attribute>" "constants" ]

||| A condition read off the run's own state too, the runtime's handle
||| table, where the run ends by a crash if it fails.
readsTableOrCrashes : Declaration i o
readsTableOrCrashes = Executes [OnState Read RuntimeState, OnState Write Crash] [] Covered Untouched

||| What a guard's condition is: one of the numeric template's conditions,
||| or the guard's own code, where the condition is no integer arithmetic
||| (a string's emptiness, a Double's finiteness, what the handle table
||| holds).
data GuardMeaning = OfTemplate GuardCondition | OwnCode

guardMeaning : GuardMeaning -> Meaning i o
guardMeaning (OfTemplate c) = InlineCondition (conditionName c)
guardMeaning OwnCode = HandFolder

||| A guard over its operands, its result the first of them, at that
||| operand's own type, which its rule infers, so its type is stated once,
||| as the operand's constraint; with its own cause and site, its
||| condition, and the effects its condition has: a crash where it fails,
||| which every guard's declaration writes, and what the condition reads
||| besides its operands.
guardOp : {others : Nat} -> (m : Mnemonic) -> (ins : Vect (S others) Operand)
       -> GuardMeaning -> (eff : Declaration (S others) 1) -> List (Trait (S others) 1)
       -> List InterfaceUse -> Doc
       -> {auto 0 fails : Found (anyOf Declaration.crashes (effectsOf eff))}
       -> {auto 0 named : So (distinct (groupNames ins [result "checked" (head ins).type] [Checks.causeSlot, Checks.siteSlot] []))}
       -> Op (S others) 1 2 0
guardOp m ins tested eff traits ifaces d = MkOp
  { home = InIdr
  , mnemonic = m
  , ins = ins
  , outs = [result "checked" (head ins).type]
  , attrs = [causeSlot, siteSlot]
  , regions = []
  , traits = traits
  , interfaces = Implements guardInterface [] :: ifaces
  , effects = eff
  , speculation = NotSpeculatable
  , stages = Always
  , meaning = guardMeaning tested
  , verify = DeclarationOnly
  , format = Declared
      (operandItems (S others) ++ [Lit ",", ValueOf (AttrRef 0), Lit "at", ValueOf (AttrRef 1), AttrDict, Lit ":", FunctionalType OfOperands OfResults])
  , builders = []
  , defaultBuilders = WithDefaults
  , members = [holds, decideMember]
  , guards = []
  , specializations = []
  , laws = []
  , doc = d
  , typing = InferredTypes [OperandType FZ]
  }

||| A divisor, which must not be zero: an integer or an Integer. Its result
||| is its operand, whose reference it hands on.
public export
nonzeroOp : Op 1 1 2 0
nonzeroOp = guardOp "check.nonzero"
  [single "value" (AnyOfTypes (int ::: [bigValue]) "an integer or an Integer")]
  (OfTemplate DivisorNonzero) endsByCrash []
  [Implements flowInterface ["getFlowEdges"], Declares InferIntRange ["inferResultRanges"]]
  (says "the value, which must not be zero, else the program crashes")

||| An index as a string's op takes it, a word, or as an array's access
||| does, upstream's `index`: one guard over both carriers.
indexCarrier : TypeC
indexCarrier = AnyOfTypes (i64 ::: [UpstreamType IndexC]) "an i64 or an index"

||| An index of a string or of an array of one dimension, below its length:
||| the guard takes what is indexed, so the index is checked against the
||| very value the op reads. Its result is the index, at the index's own
||| type.
public export
inBoundsOp : Op 2 1 2 0
inBoundsOp = guardOp "check.in_bounds"
  [ single "index" indexCarrier
  , single "indexed" (AnyOfTypes (strRead ::: [SatisfiesType rank1ArrayP]) "a string or an array of one dimension") ]
  (OfTemplate IndexInBounds) endsByCrash []
  [Declares InferIntRange ["inferResultRangesFromOptional"]]
  (says "the index, which must be at least 0 and below the length of what it indexes, else the program crashes")

||| A string, which must have a byte at least. Its result is its operand,
||| whose reference it hands on.
public export
nonemptyOp : Op 1 1 2 0
nonemptyOp = guardOp "check.nonempty" [single "str" strValue] OwnCode endsByCrash []
  [Implements flowInterface ["getFlowEdges"]]
  (says "the string, which must have at least one byte, else the program crashes")

public export
finiteOp : Op 1 1 2 0
finiteOp = guardOp "check.finite" [single "value" f64] OwnCode endsByCrash [] []
  (says "the value, which must be neither NaN nor infinite, else the program crashes")

||| The bytes [offset, offset + count) of something of `size` bytes: both
||| at least 0, and the end, computed without overflow, at most the size.
public export
rangeOp : Op 3 1 2 0
rangeOp = guardOp "check.range" [single "offset" i64, single "count" i64, single "size" i64] (OfTemplate BytesInRange) endsByCrash
  []
  [Declares InferIntRange ["inferResultRanges"]]
  (says "the offset, whose range of `count` bytes must lie in `size`, else the program crashes")

||| A handle, which must hold a string, the program's or the runtime's:
||| what base's getString reads. The handle table says at run time
||| (`idris_rt_handle_holds_string`), so the condition reads it. No constant
||| handle holds one: the program's constant handles are null and the
||| standard streams, and every string handle is one the runtime gave.
public export
holdsStringOp : Op 1 1 2 0
holdsStringOp = guardOp "check.holds_string" [single "handle" i64] OwnCode readsTableOrCrashes
  [] []
  (says "the handle, which must hold a string, else the program crashes")

||| Every guard: the ops the e-graph's guard rules are rooted at, each rule
||| reading what it needs of a guard off the guard's own declaration.
public export
guardOps : List AnyOp
guardOps =
  [ SomeOp nonzeroOp, SomeOp inBoundsOp, SomeOp nonemptyOp, SomeOp finiteOp, SomeOp rangeOp
  , SomeOp holdsStringOp ]

public export
checkOps : List AnyOp
checkOps = SomeOp crashOp :: SomeOp crashMessageOp :: guardOps

------------------------------------------------------------------------------
-- The upstream ops these guards guard
------------------------------------------------------------------------------

-- An unsigned quotient and remainder, upstream's meaning: their divisor is
-- the result of idr.check.nonzero, which the frontend builds before each
-- from the guard stated here, so each stands below its guard by data
-- dependence, as every total op does, and upstream speculates neither
-- unless its divisor is a constant other than zero. Each names its guard
-- op by value, so it is declared here, beside the guard.

||| The divisor, upstream's second operand group, is not zero.
divisorNonzero : Guard Nat
divisorNonzero = MkGuard nonzeroOp [1] DivisionByZero

public export
divUI : Admitted
divUI = { guards := [divisorNonzero] } (arithOp "Arith_DivUIOp" [] (rangedBy "inferDivU"))

public export
remUI : Admitted
remUI = { guards := [divisorNonzero] } (arithOp "Arith_RemUIOp" [] (rangedBy "inferRemU"))

||| Every upstream op the dialect admits with a guard, once.
public export
checkedAdmitted : List Admitted
checkedAdmitted = [divUI, remUI]
