-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Closures and suspensions, as the frontend writes them, and the memo
||| cell's exchange, which is all of a suspension that defunctionalization
||| leaves.
|||
||| `idr.fn.closure` captures a function's leading parameters and
||| `idr.fn.apply` runs one; `idr.lazy.suspend` builds a cell that has not
||| run its function, `idr.lazy.force` reads it, and `idr.lazy.delay` is a
||| suspension of a value that already exists. Their carriers are
||| `!idr.fn` and `!idr.lazy`. The three that build are one capture family:
||| each takes its captures over, and its result is used once exactly when a
||| capture is. A closure and an evaluated suspension are immutable values
||| nothing reads the identity of, so two equal ones are one and an unused
||| one goes; a suspension's cell is the one value that changes while
||| references to it live, so it takes a fresh identity and is never merged
||| or folded. A run of a label (an apply, a force) is code no declaration
||| bounds until defunctionalization makes it a dispatch of calls: it
||| declares every ordering atom, so nothing moves it, merges it or deletes
||| it.
|||
||| After defunctionalization only the exchange is left: `idr.memo.run`
||| moves a memoized label's captures out of its cell into its one region,
||| where the cell runs, and the value the region yields into the cell's
||| forced state, which it also gives.
module IdrisMLIR.Spec.Closures.Declarations

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Effects.Declaration
import IdrisMLIR.Spec.Control.Flow

import Data.Fin
import Data.List1
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
closureValue = MkPredicate "isClosureValue" OnType (brief "a closure, at any grade")

||| A suspension at any grade: a value of `!idr.lazy`.
export
suspensionValue : Predicate
suspensionValue = MkPredicate "isSuspensionValue" OnType (brief "a suspension, at any grade")

||| A memo family's cell, the value a suspension became: what the exchange
||| reads and writes the state of.
export
memoCell : Predicate
memoCell = MkPredicate "isMemoCell" OnType (brief "a value of a memo family, its cell")

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

||| What each member of the capture family builds, and what that value is
||| to the effects: a value, or a cell with an identity.
public export
data Builds = AClosure | ASuspension

buildsName : Builds -> Mnemonic
buildsName AClosure = "fn.closure"
buildsName ASuspension = "lazy.suspend"

buildsResult : Builds -> Predicate
buildsResult AClosure = closureValue
buildsResult ASuspension = suspensionValue

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

buildsDoc : Builds -> Doc
buildsDoc AClosure = MkDoc "a closure of a function: its leading parameters are the captures"
  """
  `%c = idr.fn.closure @f(%x) : (T) -> !idr.fn<(A) -> (R)>`. The callee's
  parameters after the captures and its results are the carrier.
  """
buildsDoc ASuspension = MkDoc "a suspension of a function: every parameter is a capture"
  """
  `%s = idr.lazy.suspend @f(%x) : (T) -> !idr.lazy<R>`. The cell runs its
  function on the first force and keeps the value for every later one.
  """

||| `idr.fn.closure` and `idr.lazy.suspend`: a function's symbol and its captures.
export
captureOp : Builds -> Op 1 1 1 0
captureOp builds = MkOp
  { home = InIdr
  , mnemonic = buildsName builds
  , ins = [variadic "captures" (UpstreamType AnyTypeC)]
  , outs = [result "result" (SatisfiesType (buildsResult builds))]
  , attrs = [attr "callee" (UpstreamAttr FlatSymbolRefAttrC)]
  , regions = []
  , traits = [ResultUsesMaxOf 0 [0]]
  , interfaces =
      [ Declares SymbolUser ["verifySymbolUses"]
      , Implements flowInterface ["getFlowEdges"]
      , Declares OpAsm ["getAsmResultNames"] ]
  , effects = buildsEffects builds
  , speculation = AlwaysSpeculatable
  , stages = between Higher Higher
  , meaning = buildsMeaning builds
  , verify = DeclarationOnly
  , format = Declared
      [ ValueOf (AttrRef 0), Lit "(", ValueOf (OperandRef 0), Lit ")", AttrDict, Lit ":"
      , FunctionalType (OfGroup (OperandRef 0)) (OfGroup (ResultRef 0)) ]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = buildsDoc builds
  }

