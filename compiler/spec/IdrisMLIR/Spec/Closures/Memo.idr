-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The memo cell's exchange, which is all of a suspension that
||| defunctionalization leaves: a force of a memoized label moves the
||| label's captures out of the cell, which is running while the label runs
||| on them, and moves the value it computes into the cell's forced state.
|||
||| The exchange reads the captures as fields of the cell, so it takes the
||| cell as its dispatch's case binds it, refined to the label's state at the
||| label's binders: the captures are at the label's indices, and the state
||| is the refinement's, held once. `idr.memo.run` holds the label's run as
||| its one region. Where a pass cannot keep that region, because the label
||| runs a call on its own function's cycle that frames must split, the
||| exchange is its steps: `idr.memo.take` moves the captures out, the
||| region's code runs in place, and `idr.memo.store` moves the value in, a
||| step of its own a continuation can begin with.
module IdrisMLIR.Spec.Closures.Memo

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Effects.Declaration
import IdrisMLIR.Spec.Control.Flow

import Data.Fin
import Data.List1
import Data.Vect

%default total

||| A memo family's cell refined to one of its states, as a case of its
||| dispatch binds it: what the exchange reads the captures of and writes
||| the state of.
export
memoState : Predicate
memoState = MkPredicate "isMemoState" OnType (brief "a memo family's cell, refined to one of its states")

||| What every step of an exchange states of its cell: the data type, and
||| the state its refinement names.
cellMembers : List Member
cellMembers =
  [ MkMember OnObject "::idr::DataType" "getDataType" []
  , MkMember OnObject "::idr::Tag" "getTag" [] ]

||| `idr.memo.run`: a memo cell's force, its captures moved out into its
||| region, which binds them, and its value moved in. It reads and writes
||| the cell's memo state; its region's effects are its own besides. The
||| cell keeps its reference: what moves out is what the label's state held.
public export
memoRunOp : Op 1 1 0 1
memoRunOp = MkOp
  { home = InIdr
  , mnemonic = "memo.run"
  , ins = [single "cell" (SatisfiesType memoState)]
  , outs = [results "outs" (UpstreamType AnyTypeC)]
  , attrs = []
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
      [ ValueOf (OperandRef 0), Lit ":", TypeOf (OfGroup (OperandRef 0))
      , OptionalGroup [Lit "->"] (TypeOf (OfGroup (ResultRef 0))) []
      , Regions, AttrDict ]
  , builders = []
  , defaultBuilders = WithDefaults
  , members =
      cellMembers ++
      [ MkMember OnObject "void" "split" [param "::mlir::RewriterBase &" "rewriter"] ]
  , guards = []
  , specializations = []
  , laws = []
  , doc = MkDoc "a memo cell's force: its captures moved out, its value moved in"
      """
      `%v = idr.memo.run %cell : !idr.data<#lazy@f<v1>> -> (R) { ^(%c: T): ... }`.
      The cell is refined to the state of a label that memoizes; the region
      binds that label's captures as reads of the cell's fields give them,
      runs once while the cell is running, and yields the value the cell's
      forced state holds at its indices, then each result. `split` makes it
      its steps, `idr.memo.take`, the region's code and `idr.memo.store`.
      """
  }

||| `idr.memo.yield`: the end of an exchange's region. Its value moves into
||| the cell's forced state, which takes it over; what follows it leaves the
||| op as its results, which the region branch forwards.
public export
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

||| `idr.memo.take`: an exchange's first step, its captures moved out of the
||| cell, each at the type a read of its field gives, which the cell infers;
||| the cell is running from then on and keeps its reference.
public export
memoTakeOp : Op 1 1 0 0
memoTakeOp = MkOp
  { home = InIdr
  , mnemonic = "memo.take"
  , ins = [single "cell" (SatisfiesType memoState)]
  , outs = [results "captures" (UpstreamType AnyTypeC)]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = [InfersTypes InferredOnly, Implements flowInterface ["getFlowEdges"]]
  , effects = Executes [OnValues Write MemoState (Operands 0)] [ReadsMemo 0] Covered Untouched
  , speculation = NotSpeculatable
  , stages = between First Owned
  , meaning = NoFold
  , verify = VerifiesOp
  , format = Declared [ValueOf (OperandRef 0), AttrDict, Lit ":", TypeOf (OfGroup (OperandRef 0))]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = cellMembers
  , guards = []
  , specializations = []
  , laws = []
  , doc = MkDoc "an exchange's first step: the captures moved out of the cell, which runs"
      """
      `%c:2 = idr.memo.take %cell : !idr.data<#lazy@f<v1>>`. The cell is
      refined to the state of a label that memoizes.
      """
  }

||| `idr.memo.store`: an exchange's last step, the value moved into the
||| cell's forced state, which takes it over. A step of its own, so the code
||| after a call the label's run makes on its own cycle, which frames moves
||| into a continuation, begins with it.
public export
memoStoreOp : Op 2 0 0 0
memoStoreOp = MkOp
  { home = InIdr
  , mnemonic = "memo.store"
  , ins = [single "cell" (SatisfiesType memoState), single "value" (UpstreamType AnyTypeC)]
  , outs = []
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = [Implements flowInterface ["getFlowEdges"]]
  , effects = Executes [OnValues Write MemoState (Operands 0)] [Consumes 1] Covered Untouched
  , speculation = NotSpeculatable
  , stages = between First Owned
  , meaning = NoFold
  , verify = VerifiesOp
  , format = Declared
      [ ValueOf (OperandRef 1), Lit "into", ValueOf (OperandRef 0), AttrDict, Lit ":"
      , TypeOf (OfGroup (OperandRef 1)), Lit ",", TypeOf (OfGroup (OperandRef 0)) ]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = cellMembers
  , guards = []
  , specializations = []
  , laws = []
  , doc = MkDoc "an exchange's last step: the value moved into the cell, which is forced"
      """
      `idr.memo.store %v into %cell : R, !idr.data<#lazy@f<v1>>`. The cell
      is the one its `idr.memo.take` took the captures of; the value is the
      forced state's at the cell's indices.
      """
  }

||| The exchange's ops, its region form and its steps.
public export
memoOps : List AnyOp
memoOps = [SomeOp memoRunOp, SomeOp memoYieldOp, SomeOp memoTakeOp, SomeOp memoStoreOp]
