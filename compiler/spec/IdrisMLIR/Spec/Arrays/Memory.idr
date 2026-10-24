-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The arrays that are memory, and the values that cross into it: mutable
||| memory (base's IOArray, Buffer and IORef) with its reads, writes and
||| updates in place; the read of a value array that gives the array back;
||| the opening of the buffer a field holds as the array it is; the copy
||| that is the first write of a buffer allocated for it; the extent of an
||| array to be made; and the tie of an array's dynamic dimensions to the
||| sizes Idris proved them equal to.
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
import IdrisMLIR.Spec.Families.Ops
import IdrisMLIR.Spec.Tail.Declarations

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
  , stages = between Higher Owned
  , params = []
  , syntax = Declarative []
  , interfaces = []
  , verifier = AnyParameters
  , bytecode = Derived
  , members = []
  , doc = brief "the memory space of memory written while it is shared"
  }

||| An access of mutable memory reads its index within the array: an
||| idr.check.in_bounds of each index, at the `index` the access takes,
||| against the array guards it, the primitive's own meaning of an index
||| outside the array, since base's arrays are indexed by an `Int` no type
||| bounds. An IORef's access takes no index, and is checked by nothing. A
||| read of a value array is indexed by a `Fin` per axis, which proves it in
||| bounds, so its records carry no guard.
inBounds : {0 i : Nat} -> (indices, arr : Fin i) -> Guard (Fin i)
inBounds indices arr = MkGuard InBounds [indices, arr] IndexOutOfBounds

||| `idr.array.new`: a new array of the given sizes, one per dimension,
||| each element the fill, which moves in, a reference per element (an
||| array of rank 0 has one element). Every element holds a value from the
||| start, so no access meets an empty place. Its shape is its sizes.
public export
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
public export
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
public export
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
||| Between the two the place holds nothing, so the region reads and writes
||| neither the contents nor a state above them (its verifier, from its
||| effects), where any access that could see the empty place falls;
||| counting's own work there (a cell filled, beneath the contents, and what
||| it frees or allocates on the heap) passes.
public export
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
public export
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
||| stands, and no reordering of pure values can put the write first. Both
||| types are inferred: the element's is the array's element type exactly
||| as the array holds it, whose grade is the one the value has, so no
||| writer states it and no verifier compares it.
public export
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
  , typing = InferredTypes [ElementTypeOf 0, OperandType 0]
  }

||| `idr.array.extent`: the extent of a value array along one axis, as a
||| natural, and the array given back as it was, a new value of it, as
||| Idris's type of a linear array's shape says: whatever writes the array
||| next takes the value given back, so the shape is read before the write
||| by data, as an element is. It reads no element.
public export
arrayExtentOp : Op 1 2 1 0
arrayExtentOp = MkOp
  { home = InIdr
  , mnemonic = "array.extent"
  , ins = [single "array" (UpstreamType AnyRankedTensorC)]
  , outs = [result "extent" natValue, result "after" (UpstreamType AnyRankedTensorC)]
  , attrs = [attr "axis" (UpstreamAttr I64AttrC)]
  , regions = []
  , traits = []
  , interfaces = [Implements flowInterface ["getFlowEdges"]]
  , effects = noEffects
  , speculation = AlwaysSpeculatable
  , stages = between Higher First
  , meaning = NoFold
  , verify = VerifiesOp
  , format = Declared
      [ ValueOf (OperandRef 0), Lit "[", ValueOf (AttrRef 0), Lit "]", AttrDict
      , Lit ":", TypeOf (OfGroup (OperandRef 0)), Lit "->", TypeOf (OfGroup (ResultRef 0)), Lit ","
      , TypeOf (OfGroup (ResultRef 1)) ]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "the extent of a value array along an axis, and the array given back"
  }

------------------------------------------------------------------------------
-- A field's buffer opened as an array
------------------------------------------------------------------------------

