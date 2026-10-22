-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Closures and suspensions, as the frontend writes them. The memo cell's
||| exchange, which is all of a suspension that defunctionalization leaves,
||| is `Closures.Memo`'s.
|||
||| `idr.fn.closure` captures a function's leading parameters and
||| `idr.fn.apply` runs one; `idr.lazy.suspend` builds a cell that has not
||| run its function, `idr.lazy.force` reads it, and `idr.lazy.delay` is a
||| suspension of a value that already exists. Their carriers are
||| `!idr.fn` and `!idr.lazy`. The three that build are one capture family:
||| each takes its captures over, and its result is used once exactly when a
||| capture is. A closure and a suspension name their function with the
||| terms its index variables take where they are built, so the label's
||| constructor is built at its refined family. A closure and an evaluated
||| suspension are immutable values
||| nothing reads the identity of, so two equal ones are one and an unused
||| one goes; a suspension's cell is the one value that changes while
||| references to it live, so it takes a fresh identity and is never merged
||| or folded. A run of a label (an apply, a force) is code no declaration
||| bounds until defunctionalization makes it a dispatch of calls: it
||| declares every ordering atom, so nothing moves it, merges it or deletes
||| it.
module IdrisMLIR.Spec.Closures.Declarations

import IdrisMLIR.Spec.Closures.Memo
import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Effects.Declaration
import IdrisMLIR.Spec.Control.Flow
import IdrisMLIR.Spec.Families.Dialect

import Data.Fin
import Data.List1
-- `captureOp`'s automatic proof is searched where it is written.
import public Data.So
import Data.Vect

%default total

------------------------------------------------------------------------------
-- The carriers
------------------------------------------------------------------------------

||| `!idr.fn<(A) -> (R)>`, C++ `FnType`: a closure, a cell holding its
||| captures, applied to the inputs and giving the results: its function's
||| parameters after the captures, and its results. Before
||| defunctionalization only, which makes each a constructor of its family.
export
fnType : TypeDef 2
fnType = MkTypeDef
  { mnemonic = "fn"
  , params =
      [ MkParameter "inputs" (ListOf TypeValue) AlwaysWritten "what it is applied to"
      , MkParameter "results" (ListOf TypeValue) AlwaysWritten "what it gives" ]
  , syntax = Declarative [Keyword "<", Keyword "(", ParamAt 0, Keyword ")", Keyword "->", Keyword "(", ParamAt 1, Keyword ")", Keyword ">"]
  , interfaces = [Declares MemRefElementType [], Declares OpAsmType ["getAsmName"]]
  , verifier = AnyParameters
  , bytecode = Derived
  , members = []
  , facts = Answers (MkValueFacts HoldsReferences UsedAsGraded Counted AlwaysCell)
  , doc = brief "a closure: a cell holding its captures"
  }

||| `!idr.lazy<T>`, C++ `LazyType`: a suspension of one value, one cell
||| shared by every reference to it, forced once. Before
||| defunctionalization only, which makes each a memo family's cell, whose
||| constructor is its state: a flag beside the value could disagree with
||| the state, and the constructor cannot.
export
lazyType : TypeDef 1
lazyType = MkTypeDef
  { mnemonic = "lazy"
  , params = [MkParameter "value" TypeValue AlwaysWritten "the value its force gives"]
  , syntax = Declarative [Keyword "<", ParamAt 0, Keyword ">"]
  , interfaces = [Declares MemRefElementType [], Declares OpAsmType ["getAsmName"]]
  , verifier = AnyParameters
  , bytecode = Derived
  , members = []
  , facts = Answers (MkValueFacts HoldsReferences UsedAsGraded Counted AlwaysCell)
  , doc = brief "a suspension of one value, forced once into its cell"
  }

------------------------------------------------------------------------------
-- What the ops take
------------------------------------------------------------------------------

||| A closure at any grade: a value of `!idr.fn`.
export
closureValue : Predicate
closureValue = MkPredicate "isClosureType" OnType (brief "a closure, at any grade")

||| A suspension at any grade: a value of `!idr.lazy`.
export
suspensionValue : Predicate
suspensionValue = MkPredicate "isLazyType" OnType (brief "a suspension, at any grade")

------------------------------------------------------------------------------
-- What reads a label
------------------------------------------------------------------------------

||| `RunsLabelsOpInterface`: an op that runs the labels of a value it holds
||| (an apply its callee's, a force its suspension's), which the label solve
||| asks for that value and defunctionalization replaces by a dispatch.
export
runsLabelsInterface : InterfaceDef
runsLabelsInterface = MkInterfaceDef
  { name = "RunsLabelsOpInterface"
  , subject = OverOps
  , bases = []
  , methods =
      [ MkMethod PerObject "::mlir::Value" "getLabelCarrier" [] EveryImplementer
          "the closure or suspension whose labels this op runs" ]
  , verifier = Unverified
  , doc = brief "an op that runs the labels a closure or a suspension holds"
  }

