// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The ops of the idr dialect on arrays: the generating set of the array
// language (a new array from its indices, the folds and scans along the
// last axis, a new array made in the world's order, a transpose), each a
// region from indices to an element, kept as such until idr-structure-loops
// lowers it once, by what its region does; the arrays a world orders; an
// element moved out of a value array's buffer and back; the extent of an
// array to be made; and the tie of an array's dimensions to the sizes Idris
// proved them equal to. An array the program computes as a value is a
// builtin tensor, and a read or a slice of one is upstream's, as are the
// reads and writes of its buffer but that move.

#ifndef IDR_ARRAY_OPS
#define IDR_ARRAY_OPS

include "idr/IR/IdrAttrs.td"
include "idr/IR/IdrInterfaces.td"
include "idr/IR/IdrBigOps.td"
include "idr/IR/IdrFlow.td"
include "mlir/Interfaces/ControlFlowInterfaces.td"
include "mlir/Interfaces/InferTypeOpInterface.td"
include "mlir/Interfaces/LoopLikeInterface.td"
include "mlir/Interfaces/ValueBoundsOpInterface.td"
include "mlir/Interfaces/ViewLikeInterface.td"

//===----------------------------------------------------------------------===//
// The generating set
//===----------------------------------------------------------------------===//

// How an op of the generating set visits one dimension of its iteration
// domain. Parallel: each index once, in no order the program can observe
// unless its region does more than compute and crash. Ordered: each index
// once, in increasing order, each step reading what the step before gave.
// The op's whole domain is visited in row-major order (the last dimension
// fastest) wherever an order is observed, so a region with an effect beyond
// a crash runs its effects in that order.
def Idr_Iteration : I32EnumAttr<"Iteration", "how a dimension of an array op is visited", [
    I32EnumAttrCase<"Parallel", 0, "parallel">, I32EnumAttrCase<"Ordered", 1, "ordered">]> {
  let cppNamespace = "::idr";
  let genSpecializedAttr = 0;
}

// An op of the generating set. Its one region is a block whose leading
// arguments are the indices of its iteration domain, `index`, outermost
// first, and which ends in idr.array.yield, or in ub.unreachable when it
// never returns. The region runs once per index of the domain, never when
// the domain is empty, and what it does is the op's: its effects are its
// region's. Each op answers what GeneratingOpInterface asks: the visit of
// each dimension of its domain, from its kind alone, and each dimension's
// size. What the region yields moves into the elements of the array it
// makes or folds, and an accumulator comes out of them (the flow interface,
// lib/IR/OpsArrays.cpp).
class Idr_GeneratingOp<string mnemonic, list<Trait> traits = []>
    : Idr_Op<mnemonic, !listconcat(traits, [RecursiveMemoryEffects, RecursivelySpeculatable,
        SingleBlock, Idr_GeneratingOpInterface,
        DeclareOpInterfaceMethods<Idr_FlowOpInterface>,
        DeclareOpInterfaceMethods<ReifyRankedShapedTypeOpInterface,
                                  ["reifyResultShapes", "reifyDimOfResult"]>,
        DeclareOpInterfaceMethods<ValueBoundsOpInterface,
                                  ["populateBoundsForIndexValue",
                                   "populateBoundsForShapedValueDim"]>])> {
  let regions = (region SizedRegion<1>:$region);
  let hasVerifier = 1;
  let hasRegionVerifier = 1;
  // What GeneratingOpInterface asks, each op answering for itself.
  code generatingDeclarations = [{
    // How each dimension of the domain is visited, outermost first.
    ::llvm::SmallVector<::idr::Iteration> getIterations();
    // The size of dimension `dim` of the domain, made with `b` where it is
    // read from an operand's shape; and the same size as value bounds names
    // it, making nothing.
    ::mlir::OpFoldResult getExtent(::mlir::OpBuilder &b, unsigned dim);
    ::mlir::ValueBoundsConstraintSet::Variable getExtentBound(unsigned dim);
    // The indices the region binds, one per dimension of the domain.
    ::mlir::Block::BlockArgListType getIndices() {
      return getBody()->getArguments().take_front(getRank());
    }
  }];
}

