// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The ops of the idr dialect on arrays a world orders, the extent of an
// array to be made, and the tie of an array's dimensions to the sizes Idris
// proved them equal to. An array the program computes as a value is a
// builtin tensor, which the frontend writes with upstream's tensor and scf
// ops: no op here makes or reads one but the tie.

#ifndef IDR_ARRAY_OPS
#define IDR_ARRAY_OPS

include "idr/IR/IdrAttrs.td"
include "idr/IR/IdrInterfaces.td"
include "idr/IR/IdrBigOps.td"
include "mlir/Interfaces/ValueBoundsOpInterface.td"

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
// The array ops are IO: each takes the world and gives the next, and reads
// or writes the array's cell in that order. Their effects are on the array
// they touch, not on the IO resource: the world operand already orders them
// with every other effect, and an effect on the array lets alias reasoning
// tell two arrays apart. An element moves in with its reference, which the
// op takes over. An element that is a closure or a suspension moves in and
// out through the elements of every array of its type: the flow model of
// these ops is in lib/IR/Flow.cpp, as every op's is.
class Idr_ArrayOp<string mnemonic, list<Trait> traits = []>
    : Idr_Op<"array." # mnemonic, !listconcat(traits, [Idr_PerformsIO, Idr_Primitive,
        DeclareOpInterfaceMethods<MemoryEffectsOpInterface>])>;

// A new array of the given sizes, one per dimension, each element the
// value `fill`, which moves in (one reference, held by each element: the
// fill takes the others). A negative size is an empty dimension; an array
// of rank 0 has no size and one element. The array's shape is known from
// its sizes (ReifyRankedShapedTypeOpInterface), so `memref.dim` of it
// folds, as upstream folds the dimension of a `memref.alloc`.
def Idr_ArrayNewOp : Idr_ArrayOp<"new", [Idr_Consumes<"1">,
    DeclareOpInterfaceMethods<ReifyRankedShapedTypeOpInterface, ["reifyResultShapes"]>]> {
  let summary = "a new array of the given sizes, each element `fill`";
  let arguments = (ins Variadic<I64>:$sizes, AnyType:$fill, Idr_WorldType:$world);
  let results = (outs Idr_ArrayValue:$array, Idr_WorldType:$next);
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

// An access (get, set) reads its index within the array: an
// idr.check.in_bounds of the index against the array's length guards it,
// the primitive's own meaning of an index outside the array. A proof is the
// guard's absence, and a rewrite that builds a new access on an index
// nothing proved builds the guard too, so no pass can leave an access that
// rests on a fact it did not keep. An array of rank 0 has one element and
// no index, so its accesses have nothing to guard.

// The element at `indices`, one per dimension, which are within the array.
// One that `moves` gives the element with the reference the array held,
// takes no reference of its own, and leaves the element's place empty
// until the write its world goes to next, of the same element, fills it
// again. MoveOutBeforeSet claims it only where nothing between the two may
// read the array, so nothing sees the empty place, and the verifier holds
// the two together. A value read only to be rebuilt and written back then
// holds the one reference to its cell while it is rebuilt, and counting
// rebuilds it in that cell.
def Idr_ArrayGetOp : Idr_ArrayOp<"get"> {
  let summary = "the element of an array at an index";
  let arguments = (ins Idr_ArrayValue:$array, Variadic<I64>:$indices, Idr_WorldType:$world,
                       UnitProp:$moves);
  let results = (outs AnyType:$value, Idr_WorldType:$next);
  let assemblyFormat = [{
    $array `[` $indices `]` `,` $world (`moves` $moves^)? attr-dict `:` type($array) `->`
    type($value)
  }];
  let hasVerifier = 1;
  let extraClassDeclaration = [{
    ::mlir::MemRefType getArrayType() {
      return ::llvm::cast<::mlir::MemRefType>(::idr::unrestricted(getArray().getType()));
    }
  }];
}

// Writes `value`, which moves in, over the element at `indices`, which are
// within the array; the old element is released, which releases nothing
// when the read before it moved the element out.
def Idr_ArraySetOp : Idr_ArrayOp<"set", [Idr_Consumes<"2">]> {
  let summary = "writes an element of an array at an index";
  let arguments = (ins Idr_ArrayValue:$array, Variadic<I64>:$indices, AnyType:$value,
                       Idr_WorldType:$world);
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
def Idr_NatToExtentOp : Idr_Op<"nat.to_extent", [Idr_MayCrash<>,
    DeclareOpInterfaceMethods<InferIntRangeInterface, ["inferResultRanges"]>]> {
  let summary = "a natural as the extent of an array to be made";
  let arguments = (ins Idr_NatType:$natural);
  let results = (outs Index:$extent);
  let assemblyFormat = "$natural attr-dict";
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
// its length is its own, read with memref.dim.
def Idr_TieShapeOp : Idr_Op<"tie_shape", [Pure, AllTypesMatch<["value", "result"]>,
    DeclareOpInterfaceMethods<ReifyRankedShapedTypeOpInterface, ["reifyResultShapes"]>,
    DeclareOpInterfaceMethods<ValueBoundsOpInterface, ["populateBoundsForShapedValueDim"]>]> {
  let summary = "an array whose dynamic dimensions are the given sizes";
  let arguments = (ins AnyTypeOf<[AnyRankedTensor, AnyMemRef]>:$value, Variadic<Index>:$dims);
  let results = (outs AnyTypeOf<[AnyRankedTensor, AnyMemRef]>:$result);
  let assemblyFormat = "$value `dims` `(` $dims `)` attr-dict `:` type($value)";
  let hasVerifier = 1;
  let hasFolder = 1;
}

#endif // IDR_ARRAY_OPS
