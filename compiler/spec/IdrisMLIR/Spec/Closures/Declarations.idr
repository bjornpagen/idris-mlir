-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Closures and suspensions, as the frontend writes them. The memo cell's
||| exchange, which is all of a suspension that defunctionalization leaves,
||| is `Closures.Memo`'s.
|||
||| `idr.fn.closure` captures a function's leading parameters and
||| `idr.fn.apply` runs one; `idr.lazy.suspend` builds a cell that has not
||| run its function, and `idr.lazy.force` reads it. Their carriers are
||| `!idr.fn` and `!idr.lazy`. The two that build are one capture family:
||| each takes its captures over, and its result is used once exactly when a
||| capture is. Each names its function with the terms its index variables
||| take where it is built, so the label's constructor is built at its
||| refined family. A closure is an immutable value nothing reads the
||| identity of, so two equal ones are one and an unused one goes; a
||| suspension's cell is the one value that changes while references to it
||| live, so it takes a fresh identity and is never merged or folded. A run
||| of a label (an apply, a force) is code no declaration bounds until
||| defunctionalization makes it a dispatch of calls: it declares every
||| ordering atom, so nothing moves it, merges it or deletes it.
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
||| parameters after the captures, and its results. Either list may be
||| empty, `!idr.fn<() -> ()>`, so each is a group its emptiness leaves out
||| between its parentheses. Before defunctionalization only, which makes
||| each a constructor of its family.
export
fnType : TypeDef 2
fnType = MkTypeDef
  { mnemonic = "fn"
  , stages = between Higher Higher
  , params =
      [ MkParameter "inputs" (ListOf TypeValue) (DefaultsTo "::llvm::SmallVector<::mlir::Type>()") "what it is applied to"
      , MkParameter "results" (ListOf TypeValue) (DefaultsTo "::llvm::SmallVector<::mlir::Type>()") "what it gives" ]
  , syntax = Declarative
      [ Keyword "<", Keyword "(", OptionalParams (AloneAtDefault ")") 0 [Keyword ")"]
      , Keyword "->", Keyword "(", OptionalParams (AloneAtDefault ")") 1 [Keyword ")"], Keyword ">" ]
  , interfaces = [Declares MemRefElementType [], Declares OpAsmType ["getAsmName"]]
  , verifier = AnyParameters
  , bytecode = Derived
  , members = []
  , facts = Answers (MkValueFacts HoldsReferences UsedAsGraded Counted AlwaysCell (Always CellAddress)
                      (Always ClosureLabels) NotMemory)
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
  , stages = between Higher Higher
  , params = [MkParameter "value" TypeValue AlwaysWritten "the value its force gives"]
  , syntax = Declarative [Keyword "<", ParamAt 0, Keyword ">"]
  , interfaces = [Declares MemRefElementType [], Declares OpAsmType ["getAsmName"]]
  , verifier = AnyParameters
  , bytecode = Derived
  , members = []
  , facts = Answers (MkValueFacts HoldsReferences UsedAsGraded Counted AlwaysCell (Always CellAddress)
                      (Always SuspensionLabels) NotMemory)
  , doc = brief "a suspension of one value, forced once into its cell"
  }

------------------------------------------------------------------------------
-- The constant closure
------------------------------------------------------------------------------

||| A constant closure's function, by its symbol: `@f`.
export
calleeRefParam : Directive
calleeRefParam = MkDirective "CalleeRef" [] (brief "a constant closure's function, by its symbol: `@f`")

||| A constant closure's captures, each a constant: `[1 : i64, #idr.big<7>]`.
export
capturesParam : Directive
capturesParam = MkDirective "Captures" [] (brief "a constant closure's captures, each a constant")

||| `#idr.closure<@f, [captures]>`, C++ `ClosureAttr`: a closure every
||| capture of which is a constant, what `idr.fn.closure` folds to, held by
||| `idr.constant` at the closure's type. It names its function with no
||| index terms: a closure at terms stays an op, so the function's binders
||| are those its family determines. Before defunctionalization only, which
||| makes each its label's constructor in its slot's family.
export
closureAttr : AttrDef 2
closureAttr = MkAttrDef
  { mnemonic = "closure"
  , stages = between Higher Higher
  , params =
      [ MkParameter "callee" (WiredValue (WiredOne (LeafAttr "::mlir::FlatSymbolRefAttr")) calleeRefParam)
          AlwaysWritten "the function it closes over"
      , MkParameter "captures" (WiredValue (WiredOne (LeafAttr "::mlir::ArrayAttr")) capturesParam)
          AlwaysWritten "its captures, the function's leading parameters, each a constant" ]
  , syntax = Declarative [Keyword "<", ParamAt 0, Keyword ",", ParamAt 1, Keyword ">"]
  , interfaces = [Implements constantAttrInterface ["isBuildableAt", "getStaticForm", "verifyParts", "getClosureHolding", "getFoldValue"]]
  , verifier = AnyParameters
  , bytecode = Derived
  , members = []
  , doc = brief "a closure whose captures are constants"
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
-- What builds a label
------------------------------------------------------------------------------

||| `BuildsLabelOpInterface`: an op that builds a label's constructor (a
||| closure or a suspension of a function), which names the function and
||| the terms its index variables take where it is built, so
||| defunctionalization builds the constructor at its refined family
||| without telling the two apart. Each method is the op's own accessor.
export
buildsLabelInterface : InterfaceDef
buildsLabelInterface = MkInterfaceDef
  { name = "BuildsLabelOpInterface"
  , subject = OverOps
  , bases = []
  , methods =
      [ MkMethod PerObject "::mlir::Value" "getResult" [] EveryImplementer
          "the closure or suspension it builds"
      , MkMethod PerObject "::mlir::FlatSymbolRefAttr" "getCalleeAttr" [] EveryImplementer
          "the function whose label it builds"
      , MkMethod PerObject "::idr::IndexArgsAttr" "getIndexArgs" [] EveryImplementer
          "the terms the function's index variables take where it is built" ]
  , verifier = Unverified
  , doc = brief "an op that builds the constructor of a function's label"
  }

