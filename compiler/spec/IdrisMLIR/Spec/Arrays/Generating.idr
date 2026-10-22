-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The generating set of the array language: a tabulation, a fold and a
||| scan along the last axis, each a region from the indices of a domain to
||| what goes at that index, and the yield that ends their regions; and the
||| three movements a step of one makes in its buffers.
|||
||| Each op is destination-style, as upstream's structured ops are, and
||| means upstream's tensor semantics: on tensors its results are its
||| destinations written, and it computes nothing but values; on buffers it
||| writes its destinations and gives nothing. It stands as one op from the
||| frontend to right before the lowering, through bufferization (upstream's
||| destination model) and counting (its flow and its effects), and is then
||| its loops, made by upstream's `lowerToLoopsUsingSCFForOp` from the three
||| tiling methods it implements, in row-major order, the last axis fastest.
||| Every other tiling method keeps its failing default, so nothing retiles
||| an order the program can observe. Its iterator types are its region's:
||| `parallel` on its frame where the region only computes, `reduction`
||| everywhere else, which on an op with no partial reduction means in
||| order, carried. So the effects of IO, which the world once ordered, and
||| crashes, which keep their order among themselves, are an order the
||| region states and the op keeps, with no world.
module IdrisMLIR.Spec.Arrays.Generating

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Effects.Declaration
import IdrisMLIR.Spec.Control.Flow

import Data.Fin
import Data.List1
import Data.Vect

%default total

------------------------------------------------------------------------------
-- What the generating set's operands are
------------------------------------------------------------------------------

||| A value array's buffer: a memref in the default memory space, which no
||| mutable memory is in, at any grade.
export
valueBuffer : Predicate
valueBuffer = MkPredicate "isValueBuffer" OnType
  (brief "a value array's buffer, a memref in the default memory space, at any grade")

||| A destination of the generating set, or an input of a scan: a value
||| array as a tensor, or, after bufferization, its buffer.
export
array : TypeC
array = AnyOfTypes (UpstreamType AnyRankedTensorC ::: [SatisfiesType valueBuffer])
  "a ranked tensor or a value array's buffer"

------------------------------------------------------------------------------
-- The shapes the generating set shares
------------------------------------------------------------------------------

||| `YieldTargetsOpInterface`: an op whose region gives values into memory
||| it holds, read by the yield that ends the region, so that no yield
||| lists its parents. A generating op's targets are its results on
||| tensors and its destinations on buffers; a memo cell's force's, its
||| cell.
export
yieldTargetsInterface : InterfaceDef
yieldTargetsInterface = MkInterfaceDef
  { name = "YieldTargetsOpInterface"
  , subject = OverOps
  , bases = []
  , methods =
      [ MkMethod PerObject "::mlir::ValueRange" "getYieldTargets" [] EveryImplementer
          "the arrays or the cell the region's values move into, one each" ]
  , verifier = Unverified
  , doc = brief "an op whose region gives values into memory it holds"
  }

||| `LastAxisFoldOpInterface`: what a pass asks of a fold or a scan along
||| an array's last axis, so that none tells them apart to read one: the
||| accumulators' first values, the axis's length, the frame's rank, the
||| accumulators the region binds.
export
lastAxisFoldInterface : InterfaceDef
lastAxisFoldInterface = MkInterfaceDef
  { name = "LastAxisFoldOpInterface"
  , subject = OverOps
  , bases = []
  , methods =
      [ MkMethod PerObject "::mlir::OperandRange" "getInits" [] EveryImplementer
          "the accumulators' first values"
      , MkMethod PerObject "::mlir::Value" "getLength" [] EveryImplementer
          "the length of the axis folded"
      , MkMethod PerObject "unsigned" "getFrameRank" [] EveryImplementer
          "the rank of the frame each step reads"
      , MkMethod PerObject "::mlir::Block::BlockArgListType" "getAccumulators" [] EveryImplementer
          "the accumulators the region binds" ]
  , verifier = Unverified
  , doc = brief "a fold or a scan of accumulators along an array's last axis"
  }