// A new array of each result's type: each element (or cell, a trailing
// subarray) at an index of the domain, the leading dimensions shared by
// every result, is what the region yields there, the j-th value for the
// j-th result. The sizes are the domain's dynamic dimensions; a cell's
// dimensions are the cells' own, which Idris made one shape. An array of
// records, after idr-columns, is several results, one per field.
//
//   %t = idr.tabulate [%n] {
//   ^bb0(%i: index):
//     %x = arith.index_cast %i : index to i64
//     idr.array.yield %x : i64
//   } : tensor<?xi64>
// That a variadic is not empty is a predicate on the op, which ODS checks
// with the op's other invariants.
def Idr_MakesAnArray : PredOpTrait<"it makes an array", CPred<"!$arrays.empty()">>;
def Idr_FoldsAnAccumulator : PredOpTrait<"it folds an accumulator", CPred<"!$inits.empty()">>;

def Idr_TabulateOp : Idr_GeneratingOp<"tabulate", [HasParallelRegion, Idr_MakesAnArray,
    DeclareOpInterfaceMethods<RegionBranchOpInterface>]> {
  let summary = "a new array, each element what the region gives at its index";
  let arguments = (ins Variadic<Index>:$sizes);
  let results = (outs Variadic<AnyRankedTensor>:$arrays);
  let assemblyFormat = "`[` $sizes `]` $region attr-dict `:` type($arrays)";
  let extraClassDeclaration = generatingDeclarations # [{
    unsigned getRank() { return getBody()->getNumArguments(); }
    ::mlir::ValueRange getHeldArrays() { return getArrays(); }
    ::mlir::ValueRange getYieldTargets() { return getArrays(); }
    // What the region yields for each array: its element, or its cell.
    ::llvm::SmallVector<::mlir::Type> getCellTypes();
  }];
}

// The tabulation in the world's order: the region binds the indices and
// the world before it, and yields each element, then the world after it,
// once per index in row-major order. The results are the arrays and the
// last world; the world goes from the op into the region, from one step to
// the next, and out (RegionBranchOpInterface).
def Idr_TabulateIOOp : Idr_GeneratingOp<"tabulate_io", [Idr_PerformsIO, Idr_MakesAnArray,
    DeclareOpInterfaceMethods<RegionBranchOpInterface,
                              ["getEntrySuccessorOperands", "getSuccessorInputs"]>]> {
  let summary = "a new array made in the world's order, each element an action's result";
  let arguments = (ins Variadic<Index>:$sizes, Idr_WorldType:$world);
  let results = (outs Variadic<AnyRankedTensor>:$arrays, Idr_WorldType:$next);
  let assemblyFormat = "`[` $sizes `]` `,` $world $region attr-dict `:` type($arrays)";
  let hasCanonicalizer = 1;
  let extraClassDeclaration = generatingDeclarations # [{
    unsigned getRank() { return getBody()->getNumArguments() - 1; }
    ::mlir::ValueRange getHeldArrays() { return getArrays(); }
    ::mlir::ValueRange getYieldTargets() { return getArrays(); }
    // What the region yields for each array, before the world.
    ::llvm::SmallVector<::mlir::Type> getCellTypes();
    ::mlir::BlockArgument getWorldArgument() { return getBody()->getArguments().back(); }
  }];
}

// For each index of the frame, the left fold along the last dimension of
// the domain, `length` long, from that index's element (or cell) of each
// init: the region binds the frame's indices, the fold's index and the
// accumulators, and yields the next accumulators. The frame is each init's
// leading dimensions; the results have the inits' types. A rank-0 init is
// an accumulator of no frame.
def Idr_FoldLastOp : Idr_GeneratingOp<"fold_last", [HasParallelRegion, Idr_FoldsAnAccumulator,
    Idr_LastAxisFoldOpInterface, DeclareOpInterfaceMethods<RegionBranchOpInterface>]> {
  let summary = "for each index of a frame, a left fold along one more dimension";
  let arguments = (ins Variadic<AnyRankedTensor>:$inits, Index:$length);
  let results = (outs Variadic<AnyRankedTensor>:$results);
  let assemblyFormat = [{
    $inits `[` $length `]` $region attr-dict `:` type($inits) `->` type($results)
  }];
  let extraClassDeclaration = generatingDeclarations # [{
    unsigned getRank() {
      return getBody()->getNumArguments() - static_cast<unsigned>(getInits().size());
    }
    unsigned getFrameRank() { return getRank() - 1; }
    ::mlir::ValueRange getHeldArrays() { return getInits(); }
    ::mlir::ValueRange getYieldTargets() { return getResults(); }
    ::mlir::Block::BlockArgListType getAccumulators() {
      return getBody()->getArguments().drop_front(getRank());
    }
  }];
}