------------------------------------------------------------------------------
-- The capture family
------------------------------------------------------------------------------

||| What each member of the capture family builds: a closure of a function,
||| a suspension of a function, or a suspension already evaluated, of a
||| value.
data Builds = AClosure | ASuspension | AnEvaluated

||| What a member's value is made of: a function, which the member names
||| with the terms its index variables take where the member is built, or a
||| value that already exists.
data Made = OfFunction | OfValue

madeOf : Builds -> Made
madeOf AClosure = OfFunction
madeOf ASuspension = OfFunction
madeOf AnEvaluated = OfValue

||| How many attributes a member names: a function's symbol and its index
||| terms, or none.
nameCount : Made -> Nat
nameCount OfFunction = 2
nameCount OfValue = 0

||| A function and the terms its index variables take, which are erased:
||| quantity 0, passed at compile time only, as a call passes them.
attrsOf : (m : Made) -> Vect (nameCount m) Attr
attrsOf OfFunction = [attr "callee" (UpstreamAttr FlatSymbolRefAttrC), MkAttr "index_args" indexArgs]
attrsOf OfValue = []

||| What a member takes over: a function's leading parameters, or the one
||| value it holds.
capturesOf : Made -> Operand
capturesOf OfFunction = variadic "captures" (UpstreamType AnyTypeC)
capturesOf OfValue = single "value" (UpstreamType AnyTypeC)

buildsName : Builds -> Mnemonic
buildsName AClosure = "fn.closure"
buildsName ASuspension = "lazy.suspend"
buildsName AnEvaluated = "lazy.delay"

||| What a member builds: a closure, or a suspension.
builtOf : Builds -> Result
builtOf AClosure = result "result" (SatisfiesType closureValue)
builtOf ASuspension = result "result" (SatisfiesType suspensionValue)
builtOf AnEvaluated = result "result" (SatisfiesType suspensionValue)

||| A closure's captures are taken over; its result is a value. A
||| suspension's cell is a fresh identity besides: never merged, hoisted or
||| folded, deletable when unused. An evaluated suspension is a value:
||| forcing it computes nothing, so nothing reads its identity.
buildsEffects : Builds -> Declaration 1 1
buildsEffects AClosure = Executes [] [Consumes 0] Covered Untouched
buildsEffects ASuspension = Executes [] [Consumes 0, NewIdentity 0] Covered Untouched
buildsEffects AnEvaluated = Executes [] [Consumes 0] Covered Untouched

||| A closure of constants folds to its constant; a suspension never folds.
buildsMeaning : Builds -> Meaning 1 1
buildsMeaning AClosure = HandFolder
buildsMeaning ASuspension = NoFold
buildsMeaning AnEvaluated = NoFold

||| A member of a function is checked through the symbol it names, at its
||| index terms; an evaluated suspension, which names none, checks its value
||| against its type.
symbolUse : Made -> List InterfaceUse
symbolUse OfFunction = [Declares SymbolUser ["verifySymbolUses"]]
symbolUse OfValue = []

verifyOf : Made -> Verify
verifyOf OfFunction = DeclarationOnly
verifyOf OfValue = VerifiesOp

formatOf : (m : Made) -> Format 1 1 (nameCount m) 0
formatOf OfFunction = Declared
  [ ValueOf (AttrRef 0), Lit "(", ValueOf (OperandRef 0), Lit ")", PropDict, AttrDict, Lit ":"
  , FunctionalType (OfGroup (OperandRef 0)) (OfGroup (ResultRef 0)) ]
formatOf OfValue = Declared
  [ ValueOf (OperandRef 0), AttrDict, Lit ":", TypeOf (OfGroup (OperandRef 0)), Lit "->"
  , TypeOf (OfGroup (ResultRef 0)) ]

buildsDoc : Builds -> Doc
buildsDoc AClosure = MkDoc "a closure of a function: its leading parameters are the captures"
  """
  `%c = idr.fn.closure @f(%x) <{index_args = #idr.index_args<[v0]>}> : (T) -> !idr.fn<(A) -> (R)>`.
  The callee's signature at the index terms: its parameters after the
  captures and its results are the carrier.
  """
buildsDoc ASuspension = MkDoc "a suspension of a function: every parameter is a capture"
  """
  `%s = idr.lazy.suspend @f(%x) <{index_args = #idr.index_args<[v0]>}> : (T) -> !idr.lazy<R>`.
  The cell runs its function, at the index terms, on the first force and
  keeps the value for every later one.
  """
buildsDoc AnEvaluated = MkDoc "a suspension already evaluated: it holds its operand"
  """
  `%s = idr.lazy.delay %v : T -> !idr.lazy<T>`. Its force is the value, at
  the quantity the force gives it.
  """