||| What every op of the generating set implements of upstream's and ours:
||| destination style; the three tiling methods its loops are made from;
||| region branching from the op into its region, round again, and out,
||| forwarding nothing; its results' shapes, its destinations'; the bounds
||| of its indices and of its results' dimensions; where what it holds
||| moves; the memory its region's values go into.
generatingInterfaces : List InterfaceUse
generatingInterfaces =
  [ Declares DestinationStyle []
  , Declares Tiling ["getLoopIteratorTypes", "getIterationDomain", "generateScalarImplementation"]
  , Declares RegionBranch ["getSuccessorRegions"]
  , Declares ReifyRankedShapedType ["reifyResultShapes"]
  , Declares ValueBounds ["populateBoundsForIndexValue", "populateBoundsForShapedValueDim"]
  , Implements flowInterface ["getFlowEdges"]
  , Implements yieldTargetsInterface ["getYieldTargets"] ]

||| The members each op of the generating set defines by hand: its
||| destinations as upstream's interface asks for them, and the rank of its
||| domain, the number of indices its region binds first.
generatingMembers : List Member
generatingMembers =
  [ MkMember OnObject "::mlir::MutableOperandRange" "getDpsInitsMutable" []
  , MkMember OnObject "unsigned" "getRank" [] ]

||| The members a fold and a scan add: the frame's rank and the
||| accumulators the region binds after the indices.
foldMembers : List Member
foldMembers =
  [ MkMember OnObject "unsigned" "getFrameRank" []
  , MkMember OnObject "::mlir::Block::BlockArgListType" "getAccumulators" [] ]

------------------------------------------------------------------------------
-- The generating ops
------------------------------------------------------------------------------