// The fold of idr.fold_last with every accumulator kept: each result's
// element (or cell) at a frame index and a step is the accumulator after
// that step. The result's dimensions are the frame's, then `length`, then
// the init's cell's.
def Idr_ScanLastOp : Idr_GeneratingOp<"scan_last", [HasParallelRegion, Idr_FoldsAnAccumulator,
    Idr_LastAxisFoldOpInterface, DeclareOpInterfaceMethods<RegionBranchOpInterface>]> {
  let summary = "for each index of a frame, every accumulator of a left fold";
  let arguments = (ins Variadic<AnyRankedTensor>:$inits, Index:$length);
  let results = (outs Variadic<AnyRankedTensor>:$results);
  let assemblyFormat = [{
    $inits `[` $length `]` $region attr-dict `:` type($inits) `->` type($results)
  }];
  let extraClassDeclaration = generatingDeclarations # [{
    unsigned getRank() {
      return getBody()->getNumArguments() - static_cast<unsigned>(getInits().size());
    }
    unsigned getFrameRank() { return getRank() - 1; }
    ::mlir::ValueRange getHeldArrays() { return getInits(); }
    ::mlir::ValueRange getYieldTargets() { return getResults(); }
    ::mlir::Block::BlockArgListType getAccumulators() {
      return getBody()->getArguments().drop_front(getRank());
    }
  }];
}

// The array whose dimension `d` is the input's dimension `permutation[d]`,
// and whose element at an index is the input's at the index permuted: a
// whole array moved, no element made.
def Idr_TransposeOp : Idr_Op<"transpose", [Pure,
    DeclareOpInterfaceMethods<Idr_FlowOpInterface>,
    DeclareOpInterfaceMethods<ReifyRankedShapedTypeOpInterface, ["reifyResultShapes"]>,
    DeclareOpInterfaceMethods<ValueBoundsOpInterface, ["populateBoundsForShapedValueDim"]>]> {
  let summary = "an array with its dimensions permuted";
  let arguments = (ins AnyRankedTensor:$input, DenseI64ArrayAttr:$permutation);
  let results = (outs AnyRankedTensor:$result);
  let assemblyFormat = [{
    $input `permutation` `=` $permutation attr-dict `:` type($input) `->` type($result)
  }];
  let hasVerifier = 1;
  let hasFolder = 1;
}

// The end of a region of an array op or of a memo cell's force: what it
// gives at its index, each value moving on with the reference it holds. Its
// leading values move into the memory its parent holds for them
// (YieldTargetsOpInterface), one each: into an array an element or the
// elements of a cell, into a memo cell its value (its flow edges); the
// values after them go on (the forwarding): of a tabulation in the world's
// order, the world after the step, to the next step and out of the op; of
// an update or a force, the values after the element or the value, out of
// the op as its results. Its parent is an op that holds such memory.
def Idr_ArrayYieldOp : Idr_Op<"array.yield", [Pure, Terminator,
    PredOpTrait<"its parent holds the arrays it yields into", CPred<
        "::llvm::isa_and_nonnull<::idr::YieldTargetsOpInterface>($_op.getParentOp())">>,
    DeclareOpInterfaceMethods<Idr_FlowOpInterface>,
    DeclareOpInterfaceMethods<RegionBranchTerminatorOpInterface,
                              ["getMutableSuccessorOperands"]>]> {
  let summary = "ends a region of an array op with what it gives at its index";
  let arguments = (ins Variadic<AnyType>:$values);
  let assemblyFormat = "attr-dict ($values^ `:` type($values))?";
}

//===----------------------------------------------------------------------===//
// Arrays a world orders
//===----------------------------------------------------------------------===//

// The memory of an array a world orders: base's IOArray, Buffer and IORef,
// written after they are shared, in the world's order. A value array's
// buffer, which bufferization makes of a tensor, is in the default memory
// space, so no type is both: what the type graph asks of a cell written
// after it exists, and what the lowering asks of an array's layout, the
// type answers.
def Idr_WorldSpaceAttr : AttrDef<Idr_Dialect, "WorldSpace"> {
  let mnemonic = "world";
  let summary = "the memory of an array a world orders";
}

