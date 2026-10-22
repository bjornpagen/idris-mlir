-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The arrays that are memory, and the values that cross into it: mutable
||| memory (base's IOArray, Buffer and IORef) with its reads, writes and
||| updates in place; the read of a value array that gives the array back;
||| the copy that is the first write of a buffer allocated for it; the
||| extent of an array to be made; and the tie of an array's dynamic
||| dimensions to the sizes Idris proved them equal to.
|||
||| Mutable memory is a builtin memref in the memory space `#idr.mutable`,
||| written after it is shared, which no value array's buffer is in: what
||| One-Shot writes in place it proved nothing else reads, while mutable
||| memory is written where the program says. Every access takes one
||| `index` per dimension, as upstream's memref ops do. Its order is its
||| effects', on its contents, with no world: a read borrows the element (a
||| reference a reader keeps is counting's to take), a write releases what
||| it replaces.
module IdrisMLIR.Spec.Arrays.Memory

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Effects.Declaration
import IdrisMLIR.Spec.Control.Flow
import IdrisMLIR.Spec.Runtime.Endings
import IdrisMLIR.Spec.Ops.Shapes
import IdrisMLIR.Spec.Arrays.Generating

import Data.Fin
import Data.List1
import Data.Vect

%default total

------------------------------------------------------------------------------
-- Mutable memory
------------------------------------------------------------------------------

||| `#idr.mutable`: the memory space of memory written while shared.
export
mutableAttr : AttrDef 0
mutableAttr = MkAttrDef
  { mnemonic = "mutable"
  , params = []
  , syntax = Declarative []
  , typed = Untyped
  , interfaces = []
  , verifier = AnyParameters
  , bytecode = Derived
  , members = []
  , doc = brief "the memory space of memory written while it is shared"
  }

||| An array of mutable memory: `memref<?xE, #idr.mutable>` or `memref<E,
||| #idr.mutable>` (an IORef) of a field type E, at any grade. Its C++ is
||| the grade's header's (`isArray`).
export
mutableArray : Predicate
mutableArray = MkPredicate "isArray" OnType
  (brief "an array of mutable memory, at any grade")

||| What an update rebuilds an element of: mutable memory, or a value
||| array's buffer, whose element a read and a write of one place move.
updatable : TypeC
updatable = AnyOfTypes (SatisfiesType mutableArray ::: [SatisfiesType valueBuffer])
  "an array of mutable memory or a value array's buffer"

||| An access reads its index within the array: an idr.check.in_bounds of
||| each index against the array guards it, the primitive's own meaning of
||| an index outside the array.
inBounds : {0 i : Nat} -> (indices, arr : Fin i) -> Guard (Fin i)
inBounds indices arr = MkGuard "check.in_bounds" (indices ::: [arr]) (caseRef causeClosed IndexOutOfBounds)

||| `idr.array.new`: a new array of the given sizes, one per dimension,
||| each element the fill, which moves in, a reference per element (an
||| array of rank 0 has one element). Every element holds a value from the
||| start, so no access meets an empty place. Its shape is its sizes.
export
arrayNewOp : Op 2 1 0 0
arrayNewOp = MkOp
  { home = InIdr
  , mnemonic = "array.new"
  , ins = [variadic "sizes" (UpstreamType IndexC), single "fill" (UpstreamType AnyTypeC)]
  , outs = [result "array" (SatisfiesType mutableArray)]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces =
      [ Declares ReifyRankedShapedType ["reifyResultShapes"]
      , Implements flowInterface ["getFlowEdges"] ]
  , effects = Executes [OnValues Allocate Heap (Results 0), OnValues Write Count (Operands 1)]
                [Consumes 1] Covered Untouched
  , speculation = NotSpeculatable
  , stages = between Higher Owned
  , meaning = NoFold
  , verify = VerifiesOp
  , format = Declared
      [ Lit "[", ValueOf (OperandRef 0), Lit "]", Lit ",", ValueOf (OperandRef 1), AttrDict
      , Lit ":", TypeOf (OfGroup (OperandRef 1)), Lit "->", TypeOf (OfGroup (ResultRef 0)) ]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "a new array of mutable memory of the given sizes, each element the fill"
  }

||| `idr.array.get`: the element at the indices, borrowed: the array keeps
||| its reference, and a reader that keeps the element takes one through
||| counting. It reads the array's contents and nothing else, so two reads
||| of one element are one and an unused read goes.
export
arrayGetOp : Op 2 1 0 0
arrayGetOp = MkOp
  { home = InIdr
  , mnemonic = "array.get"
  , ins = [single "array" (SatisfiesType mutableArray), variadic "indices" (UpstreamType IndexC)]
  , outs = [result "value" (UpstreamType AnyTypeC)]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = [Implements flowInterface ["getFlowEdges"]]
  , effects = Executes [OnValues Read Contents (Operands 0)] [] Covered Untouched
  , speculation = NotSpeculatable
  , stages = between Higher Owned
  , meaning = NoFold
  , verify = VerifiesOp
  , format = Declared
      [ ValueOf (OperandRef 0), Lit "[", ValueOf (OperandRef 1), Lit "]", AttrDict
      , Lit ":", TypeOf (OfGroup (OperandRef 0)), Lit "->", TypeOf (OfGroup (ResultRef 0)) ]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = [inBounds 1 0]
  , specializations = []
  , laws = []
  , doc = brief "the element of an array of mutable memory at an index, borrowed"
  }

||| `idr.array.set`: the value, which moves in, written over the element at
||| the indices, which is released.
export
arraySetOp : Op 3 0 0 0
arraySetOp = MkOp
  { home = InIdr
  , mnemonic = "array.set"
  , ins = [ single "array" (SatisfiesType mutableArray), variadic "indices" (UpstreamType IndexC)
          , single "value" (UpstreamType AnyTypeC) ]
  , outs = []
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = [Implements flowInterface ["getFlowEdges"]]
  , effects = Executes [ OnValues Read Contents (Operands 0), OnValues Write Contents (Operands 0)
                       , OnValues Write Count (Operands 0), OnValues Free Heap (Operands 0) ]
                [Consumes 2] Covered Untouched
  , speculation = NotSpeculatable
  , stages = between Higher Owned
  , meaning = NoFold
  , verify = VerifiesOp
  , format = Declared
      [ ValueOf (OperandRef 0), Lit "[", ValueOf (OperandRef 1), Lit "]", Lit ","
      , ValueOf (OperandRef 2), AttrDict, Lit ":", TypeOf (OfGroup (OperandRef 0)), Lit ","
      , TypeOf (OfGroup (OperandRef 2)) ]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = [inBounds 1 0]
  , specializations = []
  , laws = []
  , doc = brief "writes an element of an array of mutable memory, releasing the one it replaces"
  }

||| `idr.array.update`: the element at the indices rebuilt in its place,
||| shaped like `memref.generic_atomic_rmw`, in mutable memory or in a
||| value array's buffer alike: the element moves out into the region's one
||| argument with the reference its place held, and the first value the
||| region gives moves back in; the values after it are the op's results.
||| Between the two the place holds nothing, so the region touches no
||| memory written in place (its verifier, from its effects): no access it
||| makes can see the empty place.
export
arrayUpdateOp : Op 2 1 0 1
arrayUpdateOp = MkOp
  { home = InIdr
  , mnemonic = "array.update"
  , ins = [single "array" updatable, variadic "indices" (UpstreamType IndexC)]
  , outs = [results "outs" (UpstreamType AnyTypeC)]
  , attrs = []
  , regions = [sized "region" 1]
  , traits = [SingleBlock]
  , interfaces =
      [ Declares RegionBranch
          ["getSuccessorRegions", "getSuccessorInputs", "getRegionInvocationBounds"]
      , Implements flowInterface ["getFlowEdges"]
      , Implements yieldTargetsInterface ["getYieldTargets"] ]
  , effects = Executes [OnValues Read Contents (Operands 0), OnValues Write Contents (Operands 0)]
                [] Recursive Untouched
  , speculation = NotSpeculatable
  , stages = between Higher Owned
  , meaning = NoFold
  , verify = VerifiesOpAndRegions
  , format = Declared
      [ ValueOf (OperandRef 0), Lit "[", ValueOf (OperandRef 1), Lit "]", ValueOf (RegionRef 0)
      , AttrDict, Lit ":", TypeOf (OfGroup (OperandRef 0))
      , OptionalGroup [Lit "->"] (TypeOf (OfGroup (ResultRef 0))) [] ]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "an element of an array rebuilt in its place"
  }

||| `idr.array.update_yield`: the end of an update's region: the rebuilt
||| element, which moves into memory, its place, and the update's results,
||| which move out of the region as a yield's values do.
export
arrayUpdateYieldOp : Op 2 0 0 0
arrayUpdateYieldOp = MkOp
  { home = InIdr
  , mnemonic = "array.update_yield"
  , ins = [single "element" (UpstreamType AnyTypeC), variadic "outs" (UpstreamType AnyTypeC)]
  , outs = []
  , attrs = []
  , regions = []
  , traits = [Terminator, HasParent ("array.update" ::: [])]
  , interfaces =
      [ Declares RegionBranchTerminator ["getMutableSuccessorOperands"]
      , Implements flowInterface ["getFlowEdges"] ]
  , effects = Executes [] [Consumes 0] Covered Untouched
  , speculation = NotSpeculatable
  , stages = between Higher Owned
  , meaning = NoFold
  , verify = DeclarationOnly
  , format = Declared
      [ ValueOf (OperandRef 0), Lit ":", TypeOf (OfGroup (OperandRef 0))
      , OptionalGroup [Lit ","] (ValueOf (OperandRef 1)) [Lit ":", TypeOf (OfGroup (OperandRef 1))]
      , AttrDict ]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "ends an update's region with the rebuilt element and the update's results"
  }

------------------------------------------------------------------------------
-- A value array's read that gives it back
------------------------------------------------------------------------------

||| `idr.array.read`: the element at the indices, and the array given back
||| as it was, a new value of it, as Idris's type of a linear array's read
||| says. Whatever writes the array next takes the value given back, so the
||| read precedes the write by the data it reads, never by where it
||| stands, and no reordering of pure values can put the write first.
export
arrayReadOp : Op 2 2 0 0
arrayReadOp = MkOp
  { home = InIdr
  , mnemonic = "array.read"
  , ins = [single "array" (UpstreamType AnyRankedTensorC), variadic "indices" (UpstreamType IndexC)]
  , outs = [result "value" (UpstreamType AnyTypeC), result "after" (UpstreamType AnyRankedTensorC)]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = [Implements flowInterface ["getFlowEdges"]]
  , effects = noEffects
  , speculation = AlwaysSpeculatable
  , stages = between Higher First
  , meaning = NoFold
  , verify = VerifiesOp
  , format = Declared
      [ ValueOf (OperandRef 0), Lit "[", ValueOf (OperandRef 1), Lit "]", AttrDict
      , Lit ":", TypeOf (OfGroup (OperandRef 0)), Lit "->", TypeOf (OfGroup (ResultRef 0)), Lit ","
      , TypeOf (OfGroup (ResultRef 1)) ]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "the element of a value array at an index, and the array given back"
  }

------------------------------------------------------------------------------
-- A fresh buffer's first write
------------------------------------------------------------------------------

||| `idr.array.place_copy`: a copy of an array placed in a buffer allocated
||| for it, whose slots hold nothing: each element gains a reference of its
||| own and nothing is released. It is the copy bufferization makes before
||| a write it cannot make in place, made where bufferization makes it, the
||| one place that knows nothing has written the buffer; a copy over a
||| buffer that holds elements is `memref.copy`, which releases each element
||| it overwrites. Its destination, the target, is the allocation itself,
||| which the copy writes whole, so from the copy on every slot holds an
||| element, and no write and no release at the buffer's death reads a slot
||| nothing wrote: no allocation is filled for them.
export
arrayPlaceCopyOp : Op 2 0 0 0
arrayPlaceCopyOp = MkOp
  { home = InIdr
  , mnemonic = "array.place_copy"
  , ins = [single "source" (SatisfiesType valueBuffer), single "target" (SatisfiesType valueBuffer)]
  , outs = []
  , attrs = []
  , regions = []
  , traits = []
  , interfaces =
      [ Declares DestinationStyle []
      , Implements flowInterface ["getFlowEdges"] ]
  , effects = Executes [ OnValues Read Contents (Operands 0), OnValues Write Count (Operands 0)
                       , OnValues Write Contents (Operands 1) ]
                [] Covered Untouched
  , speculation = NotSpeculatable
  , stages = between First Owned
  , meaning = NoFold
  , verify = VerifiesOp
  , format = Declared
      [ ValueOf (OperandRef 0), Lit ",", ValueOf (OperandRef 1), AttrDict, Lit ":"
      , TypeOf (OfGroup (OperandRef 0)), Lit "to", TypeOf (OfGroup (OperandRef 1)) ]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = [MkMember OnObject "::mlir::MutableOperandRange" "getDpsInitsMutable" []]
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "a copy of an array placed in a buffer allocated for it, releasing nothing"
  }

------------------------------------------------------------------------------
-- Extents and ties
------------------------------------------------------------------------------

||| `idr.nat.to_extent`: a natural as the extent of an array to be made. A
||| coordinate, at its access, is below an extent by its type, so its
||| conversion is exact and needs no op of its own. An extent has no such
||| bound: a natural past the small range is past every allocation a
||| target can make, which ends the run as out of memory, outside the
||| language and no effect. It moves nowhere it would not have run, so that
||| no run ends that would not have.
export
natToExtentOp : Op 1 1 0 0
natToExtentOp = MkOp
  { home = InIdr
  , mnemonic = "nat.to_extent"
  , ins = [single "natural" (SatisfiesType natReadP)]
  , outs = [result "extent" (UpstreamType IndexC)]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces = [Declares InferIntRange ["inferResultRanges"]]
  , effects = noEffects
  , speculation = NotSpeculatable
  , stages = between Higher Owned
  , meaning = HandFolder
  , verify = DeclarationOnly
  , format = Declared [ValueOf (OperandRef 0), AttrDict, Lit ":", TypeOf (OfGroup (OperandRef 0))]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "a natural as the extent of an array to be made"
  }

||| `idr.array.tie_shape`: an array whose dynamic dimensions are the given
||| sizes, in order: the same array, saying what Idris proved of arrays
||| indexed by one size inside a function, where MLIR's tensor type has no
||| symbolic dimension. Folding it away loses an optimization, never a
||| meaning.
export
tieShapeOp : Op 2 1 0 0
tieShapeOp = MkOp
  { home = InIdr
  , mnemonic = "array.tie_shape"
  , ins = [single "value" array, variadic "dims" (UpstreamType IndexC)]
  , outs = [result "result" array]
  , attrs = []
  , regions = []
  , traits = []
  , interfaces =
      [ Declares ViewLike ["getViewSource"]
      , Declares ReifyRankedShapedType ["reifyResultShapes"]
      , Declares ValueBounds ["populateBoundsForShapedValueDim"] ]
  , effects = noEffects
  , speculation = AlwaysSpeculatable
  , stages = between Higher Owned
  , meaning = HandFolder
  , verify = VerifiesOp
  , format = Declared
      [ ValueOf (OperandRef 0), Lit "dims", Lit "(", ValueOf (OperandRef 1), Lit ")", AttrDict
      , Lit ":", TypeOf (OfGroup (OperandRef 0)), Lit "->", TypeOf (OfGroup (ResultRef 0)) ]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "an array whose dynamic dimensions are the given sizes"
  }

------------------------------------------------------------------------------
-- The skeleton rule
------------------------------------------------------------------------------

||| A read of an element of mutable memory whose next access to memory of
||| its array is a write of the same element is that element's update: the
||| element moves out of its place with the reference the place held, the
||| ops between that rebuild it from it run in the update's region, and the
||| value written moves back in. A value read only to be rebuilt and written
||| back (an IORef's modify, a state record's update) then holds the one
||| reference to its cell while it is rebuilt, and counting rebuilds it in
||| that cell. The read and the write are ordered by their effects, so the
||| rule is a skeleton rule, hand C++ (`::idr::egraph::MoveOut`) declared
||| in the arrays' header, rooted at the write.
export
memorySkeleton : List SkeletonRule
memorySkeleton =
  [ MkSkeletonRule "MoveOut" ("idr" ::: ["IR", "Arrays.h"]) "array.set"
      "a write of the element a read gave, with nothing between touching the array, is its update" ]

------------------------------------------------------------------------------
-- The area's part
------------------------------------------------------------------------------

export
memoryOps : List AnyOp
memoryOps =
  [ SomeOp arrayNewOp, SomeOp arrayGetOp, SomeOp arraySetOp, SomeOp arrayUpdateOp
  , SomeOp arrayUpdateYieldOp, SomeOp arrayReadOp, SomeOp arrayPlaceCopyOp, SomeOp natToExtentOp
  , SomeOp tieShapeOp ]