||| `idr.array.tabulate`: each destination written at every index of the
||| domain with what the region gives there, the j-th value for the j-th
||| destination; the domain is the destinations' leading dimensions, which
||| they share, and a value is an element, or the cell of the dimensions
||| after them. The region runs once per index, never on an empty domain. A
||| destination of elements that hold references is fresh, a `tensor.empty`
||| or an `alloc_tensor` (the op's verifier), so placing its slots releases
||| nothing.
|||
|||   %t = idr.array.tabulate outs(%e : tensor<?xi64>) {
|||   ^bb0(%i: index):
|||     %x = arith.index_cast %i : index to i64
|||     idr.array.yield %x : i64
|||   } -> tensor<?xi64>
export
tabulateOp : Op 1 1 0 1
tabulateOp = MkOp
  { home = InIdr
  , mnemonic = "array.tabulate"
  , ins = [variadic "outs" array]
  , outs = [results "arrays" (UpstreamType AnyRankedTensorC)]
  , attrs = []
  , regions = [sized "region" 1]
  , traits = [SingleBlock]
  , interfaces = generatingInterfaces
  , effects = Executes [] [WritesBuffers 0] Recursive Untouched
  , speculation = Conditionally
  , stages = between Higher Owned
  , meaning = NoFold
  , verify = VerifiesOpAndRegions
  , format = Declared
      [ Lit "outs", Lit "(", ValueOf (OperandRef 0), Lit ":", TypeOf (OfGroup (OperandRef 0))
      , Lit ")", ValueOf (RegionRef 0), AttrDict
      , OptionalGroup [Lit "->"] (TypeOf (OfGroup (ResultRef 0))) [] ]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = generatingMembers ++
      [MkMember OnObject "::llvm::SmallVector<::mlir::Type>" "getCellTypes" []]
  , guards = []
  , specializations = []
  , laws = []
  , doc = MkDoc "each destination written at each index with what the region gives there"
      """
      A new array, as upstream's tensor semantics means one, built in its
      destination: the domain is the destinations' leading dimensions, each
      value an element or the cell after them. On buffers the op writes the
      destinations and gives nothing.
      """
  }

||| `idr.array.fold_last`: for each index of the frame, the left fold along
||| the last axis of the domain, `length` long, from what each destination
||| holds there, which the last accumulator replaces. The region binds the
||| frame's indices, the fold's index and the accumulators, and gives the
||| next accumulators. A rank-0 destination is an accumulator of no frame.
export
foldLastOp : Op 2 1 0 1
foldLastOp = MkOp
  { home = InIdr
  , mnemonic = "array.fold_last"
  , ins = [single "length" (UpstreamType IndexC), variadic "inits" array]
  , outs = [results "results" (UpstreamType AnyRankedTensorC)]
  , attrs = []
  , regions = [sized "region" 1]
  , traits = [SingleBlock]
  , interfaces = generatingInterfaces ++ [Implements lastAxisFoldInterface []]
  , effects = Executes [] [ReadsBuffers 1, WritesBuffers 1] Recursive Untouched
  , speculation = Conditionally
  , stages = between Higher Owned
  , meaning = NoFold
  , verify = VerifiesOpAndRegions
  , format = Declared
      [ Lit "[", ValueOf (OperandRef 0), Lit "]"
      , Lit "outs", Lit "(", ValueOf (OperandRef 1), Lit ":", TypeOf (OfGroup (OperandRef 1))
      , Lit ")", ValueOf (RegionRef 0), AttrDict
      , OptionalGroup [Lit "->"] (TypeOf (OfGroup (ResultRef 0))) [] ]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = generatingMembers ++ foldMembers
  , guards = []
  , specializations = []
  , laws = []
  , doc = MkDoc "for each index of a frame, a left fold along one more dimension"
      """
      The fold reads its first accumulators from its destinations and leaves
      the last in their place: the destinations are the inits.
      """
  }

||| `idr.array.scan_last`: the fold of `idr.array.fold_last` with every
||| accumulator kept. It reads its first accumulators from its inputs and
||| writes each step's into its destination at that step: a destination's
||| dimensions are the frame's, then `length`, then the input's cell's.
export
scanLastOp : Op 3 1 0 1
scanLastOp = MkOp
  { home = InIdr
  , mnemonic = "array.scan_last"
  , ins = [single "length" (UpstreamType IndexC), variadic "inits" array, variadic "outs" array]
  , outs = [results "results" (UpstreamType AnyRankedTensorC)]
  , attrs = []
  , regions = [sized "region" 1]
  , traits = [SingleBlock, AttrSizedOperandSegments]
  , interfaces = generatingInterfaces ++ [Implements lastAxisFoldInterface []]
  , effects = Executes [] [ReadsBuffers 1, WritesBuffers 2] Recursive Untouched
  , speculation = Conditionally
  , stages = between Higher Owned
  , meaning = NoFold
  , verify = VerifiesOpAndRegions
  , format = Declared
      [ Lit "[", ValueOf (OperandRef 0), Lit "]"
      , Lit "ins", Lit "(", ValueOf (OperandRef 1), Lit ":", TypeOf (OfGroup (OperandRef 1)), Lit ")"
      , Lit "outs", Lit "(", ValueOf (OperandRef 2), Lit ":", TypeOf (OfGroup (OperandRef 2))
      , Lit ")", ValueOf (RegionRef 0), AttrDict
      , OptionalGroup [Lit "->"] (TypeOf (OfGroup (ResultRef 0))) [] ]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = generatingMembers ++ foldMembers
  , guards = []
  , specializations = []
  , laws = []
  , doc = MkDoc "for each index of a frame, every accumulator of a left fold"
      """
      A scan reads its inputs and writes its destinations, which it never
      reads: the first accumulator of each frame index is the input's there,
      each later one the step before's.
      """
  }

||| `idr.array.yield`: the end of a step of the generating set, what goes
||| at the step's index, each value moving into its destination there (the
||| flow interface, read off the parent's targets). It ends a generating
||| op's region only; nothing is forwarded to a successor.
export
arrayYieldOp : Op 1 0 0 0
arrayYieldOp = MkOp
  { home = InIdr
  , mnemonic = "array.yield"
  , ins = [variadic "values" (UpstreamType AnyTypeC)]
  , outs = []
  , attrs = []
  , regions = []
  , traits =
      [Terminator, HasParent ("array.tabulate" ::: ["array.fold_last", "array.scan_last"])]
  , interfaces =
      [ Declares RegionBranchTerminator ["getMutableSuccessorOperands"]
      , Implements flowInterface ["getFlowEdges"] ]
  , effects = Executes [] [Consumes 0] Covered Untouched
  , speculation = NotSpeculatable
  , stages = between Higher Owned
  , meaning = NoFold
  , verify = DeclarationOnly
  , format = Declared
      [AttrDict, OptionalGroup [] (ValueOf (OperandRef 0)) [Lit ":", TypeOf (OfGroup (OperandRef 0))]]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "ends a step of the generating set with what goes at its index"
  }

------------------------------------------------------------------------------
-- A step's movements on buffers
------------------------------------------------------------------------------

-- A step of a generating op on buffers, made by its tiling method right
-- before the lowering, moves what it reads and gives in three ways, each
-- its own op: out of slots that then hold nothing, out with references of
-- its own while the slots keep theirs, and into slots that hold nothing.
-- Each moves what the slots under its indices hold: an element under as
-- many indices as the buffer has dimensions, else the cell after them, a
-- fresh buffer of the identity layout. They exist only past counting,
-- whose decisions they keep: no count is placed for them.

movementInterfaces : List InterfaceUse
movementInterfaces = [Implements flowInterface ["getFlowEdges"]]

movementFormat : Format 2 1 0 0
movementFormat = Declared
  [ ValueOf (OperandRef 0), Lit "[", ValueOf (OperandRef 1), Lit "]", AttrDict
  , Lit ":", TypeOf (OfGroup (OperandRef 0)), Lit "->", TypeOf (OfGroup (ResultRef 0)) ]

||| `idr.array.take`: what the slots hold, moved out with their references;
||| they hold nothing to release until a value is placed back. A fold's
||| accumulator.
export
arrayTakeOp : Op 2 1 0 0
arrayTakeOp = MkOp
  { home = InIdr
  , mnemonic = "array.take"
  , ins = [single "buffer" (SatisfiesType valueBuffer), variadic "indices" (UpstreamType IndexC)]
  , outs = [result "value" (UpstreamType AnyTypeC)]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = movementInterfaces
  , effects = Executes [OnValues Read Contents (Operands 0), OnValues Write Contents (Operands 0)]
                [] Covered Untouched
  , speculation = NotSpeculatable
  , stages = between Owned Owned
  , meaning = NoFold
  , verify = VerifiesOp
  , format = movementFormat
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "what slots of a buffer hold, moved out, the slots left holding nothing"
  }

||| `idr.array.copy`: what the slots hold, with references of its own; the
||| slots keep theirs. A scan's accumulator, read from its input or from the
||| step before, which both keep it.
export
arrayCopyOp : Op 2 1 0 0
arrayCopyOp = MkOp
  { home = InIdr
  , mnemonic = "array.copy"
  , ins = [single "buffer" (SatisfiesType valueBuffer), variadic "indices" (UpstreamType IndexC)]
  , outs = [result "value" (UpstreamType AnyTypeC)]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = movementInterfaces
  , effects = Executes [OnValues Read Contents (Operands 0), OnValues Write Count (Operands 0)]
                [] Covered Untouched
  , speculation = NotSpeculatable
  , stages = between Owned Owned
  , meaning = NoFold
  , verify = VerifiesOp
  , format = movementFormat
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "what slots of a buffer hold, with references of its own"
  }

||| `idr.array.place`: a value moved into slots that hold nothing to
||| release: an element into its slot, or a cell's elements into the slots
||| under the indices, each with a reference of its own, the cell's own
||| reference given up. What a tabulation and a scan write, and a fold's
||| next accumulator.
export
arrayPlaceOp : Op 3 0 0 0
arrayPlaceOp = MkOp
  { home = InIdr
  , mnemonic = "array.place"
  , ins = [ single "value" (UpstreamType AnyTypeC), single "buffer" (SatisfiesType valueBuffer)
          , variadic "indices" (UpstreamType IndexC) ]
  , outs = []
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = movementInterfaces
  , effects = Executes [OnValues Write Contents (Operands 1)] [Consumes 0] Covered Untouched
  , speculation = NotSpeculatable
  , stages = between Owned Owned
  , meaning = NoFold
  , verify = VerifiesOp
  , format = Declared
      [ ValueOf (OperandRef 0), Lit ",", ValueOf (OperandRef 1), Lit "[", ValueOf (OperandRef 2)
      , Lit "]", AttrDict, Lit ":", TypeOf (OfGroup (OperandRef 0)), Lit ","
      , TypeOf (OfGroup (OperandRef 1)) ]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "a value moved into slots of a buffer that hold nothing"
  }

------------------------------------------------------------------------------
-- The area's part
------------------------------------------------------------------------------

export
generatingOps : List AnyOp
generatingOps =
  [ SomeOp tabulateOp, SomeOp foldLastOp, SomeOp scanLastOp, SomeOp arrayYieldOp
  , SomeOp arrayTakeOp, SomeOp arrayCopyOp, SomeOp arrayPlaceOp ]

export
generatingInterfacesDeclared : List InterfaceDef
generatingInterfacesDeclared = [yieldTargetsInterface, lastAxisFoldInterface]