// An array a world orders is a builtin memref of rank 0 or 1, each
// dimension dynamic, in that memory space, over a field type E at no grade:
// the type the memref passes know, so no array type of our own.
// `memref<?xE, #idr.world>` (ArrayData, Buffer) holds as many elements as
// it was made with, `memref<E, #idr.world>` (an IORef's Mut) holds one. The
// ops take one size or one index per dimension, as memref.alloc and
// memref.load do, so an IORef's ops are the array ops at none. Its cell
// holds its elements like a constructor's fields, so the array is a counted
// value, an element moves into it with its reference, and an element read
// takes one of its own (lib/Conversion, runtime idris_rt_array).
def Idr_ArrayType : Type<CPred<"::idr::isArray($_self)">,
                         "an array a world orders, memref<?xE, #idr.world> or "
                         "memref<E, #idr.world> of a field type E",
                         "::mlir::MemRefType">;
// The buffer bufferization makes of a value array, a tensor: a memref in
// the default memory space, which no array a world orders is in.
def Idr_ValueBuffer : Type<And<[AnyMemRef.predicate,
                                CPred<"!::llvm::cast<::mlir::MemRefType>($_self).getMemorySpace()">]>,
                           "a value array's buffer, a memref in the default memory space",
                           "::mlir::MemRefType">;

// The array ops are IO: each takes the world and gives the next, and reads
// or writes the array's cell in that order. Their effects are on the array
// they touch, not on the IO resource: the world operand already orders them
// with every other effect, and an effect on the array lets alias reasoning
// tell two arrays apart. Each op declares its own on the array it makes or
// takes; an access crashes on no index, the index being its guard's to
// check. An element moves in with its reference, which the op takes over,
// and out with one of its own: the flow edges of each op say which
// (lib/IR/OpsArrays.cpp).
class Idr_ArrayOp<string mnemonic, list<Trait> traits = []>
    : Idr_Op<"array." # mnemonic, !listconcat(traits, [Idr_PerformsIO,
        DeclareOpInterfaceMethods<Idr_FlowOpInterface>])>;

// A new array of the given sizes, one per dimension, each element the
// value `fill`, which moves in (one reference, held by each element: the
// fill takes the others). A negative size is an empty dimension; an array
// of rank 0 has no size and one element. Every element holds a value from
// the start, so no read or write of an array a world orders meets an empty
// place, and a write's release of the old element always releases one. The
// array's shape is known from its sizes (ReifyRankedShapedTypeOpInterface),
// so `memref.dim` of it folds, as upstream folds the dimension of a
// `memref.alloc`. It allocates the array and writes its fill.
def Idr_ArrayNewOp : Idr_ArrayOp<"new", [Idr_Primitive,
    DeclareOpInterfaceMethods<ReifyRankedShapedTypeOpInterface, ["reifyResultShapes"]>]> {
  let summary = "a new array of the given sizes, each element `fill`";
  let arguments = (ins Variadic<I64>:$sizes, AnyType:$fill, Idr_WorldType:$world);
  let results = (outs Res<Idr_ArrayValue, "", [MemAlloc, MemWrite]>:$array, Idr_WorldType:$next);
  let assemblyFormat = [{
    ` ` `[` $sizes `]` `,` $fill `,` $world attr-dict `:` type($fill) `->` type($array)
  }];
  let hasVerifier = 1;
  let extraClassDeclaration = [{
    ::mlir::MemRefType getArrayType() {
      return ::llvm::cast<::mlir::MemRefType>(::idr::unrestricted(getArray().getType()));
    }
  }];
}

// An access (get, set, update) reads its index within the array: an
// idr.check.in_bounds of each index against the array guards it
// (Idr_Guarded), the primitive's own meaning of an index outside the
// array; an update is made of a get and a set whose indices were guarded. A proof is the
// guard's absence, and a rewrite that builds a new access on an index
// nothing proved builds the guard too, so no pass can leave an access that
// rests on a fact it did not keep. An array of rank 0 has one element and
// no index, so its accesses have nothing to guard.