------------------------------------------------------------------------------
-- The capture family
------------------------------------------------------------------------------

||| What each member of the capture family builds: a closure of a function,
||| or a suspension of a function.
data Builds = AClosure | ASuspension

||| A function and the terms its index variables take, which are erased:
||| quantity 0, passed at compile time only, as a call passes them.
functionAttrs : Vect 2 Attr
functionAttrs = [attr "callee" (UpstreamAttr FlatSymbolRefAttrC), MkAttr "index_args" indexArgs]

||| What a member takes over: its function's leading parameters.
leadingCaptures : Operand
leadingCaptures = variadic "captures" (UpstreamType AnyTypeC)

public export
buildsName : Builds -> Mnemonic
buildsName AClosure = "fn.closure"
buildsName ASuspension = "lazy.suspend"

||| What a member builds: a closure, or a suspension.
builtValue : Builds -> Predicate
builtValue AClosure = closureValue
builtValue ASuspension = suspensionValue

||| A closure's captures are taken over; its result is a value. A
||| suspension's cell is a fresh identity besides: never merged, hoisted or
||| folded, deletable when unused.
buildsEffects : Builds -> Declaration 1 1
buildsEffects AClosure = Executes [] [Consumes 0] Covered Untouched
buildsEffects ASuspension = Executes [] [Consumes 0, NewIdentity 0] Covered Untouched

||| A closure of constants folds to its constant; a suspension never folds.
buildsMeaning : Builds -> Meaning 1 1
buildsMeaning AClosure = HandFolder
buildsMeaning ASuspension = NoFold

||| The hand folder's condition, the closure's: a closure of constants is the
||| constant idr.constant holds at its type.
buildsMembers : Builds -> List Member
buildsMembers AClosure = [compositeMeaning "::idr::FnClosureOp"]
buildsMembers ASuspension = []

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

||| `idr.fn.closure` and `idr.lazy.suspend`: each takes its captures over,
||| and its result is used once exactly when a capture is, which holds of
||| every member by construction. Each is checked through the symbol it
||| names, at its index terms, and builds that function's label. Every
||| member's operands, result and attributes are named alike.
public export
captureOp : Builds -> Op 1 1 2 0
captureOp b = MkOp
  { home = InIdr
  , mnemonic = buildsName b
  , ins = [leadingCaptures]
  , outs = [result "result" (SatisfiesType (builtValue b))]
  , attrs = functionAttrs
  , regions = []
  , traits = [ResultUsesMaxOf 0 [0]]
  , interfaces =
      [ Declares SymbolUser ["verifySymbolUses"], Implements buildsLabelInterface []
      , Implements flowInterface ["getFlowEdges"] ]
  , effects = buildsEffects b
  , speculation = AlwaysSpeculatable
  , stages = between Higher Higher
  , meaning = buildsMeaning b
  , verify = DeclarationOnly
  , format = Declared
      [ ValueOf (AttrRef 0), Lit "(", ValueOf (OperandRef 0), Lit ")", PropDict, AttrDict, Lit ":"
      , FunctionalType (OfGroup (OperandRef 0)) (OfGroup (ResultRef 0)) ]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = buildsMembers b
  , guards = []
  , specializations = []
  , laws = []
  , doc = buildsDoc b
  }

||| The capture family's members, each by its name, so a reader of one
||| member's facts (Emit, the quantity its result takes) reads them here.
public export
closureOp : Op 1 1 2 0
closureOp = captureOp AClosure

public export
suspendOp : Op 1 1 2 0
suspendOp = captureOp ASuspension

------------------------------------------------------------------------------
-- The runs of a label
------------------------------------------------------------------------------

||| `idr.lazy.force`: the value of a suspension, computed on the first force and
||| shared.
public export
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
  , meaning = NoFold
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
public export
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

public export
declarations : Declarations
declarations =
  { ops := [SomeOp closureOp, SomeOp suspendOp, SomeOp forceOp, SomeOp applyOp] ++ memoOps
  , types := [SomeType fnType, SomeType lazyType]
  , attributes := [SomeAttr closureAttr]
  , interfaces := [runsLabelsInterface, buildsLabelInterface]
  , skeleton := [ MkSkeletonRule "ForceFreshCell" ("idr" ::: ["Transforms", "Defunctionalize.h"]) "memo.run"
                    "an exchange of a cell built for it alone runs its label in place: no reader sees the cell running or forced" ]
  } nothing