||| `idr.lazy.delay`: a suspension already evaluated, holding its operand. A
||| value: nothing reads its identity, since forcing it computes nothing.
delayOp : Op 1 1 0 0
delayOp = MkOp
  { home = InIdr
  , mnemonic = "lazy.delay"
  , ins = [single "value" (UpstreamType AnyTypeC)]
  , outs = [result "result" (SatisfiesType suspensionValue)]
  , attrs = []
  , regions = []
  , traits = [ResultUsesMaxOf 0 [0]]
  , interfaces = [Implements flowInterface ["getFlowEdges"], Declares OpAsm ["getAsmResultNames"]]
  , effects = Executes [] [Consumes 0] Covered Untouched
  , speculation = AlwaysSpeculatable
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
  , doc = MkDoc "a suspension already evaluated: it holds its operand"
      """
      `%s = idr.lazy.delay %v : T -> !idr.lazy<T>`. Its force is the value, at
      the quantity the force gives it.
      """
  }

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
      [ Implements runsLabelsInterface ["getLabelCarrier"]
      , Implements flowInterface ["getFlowEdges"]
      , Declares OpAsm ["getAsmResultNames"] ]
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
||| upstream's indirect call; which functions it runs the label solve says.
export
applyOp : Op 2 1 0 0
applyOp = MkOp
  { home = InIdr
  , mnemonic = "fn.apply"
  , ins = [single "callee" (SatisfiesType closureValue), variadic "args" (UpstreamType AnyTypeC)]
  , outs = [results "results" (UpstreamType AnyTypeC)]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces =
      [ Declares CallOp ["getCallableForCallee", "setCalleeFromCallable", "getArgOperands",
                          "getArgOperandsMutable"]
      , Implements runsLabelsInterface ["getLabelCarrier"]
      , Implements flowInterface ["getFlowEdges"]
      , Declares OpAsm ["getAsmResultNames"] ]
  , effects = unknownCode
  , speculation = NotSpeculatable
  , stages = between Higher Higher
  , meaning = NoFold
  , verify = VerifiesOp
  , format = Declared
      [ ValueOf (OperandRef 0), Lit "(", ValueOf (OperandRef 1), Lit ")", AttrDict, Lit ":"
      , QualifiedTypeOf (OfGroup (OperandRef 0)) ]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "applies a closure to arguments"
  }

------------------------------------------------------------------------------
-- The exchange
------------------------------------------------------------------------------

||| `idr.memo.run`: a memo cell's force, its captures moved out into its
||| region, which binds them, and its value moved in. It reads and writes
||| the cell's memo state; its region's effects are its own besides. The
||| cell keeps its reference: what moves out is what the label's state held.
memoRunOp : Op 1 1 1 1
memoRunOp = MkOp
  { home = InIdr
  , mnemonic = "memo.run"
  , ins = [single "cell" (SatisfiesType memoCell)]
  , outs = [results "outs" (UpstreamType AnyTypeC)]
  , attrs = [attr "tag" (UpstreamAttr I32AttrC)]
  , regions = [sized "region" 1]
  , traits = [SingleBlock]
  , interfaces =
      [ Declares RegionBranch ["getSuccessorInputs", "getRegionInvocationBounds"]
      , Implements flowInterface ["getFlowEdges"] ]
  , effects = Executes [OnValues Write MemoState (Operands 0)] [ReadsMemo 0] Recursive Untouched
  , speculation = NotSpeculatable
  , stages = between First Owned
  , meaning = NoFold
  , verify = VerifiesOpAndRegions
  , format = Declared
      [ ValueOf (OperandRef 0), Lit ":", TypeOf (OfGroup (OperandRef 0)), ValueOf (AttrRef 0)
      , OptionalGroup [Lit "->"] (TypeOf (OfGroup (ResultRef 0))) []
      , Regions, AttrDict ]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = MkDoc "a memo cell's force: its captures moved out, its value moved in"
      """
      `%v = idr.memo.run %cell : !idr.data<#Lazy> 0 -> (R) { ^(%c: T): ... }`.
      The cell is in the state of the label at the tag, one that memoizes;
      the region binds that label's captures as fields read from the cell
      are, runs once while the cell is running, and yields the value the
      cell's forced state holds, then each result.
      """
  }

||| `idr.memo.yield`: the end of an exchange's region. Its value moves into
||| the cell's forced state, which takes it over; what follows it leaves the
||| op as its results, which the region branch forwards.
memoYieldOp : Op 2 0 0 0
memoYieldOp = MkOp
  { home = InIdr
  , mnemonic = "memo.yield"
  , ins = [single "value" (UpstreamType AnyTypeC), variadic "results" (UpstreamType AnyTypeC)]
  , outs = []
  , attrs = []
  , regions = []
  , traits = [Terminator, ReturnLike, HasParent ("memo.run" ::: [])]
  , interfaces =
      [ Declares RegionBranchTerminator ["getMutableSuccessorOperands"]
      , Implements flowInterface ["getFlowEdges"] ]
  , effects = Executes [] [Consumes 0] Covered Untouched
  , speculation = AlwaysSpeculatable
  , stages = between First Owned
  , meaning = NoFold
  , verify = DeclarationOnly
  , format = Declared
      [ ValueOf (OperandRef 0), Lit ":", TypeOf (OfGroup (OperandRef 0))
      , OptionalGroup [Lit "then"] (ValueOf (OperandRef 1)) [Lit ":", TypeOf (OfGroup (OperandRef 1))]
      , AttrDict ]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "ends an exchange's region: the forced value into the cell, then the exchange's results"
  }

export
declarations : Declarations
declarations =
  { ops := [ SomeOp (captureOp AClosure), SomeOp (captureOp ASuspension), SomeOp delayOp
           , SomeOp forceOp, SomeOp applyOp, SomeOp memoRunOp, SomeOp memoYieldOp ]
  , types := [SomeType fnType, SomeType lazyType]
  , interfaces := [runsLabelsInterface]
  , predicates := [closureValue, suspensionValue, memoCell]
  , skeleton := [ MkSkeletonRule "ForceFreshCell" ("idr" ::: ["Transforms", "Defunctionalize.h"]) "memo.run"
                    "an exchange of a cell built for it alone runs its label in place: no reader sees the cell running or forced" ]
  } nothing