// The element at `indices`, one per dimension, which are within the array,
// with a reference of its own: the array keeps its. It reads the array.
def Idr_ArrayGetOp : Idr_ArrayOp<"get", [Idr_Primitive, Idr_TakesReference,
    Idr_Guarded<["indices", "array"], Idr_InBounds, "array index out of bounds">]> {
  let summary = "the element of an array at an index";
  let arguments = (ins Arg<Idr_ArrayValue, "", [MemRead]>:$array, Variadic<I64>:$indices,
                       Idr_WorldType:$world);
  let results = (outs AnyType:$value, Idr_WorldType:$next);
  let assemblyFormat = [{
    $array `[` $indices `]` `,` $world attr-dict `:` type($array) `->` type($value)
  }];
  let hasVerifier = 1;
  let extraClassDeclaration = [{
    ::mlir::MemRefType getArrayType() {
      return ::llvm::cast<::mlir::MemRefType>(::idr::unrestricted(getArray().getType()));
    }
  }];
}

// Writes `value`, which moves in, over the element at `indices`, which are
// within the array; the old element is released. It reads the old element,
// to release it, and writes the new one.
def Idr_ArraySetOp : Idr_ArrayOp<"set", [Idr_Primitive,
    Idr_Guarded<["indices", "array"], Idr_InBounds, "array index out of bounds">]> {
  let summary = "writes an element of an array at an index";
  let arguments = (ins Arg<Idr_ArrayValue, "", [MemRead, MemWrite]>:$array,
                       Variadic<I64>:$indices, AnyType:$value, Idr_WorldType:$world);
  let results = (outs Idr_WorldType:$next);
  let assemblyFormat = [{
    $array `[` $indices `]` `,` $value `,` $world attr-dict `:` type($array) `,` type($value)
  }];
  let hasVerifier = 1;
  let hasCanonicalizer = 1;
  let extraClassDeclaration = [{
    ::mlir::MemRefType getArrayType() {
      return ::llvm::cast<::mlir::MemRefType>(::idr::unrestricted(getArray().getType()));
    }
  }];
}

// The element at `indices` rebuilt in its place, shaped like
// memref.generic_atomic_rmw: the element moves out of the array into the
// region's one argument, with the reference the array held, and the first
// value the region yields moves back in; the values it yields after that
// leave the op as its results, before the world (an exchange gives the old
// element out so). Between the two the element's place is empty, and only
// the region runs there: it binds no world, so it performs no access of an
// array a world orders and cannot see the empty place. A value read only to
// be rebuilt and written back (an IORef's modify, a record's update in
// place) so holds the one reference to its cell while it is rebuilt, and
// counting rebuilds it in that cell. The read and write of the element are
// the op's own effects, on the array; the region's are its own
// (RecursiveMemoryEffects).
def Idr_ArrayUpdateOp : Idr_ArrayOp<"update", [RecursiveMemoryEffects, SingleBlock,
    Idr_UpdateOpInterface, DeclareOpInterfaceMethods<MemoryEffectsOpInterface>,
    DeclareOpInterfaceMethods<RegionBranchOpInterface,
                              ["getSuccessorInputs", "getRegionInvocationBounds"]>]> {
  let summary = "an element of an array rebuilt in its place";
  let arguments = (ins Idr_ArrayValue:$array, Variadic<I64>:$indices, Idr_WorldType:$world);
  let results = (outs Variadic<AnyType>:$outs, Idr_WorldType:$next);
  let regions = (region SizedRegion<1>:$region);
  let assemblyFormat = [{
    $array `[` $indices `]` `,` $world $region attr-dict `:` type($array) (`->` type($outs)^)?
  }];
  let hasVerifier = 1;
  let hasRegionVerifier = 1;
  let extraClassDeclaration = [{
    ::mlir::MemRefType getArrayType() {
      return ::llvm::cast<::mlir::MemRefType>(::idr::unrestricted(getArray().getType()));
    }
    // The element moved out, which the region rebuilds.
    ::mlir::BlockArgument getElement() { return getBody()->getArgument(0); }
    // The array the region's first value moves back into: the operand's
    // range, which outlives the call.
    ::mlir::ValueRange getYieldTargets() { return getODSOperands(0); }
  }];
}