||| `idr.fn.closure`, `idr.lazy.suspend` and `idr.lazy.delay`: each takes
||| its captures over, and its result is used once exactly when a capture
||| is, which holds of every member by construction.
captureOp : (b : Builds)
  -> {auto 0 named : So (distinct (groupNames [capturesOf (madeOf b)] [builtOf b] (attrsOf (madeOf b)) []))}
  -> Op 1 1 (nameCount (madeOf b)) 0
captureOp b = MkOp
  { home = InIdr
  , mnemonic = buildsName b
  , ins = [capturesOf (madeOf b)]
  , outs = [builtOf b]
  , attrs = attrsOf (madeOf b)
  , regions = []
  , traits = [ResultUsesMaxOf 0 [0]]
  , interfaces = symbolUse (madeOf b) ++ [Implements flowInterface ["getFlowEdges"]]
  , effects = buildsEffects b
  , speculation = AlwaysSpeculatable
  , stages = between Higher Higher
  , meaning = buildsMeaning b
  , verify = verifyOf (madeOf b)
  , format = formatOf (madeOf b)
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = buildsDoc b
  }

||| The capture family's members, each by its name, so a reader of one
||| member's facts (Emit, the quantity its result takes) reads them here.
export
closureOp : Op 1 1 2 0
closureOp = captureOp AClosure

export
suspendOp : Op 1 1 2 0
suspendOp = captureOp ASuspension

export
delayOp : Op 1 1 0 0
delayOp = captureOp AnEvaluated

------------------------------------------------------------------------------
-- The runs of a label
------------------------------------------------------------------------------

||| `idr.lazy.force`: the value of a suspension, computed on the first force and
||| shared. Its fold is the value of an evaluated suspension.
forceOp : Op 1 1 0 0
forceOp = MkOp
  { home = InIdr
  , mnemonic = "lazy.force"
  , ins = [single "suspension" (SatisfiesType suspensionValue)]
  , outs = [result "result" (UpstreamType AnyTypeC)]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces =
      [Implements runsLabelsInterface ["getLabelCarrier"], Implements flowInterface ["getFlowEdges"]]
  , effects = unknownCode
  , speculation = NotSpeculatable
  , stages = between Higher Higher
  , meaning = HandFolder
  , verify = VerifiesOp
  , format = Declared
      [ ValueOf (OperandRef 0), AttrDict, Lit ":", TypeOf (OfGroup (OperandRef 0)), Lit "->"
      , TypeOf (OfGroup (ResultRef 0)) ]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "the value of a suspension, computed on the first force and shared"
  }

||| `idr.fn.apply`: a closure applied to arguments. A call through a value,
||| upstream's indirect call, with its attributes per argument and per
||| result, which upstream's call interface reads; which functions it runs
||| the label solve says. Its arguments and results are its closure's up to
||| what each holds, which counting grades after the closure's type is
||| fixed, so their types are written beside the closure's.
export
applyOp : Op 2 1 2 0
applyOp = MkOp
  { home = InIdr
  , mnemonic = "fn.apply"
  , ins = [single "callee" (SatisfiesType closureValue), variadic "args" (UpstreamType AnyTypeC)]
  , outs = [results "results" (UpstreamType AnyTypeC)]
  , attrs =
      [ MkAttr "arg_attrs" (AnAttribute (UpstreamAttr DictArrayAttrC) MayBeAbsent)
      , MkAttr "res_attrs" (AnAttribute (UpstreamAttr DictArrayAttrC) MayBeAbsent) ]
  , regions = []
  , traits = []
  , interfaces =
      [ Declares CallOp ["getCallableForCallee", "setCalleeFromCallable", "getArgOperands",
                          "getArgOperandsMutable"]
      , Implements runsLabelsInterface ["getLabelCarrier"]
      , Implements flowInterface ["getFlowEdges"] ]
  , effects = unknownCode
  , speculation = NotSpeculatable
  , stages = between Higher Higher
  , meaning = NoFold
  , verify = VerifiesOp
  , format = Declared
      [ ValueOf (OperandRef 0), Lit "(", ValueOf (OperandRef 1), Lit ")", PropDict, AttrDict, Lit ":"
      , QualifiedTypeOf (OfGroup (OperandRef 0)), Lit ","
      , FunctionalType (OfGroup (OperandRef 1)) (OfGroup (ResultRef 0)) ]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "applies a closure to arguments"
  }

export
declarations : Declarations
declarations =
  { ops := [SomeOp closureOp, SomeOp suspendOp, SomeOp delayOp, SomeOp forceOp, SomeOp applyOp] ++ memoOps
  , types := [SomeType fnType, SomeType lazyType]
  , interfaces := [runsLabelsInterface]
  , predicates := [closureValue, suspensionValue, memoState]
  , skeleton := [ MkSkeletonRule "ForceFreshCell" ("idr" ::: ["Transforms", "Defunctionalize.h"]) "memo.run"
                    "an exchange of a cell built for it alone runs its label in place: no reader sees the cell running or forced" ]
  } nothing
