-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The generating set of the array language: a tabulation, a fold and a
||| scan along the last axis, each a region from the indices of a domain to
||| what goes at that index, and the yield that ends their regions; and the
||| movements a step of one, or an element's update split around a call,
||| makes in its buffers.
|||
||| Each op is destination-style, as upstream's structured ops are, and
||| means upstream's tensor semantics: on tensors its results are its
||| destinations written, and it computes nothing but values; on buffers it
||| writes its destinations and gives nothing. It stands as one op from the
||| frontend to right before the lowering, through bufferization (upstream's
||| destination model) and counting (its flow and its effects), and is then
||| its loops, made by upstream's `lowerToLoopsUsingSCFForOp` from the three
||| tiling methods it implements, in row-major order, the last axis fastest.
||| An op whose region holds a call on its function's own cycle is made its
||| loops earlier, on the counted program before the frames are made, as
||| recursive join points from the same methods: frames split a join region
||| and no region of this set, so the cycle's depth stays on their stacks.
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

||| An array of mutable memory: `memref<?xE, #idr.mutable>` or `memref<E,
||| #idr.mutable>` (an IORef) of a field type E, at any grade. Its C++ is
||| the grade's header's (`isArray`).
export
mutableArray : Predicate
mutableArray = MkPredicate "isArray" OnType
  (brief "an array of mutable memory, at any grade")

||| What an update rebuilds an element of, and what a take moves an element
||| out of and a put-back moves it back into: mutable memory, or a value
||| array's buffer, whose element a read and a write of one place move.
export
updatable : TypeC
updatable = AnyOfTypes (SatisfiesType mutableArray ::: [SatisfiesType valueBuffer])
  "an array of mutable memory or a value array's buffer"

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
||| accumulators the region binds, and the arrays that keep every step's
||| accumulators: a scan's destinations, one per accumulator; none of a
||| fold's, which keeps only the last step, in its inits.
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
          "the accumulators the region binds"
      , MkMethod PerObject "::mlir::ValueRange" "getKeptSteps" [] EveryImplementer
          "the arrays that keep every step's accumulators, one per accumulator, or none where only the last step is kept, in the inits" ]
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

||| The members a fold and a scan add: the frame's rank, the accumulators
||| the region binds after the indices, and the arrays that keep every
||| step.
foldMembers : List Member
foldMembers =
  [ MkMember OnObject "unsigned" "getFrameRank" []
  , MkMember OnObject "::mlir::Block::BlockArgListType" "getAccumulators" []
  , MkMember OnObject "::mlir::ValueRange" "getKeptSteps" [] ]

------------------------------------------------------------------------------
-- The generating ops
------------------------------------------------------------------------------

||| `idr.array.tabulate`: each destination written at every index of the
||| domain with what the region gives there, the j-th value for the j-th
||| destination; the domain is the destinations' leading dimensions, which
||| they share, and a value is an element, or the cell of the dimensions
||| after them. The region runs once per index, never on an empty domain. A
||| destination of elements that hold references is fresh (the op's
||| verifier): a `tensor.empty` or an `alloc_tensor` of no copy, and on
||| buffers the allocation bufferization made of one. Its slots hold
||| nothing, so placing them releases nothing, and the op, its first
||| writer, places every one before anything reads or releases it.
|||
|||   %t = idr.array.tabulate outs(%e : tensor<?xi64>) {
|||   ^bb0(%i: index):
|||     %x = arith.index_cast %i : index to i64
|||     idr.array.yield %x : i64
|||   } -> tensor<?xi64>
public export
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
public export
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
||| dimensions are the frame's, then `length`, then the input's cell's. A
||| destination of elements that hold references is fresh, as a
||| tabulation's is, which every step's placement fills.
public export
scanLastOp : Op 3 1 0 1
scanLastOp = MkOp
  { home = InIdr
  , mnemonic = "array.scan_last"
  , ins = [single "length" (UpstreamType IndexC), variadic "inits" array, variadic "outs" array]
  , outs = [results "results" (UpstreamType AnyRankedTensorC)]
  , attrs = []
  , regions = [sized "region" 1]
  , traits = [SingleBlock]
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
public export
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

-- A step of a generating op on buffers, made by its tiling method, moves
-- what it reads and gives in four ways, each its own op: out of slots
-- that are left to be put back into, out with references of its own while
-- the slots keep theirs, into slots that hold nothing, and back into the
-- place a take left. Each moves what the slots under its indices hold: an
-- element under as many indices as the buffer has dimensions, else the
-- cell after them, a fresh buffer of the identity layout, at any grade. An
-- element's update whose region calls into its function's own cycle is a
-- take and a put-back around its region's code, so frames can split it,
-- in mutable memory or a value array's buffer alike. They exist only past
-- counting, whose decisions they keep: no count is placed for them.

movementInterfaces : List InterfaceUse
movementInterfaces = [Implements flowInterface ["getFlowEdges"]]

movementFormat : Format 2 1 0 0
movementFormat = Declared
  [ ValueOf (OperandRef 0), Lit "[", ValueOf (OperandRef 1), Lit "]", AttrDict
  , Lit ":", TypeOf (OfGroup (OperandRef 0)), Lit "->", TypeOf (OfGroup (ResultRef 0)) ]

||| `idr.array.take`: what the slots hold, moved out with their references,
||| the place left to be put back into: slots in place hold nothing to
||| release, and a boxed element's place keeps an empty box, its own where
||| a copy of the array shares the one it held. A fold's accumulator, and
||| an element whose update is split around a call.
public export
arrayTakeOp : Op 2 1 0 0
arrayTakeOp = MkOp
  { home = InIdr
  , mnemonic = "array.take"
  , ins = [single "buffer" updatable, variadic "indices" (UpstreamType IndexC)]
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
public export
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
||| reference given up. What a tabulation and a scan write.
public export
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

||| `idr.array.put_back`: a value moved back into the place a take left,
||| as a place moves one into slots that hold nothing, but a boxed element
||| into the box the take left there. A fold's next accumulator, and an
||| element's rebuilt value where its update was split around a call.
public export
arrayPutBackOp : Op 3 0 0 0
arrayPutBackOp = MkOp
  { home = InIdr
  , mnemonic = "array.put_back"
  , ins = [ single "value" (UpstreamType AnyTypeC), single "buffer" updatable
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
  , doc = brief "a value moved back into the place a take left"
  }

------------------------------------------------------------------------------
-- The area's part
------------------------------------------------------------------------------

public export
generatingOps : List AnyOp
generatingOps =
  [ SomeOp tabulateOp, SomeOp foldLastOp, SomeOp scanLastOp, SomeOp arrayYieldOp
  , SomeOp arrayTakeOp, SomeOp arrayCopyOp, SomeOp arrayPlaceOp, SomeOp arrayPutBackOp ]

export
generatingInterfacesDeclared : List InterfaceDef
generatingInterfacesDeclared = [yieldTargetsInterface, lastAxisFoldInterface]
