// The ops of the idr dialect on arrays, and the loops over them.

#ifndef IDR_ARRAY_OPS
#define IDR_ARRAY_OPS

include "idr/IR/IdrAttrs.td"
include "idr/IR/IdrInterfaces.td"
include "idr/IR/IdrBigOps.td"
include "idr/IR/IdrIOOps.td"

//===----------------------------------------------------------------------===//
// Arrays
//===----------------------------------------------------------------------===//

// An array is a builtin memref of rank 0 or 1, each dimension dynamic,
// over a field type E at no grade: the type the memref and bufferization
// passes know, so no array type of our own. `memref<?xE>` (ArrayData,
// Buffer) holds as many elements as it was made with, `memref<E>` (an
// IORef's Mut) holds one. The ops take one size or one index per
// dimension, as memref.alloc and memref.load do, so an IORef's ops are the
// array ops at none. Its cell holds its elements like a constructor's
// fields, so the array is a counted value, an element moves into it with
// its reference, and an element read takes one of its own
// (lib/Conversion, runtime idris_rt_array).
def Idr_ArrayType : Type<CPred<"::idr::isArray($_self)">,
                         "an array, memref<?xE> or memref<E> of a field type E",
                         "::mlir::MemRefType">;
// The array ops are IO: each takes the world and gives the next, and
// reads or writes the array's cell in that order. Their effects are their
// own (not Idr_IOOp's, whose runtime call they do not make): the IO
// resource, and an allocation for a new array. An element moves in with its
// reference, which the op takes over.
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
// and is the access's own check. A proof is the guard's absence:
// idr-in-bounds erases the guards it proves, and a rewrite that builds a new
// access on an index nothing proved builds the guard too, so no pass can
// leave an access that rests on a fact it did not keep. An array of rank 0
// has one element and no index, so its accesses have nothing to guard.

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

// The two loops over an array's index space, graded region ops: the body
// runs once per index it covers, in index order, and what its ops perform
// the loop performs (RecursiveMemoryEffects). The body is its own
// successor, as an scf.for body's is, so a pass that asks which regions
// run again sees the loop instead of a list of op names. A fold forwards
// its accumulator along both edges (the init into the body, and into the
// result when the array is empty; the yield back into the body and out as
// the result). A generate forwards nothing: the yielded word is stored in
// the new array, not passed as an SSA value. Their elements are machine
// words (an integer or a float type), which a memref holds and a vector
// lane computes; the frontend emits them only then, and the library's own
// definition compiles as written for any other element. Lowering makes
// each a linalg.generic over the array's memory (lib/Conversion), and a
// generate whose body is a fold one generic of two dimensions.

// The body of a region primitive: one block, whose entry block takes
// `numArguments` arguments, as SizedRegion's `blocks` counts the blocks it
// checks. idris-mlir-tblgen reads `arguments` for the Idris side's
// regionArity.
class Idr_BodyRegion<int numArguments> : Region<
    And<[CPred<"::llvm::hasNItems($_self, 1)">,
         CPred<"$_self.front().getNumArguments() == " # numArguments>]>,
    "region with 1 block of " # numArguments # " arguments"> {
  int blocks = 1;
  int arguments = numArguments;
}

// A new array of `size` elements: element 0 is `fill`, and element `i` from
// 1 on the body at `i` (an i64). So the library's loop makes it: base's
// primitive fills the new array with the function at 0, and the loop
// applies the function at each index from 1 on, never at 0 again. `fill`
// moves in as array.new's does. A negative size, the least included, is an
// empty array, and the array's shape is known from its size, as
// array.new's.
def Idr_ArrayGenerateOp : Idr_ArrayOp<"generate", [Idr_Consumes<"1">, RecursiveMemoryEffects, SingleBlock,
    DeclareOpInterfaceMethods<RegionBranchOpInterface, ["getEntrySuccessorOperands"]>,
    DeclareOpInterfaceMethods<ReifyRankedShapedTypeOpInterface, ["reifyResultShapes"]>]> {
  let summary = "a new array of the body's value at each index";
  let arguments = (ins I64:$size, AnyType:$fill, Idr_WorldType:$world);
  let results = (outs Idr_Rank1ArrayValue:$array, Idr_WorldType:$next);
  let regions = (region Idr_BodyRegion<1>:$body);
  let hasCustomAssemblyFormat = 1;
  let hasVerifier = 1;
  let hasRegionVerifier = 1;
  let extraClassDeclaration = [{
    ::mlir::MemRefType getArrayType() {
      return ::llvm::cast<::mlir::MemRefType>(::idr::unrestricted(getArray().getType()));
    }
  }];
}

// The elements folded from the left in index order: the body takes the
// accumulator (`init` first, which moves in), the element (as array.get
// gives it) and the index (an i64), and yields the next accumulator; the
// result is the last.
def Idr_ArrayFoldOp : Idr_ArrayOp<"fold", [Idr_Consumes<"1">, RecursiveMemoryEffects, SingleBlock,
    DeclareOpInterfaceMethods<RegionBranchOpInterface, [
        "getEntrySuccessorOperands", "getSuccessorInputs", "areTypesCompatible"]>]> {
  let summary = "an array folded from the left in index order";
  let arguments = (ins Idr_Rank1ArrayValue:$array, AnyType:$init, Idr_WorldType:$world);
  let results = (outs AnyType:$result, Idr_WorldType:$next);
  let regions = (region Idr_BodyRegion<3>:$body);
  let hasCustomAssemblyFormat = 1;
  let hasVerifier = 1;
  let hasRegionVerifier = 1;
  let extraClassDeclaration = [{
    ::mlir::MemRefType getArrayType() {
      return ::llvm::cast<::mlir::MemRefType>(::idr::unrestricted(getArray().getType()));
    }
  }];
}

#endif // IDR_ARRAY_OPS