// The same move on the buffer of a value array, which bufferization made of
// a tensor: an element of a memref in the default memory space, at i64
// indices within it, as an array a world orders takes its own, rebuilt in
// its place. No world orders a value array's
// buffer, whose writes are its tensors' in-place decisions, so the op takes
// none and performs no IO. The element moves out into the region's one
// argument with the reference the buffer held, and the first value the
// region yields moves back in over the place it left, which holds nothing
// to release; the values it yields after that are the op's results. A read
// of an element that holds references, whose place the next write to the
// buffer overwrites, is one: a vector's pop reads its last element and
// writes the fill behind it, and the element leaves with the buffer's
// reference, where a read would take one of its own and the write would
// release the buffer's.
def Idr_ElementUpdateOp : Idr_Op<"element.update", [RecursiveMemoryEffects, SingleBlock,
    Idr_UpdateOpInterface,
    DeclareOpInterfaceMethods<MemoryEffectsOpInterface>,
    DeclareOpInterfaceMethods<Idr_FlowOpInterface>,
    DeclareOpInterfaceMethods<RegionBranchOpInterface,
                              ["getSuccessorInputs", "getRegionInvocationBounds"]>]> {
  let summary = "an element of a value array's buffer rebuilt in its place";
  // The buffer is named as an array a world orders is, so that an update's
  // array is one name of both (UpdateOpInterface).
  let arguments = (ins Idr_ValueBuffer:$array, Variadic<I64>:$indices);
  let results = (outs Variadic<AnyType>:$outs);
  let regions = (region SizedRegion<1>:$region);
  let assemblyFormat = [{
    $array `[` $indices `]` $region attr-dict `:` type($array) (`->` type($outs)^)?
  }];
  let hasVerifier = 1;
  let hasRegionVerifier = 1;
  let extraClassDeclaration = [{
    ::mlir::MemRefType getArrayType() {
      return ::llvm::cast<::mlir::MemRefType>(::idr::unrestricted(getArrayMutable().get().getType()));
    }
    // The element moved out, which the region rebuilds.
    ::mlir::BlockArgument getElement() { return getBody()->getArgument(0); }
    // The buffer the region's first value moves back into: the operand's
    // range, which outlives the call.
    ::mlir::ValueRange getYieldTargets() { return getODSOperands(0); }
  }];
}

//===----------------------------------------------------------------------===//
// The extent of an array to be made
//===----------------------------------------------------------------------===//

// A natural becomes an index in two places. A coordinate, at its access,
// is below an extent by its type, so its conversion is exact and needs no
// op of its own (idr.big.to_int, then arith.index_castui). An extent, at
// the allocation it sizes, has no such bound: this op is its conversion.
// A small natural is itself; one that is not small is past every
// allocation either target can make, so it is the allocation's failure,
// here, where the extent is made.
def Idr_NatToExtentOp : Idr_Op<"nat.to_extent", [Idr_MayCrash,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  let summary = "a natural as the extent of an array to be made";
  let arguments = (ins Idr_NatRead:$natural);
  let results = (outs Index:$extent);
  let assemblyFormat = "$natural attr-dict `:` type($natural)";
  let hasFolder = 1;
}

//===----------------------------------------------------------------------===//
// Dimensions across calls
//===----------------------------------------------------------------------===//

// An array whose dynamic dimensions are the given sizes, in order: the
// identity, saying what Idris proved of arrays indexed by one size
// variable. Upstream relates a dynamic dimension only through the op that
// made it, and a function's parameter or a call's result has none, so the
// frontend ties them at a function's entry and at a call. Value bounds and
// the folding of a dimension then cross the call. Folding the op away loses
// an optimization, never a meaning: the equality is Idris's and holds
// whether or not the op is there. An array a world orders is never tied:
// its length is its own, read with memref.dim. The result is a view of its
// operand (ViewLikeOpInterface): the same array, which is what it is at run
// time (Idr_NoRuntimeForm).
def Idr_TieShapeOp : Idr_Op<"tie_shape", [Pure, Idr_NoRuntimeForm,
    AllTypesMatch<["value", "result"]>,
    DeclareOpInterfaceMethods<ViewLikeOpInterface>,
    DeclareOpInterfaceMethods<ReifyRankedShapedTypeOpInterface, ["reifyResultShapes"]>,
    DeclareOpInterfaceMethods<ValueBoundsOpInterface, ["populateBoundsForShapedValueDim"]>]> {
  let summary = "an array whose dynamic dimensions are the given sizes";
  let arguments = (ins AnyTypeOf<[AnyRankedTensor, Idr_ValueBuffer]>:$value, Variadic<Index>:$dims);
  let results = (outs AnyTypeOf<[AnyRankedTensor, Idr_ValueBuffer]>:$result);
  let assemblyFormat = "$value `dims` `(` $dims `)` attr-dict `:` type($value)";
  let hasVerifier = 1;
  let hasFolder = 1;
}

#endif // IDR_ARRAY_OPS