||| `idr.array.open`: the buffer field `index` of a value refined to one
||| constructor holds, opened as the array it is, the only array of that
||| buffer while it lives: a field holds an array as its buffer from the
||| frontend on, and a match reads one through this op, which takes the
||| value, so what the value claims of its sharing reaches the op that
||| opens the array. The array may be written in place where the value
||| claims its own cells unshared, a claim that covers the storage of a
||| buffer one of them holds, never the elements in it; bufferization reads
||| it off the operand's grade, and no fact beside the grade says it. Its
||| type is the buffer's shape and element, inferred, so the array follows
||| its field wherever a pass changes the value's type. The value is only
||| read, the field's reference reaching the array, as a field read reads
||| it (a memo cell's field its state), and the read is total, since the
||| type fixes the constructor, so it may run anywhere its operand is.
||| Bufferization makes it the field's read.
public export
arrayOpenOp : Op 1 1 1 0
arrayOpenOp = MkOp
  { home = InIdr
  , mnemonic = "array.open"
  , ins = [single "value" (SatisfiesType refinedValue)]
  , outs = [result "array" (UpstreamType AnyRankedTensorC)]
  , attrs = [attr "index" (UpstreamAttr I64AttrC)]
  , regions = []
  , traits = []
  , interfaces = [InfersTypes InferredOnly, Implements flowInterface ["getFlowEdges"]]
  , effects = Executes [] [ReadsMemo 0] Covered Untouched
  , speculation = AlwaysSpeculatable
  , stages = between Higher First
  , meaning = NoFold
  , verify = DeclarationOnly
  , format = Declared
      [ ValueOf (OperandRef 0), Lit "[", ValueOf (AttrRef 0), Lit "]", AttrDict
      , Lit ":", TypeOf (OfGroup (OperandRef 0)), Lit "->", TypeOf (OfGroup (ResultRef 0)) ]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "the array a field of a value holds as its buffer, opened"
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
public export
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
public export
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
  , typing = InferredTypes [FixedType BuiltIndex]
  }

||| `idr.array.tie_shape`: an array whose dimensions at the axes it names
||| are the given sizes, one for each, the axes increasing: the same array,
||| saying what Idris proved of arrays indexed by one size inside a
||| function, where MLIR's tensor type has no symbolic dimension. It names
||| the axes something states (a size the program holds, the natural an
||| array was made of, a constant its type fixes) and no other: an axis
||| nothing states stays untied, never read off the array, since a read of
||| a call's result would follow the call and take it out of the tail.
||| Folding it away loses an optimization, never a meaning. Its result's
||| type is its operand's: an array's words are its cell and one word per
||| dynamic size, so a tie that changed the type would re-pack them as a
||| cast does, and a call whose result it ties would no longer be the tail;
||| with one type it gives the array on untouched. Its inference is hand
||| C++ because it is partial: it gives that type only where each axis it
||| names is a dynamic dimension of the operand, with one size each. So a
||| re-inference that makes a tied axis static (a copy's input made static)
||| is refused at the tie, which keeps its type and reads its operand cast
||| back, and the interface's verifier, which runs the inference, is the
||| op's whole check beside its axes' own constraint.
public export
tieShapeOp : Op 2 1 1 0
tieShapeOp = MkOp
  { home = InIdr
  , mnemonic = "array.tie_shape"
  , ins = [single "value" array, variadic "dims" (UpstreamType IndexC)]
  , outs = [result "result" array]
  , attrs = [attr "axes" (Confined (UpstreamAttr DenseI32ArrayAttrC) (NonNegativeArray ::: [StrictlySortedArray]))]
  , regions = []
  , traits = []
  , interfaces =
      [ Declares ViewLike ["getViewSource"]
      , Declares ReifyRankedShapedType ["reifyResultShapes"]
      , Declares ValueBounds ["populateBoundsForShapedValueDim"]
      , Implements carriesOnInterface ["getCarry", "getCarriedType"]
      , InfersTypes InferredOnly ]
  , effects = noEffects
  , speculation = AlwaysSpeculatable
  , stages = between Higher Owned
  , meaning = HandFolder
  , verify = DeclarationOnly
  , format = Declared
      [ ValueOf (OperandRef 0), Lit "axes", ValueOf (AttrRef 0), Lit "dims", Lit "(", ValueOf (OperandRef 1), Lit ")"
      , AttrDict, Lit ":", TypeOf (OfGroup (OperandRef 0)), Lit "->", TypeOf (OfGroup (ResultRef 0)) ]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = [structuralMeaning "::idr::ArrayTieShapeOp"]
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "an array whose dimensions at the axes it names are the given sizes"
  }

------------------------------------------------------------------------------
-- The skeleton rules
------------------------------------------------------------------------------

||| The arrays' header, which declares the rules on mutable memory.
arraysHeader : Path
arraysHeader = "idr" ::: ["IR", "Arrays.h"]

||| The rules on two accesses of one element of mutable memory, each the
||| two made one. Accesses of mutable memory are ordered by their effects on
||| its contents, so each rule is a skeleton rule, hand C++ declared in the
||| arrays' header, and each moves nothing past another access of the
||| array: it reads the order the effects give and only removes an access.
|||
||| A read of an element whose next access to memory of its array is a
||| write of the same element is that element's update (`MoveOut`, rooted
||| at the write): the element moves out of its place with the reference
||| the place held, the ops between that rebuild it from it run in the
||| update's region, and the value written moves back in. A value read only
||| to be rebuilt and written back (an IORef's modify, a state record's
||| update) then holds the one reference to its cell while it is rebuilt,
||| and counting rebuilds it in that cell.
|||
||| A read of an element whose last write to memory of its array wrote the
||| same element is the value written (`ForwardWritten`, rooted at the
||| read): reads between change nothing. A write whose last access to
||| memory of its array was a write of the same element overwrites what
||| nothing read, so that write goes (`DeleteOverwritten`, rooted at the
||| later write); a crash between ends the run before anything could read
||| it. The read borrows and the write moves its value in, so each rule
||| holds only while no reference is counted, and neither changes how often
||| a value used once is used.
export
memorySkeleton : List SkeletonRule
memorySkeleton =
  [ MkSkeletonRule "MoveOut" arraysHeader "array.set"
      "a write of the element a read gave, with nothing between touching the array, is its update"
  , MkSkeletonRule "ForwardWritten" arraysHeader "array.get"
      "a read of the element a write wrote, with nothing between changing the array, is the value written"
  , MkSkeletonRule "DeleteOverwritten" arraysHeader "array.set"
      "a write of the element a write wrote, with nothing between touching the array, makes the first write go" ]

------------------------------------------------------------------------------
-- The area's part
------------------------------------------------------------------------------

public export
memoryOps : List AnyOp
memoryOps =
  [ SomeOp arrayNewOp, SomeOp arrayGetOp, SomeOp arraySetOp, SomeOp arrayUpdateOp
  , SomeOp arrayUpdateYieldOp, SomeOp arrayReadOp, SomeOp arrayExtentOp, SomeOp arrayOpenOp
  , SomeOp arrayPlaceCopyOp
  , SomeOp natToExtentOp
  , SomeOp tieShapeOp ]
