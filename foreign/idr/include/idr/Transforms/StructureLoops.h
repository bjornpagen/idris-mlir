// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
//===- StructureLoops.h - The array ops as linalg and as loops ------------===//
//
// Two passes on the generating set (idr.array.tabulate, idr.array.fold_last,
// idr.array.scan_last). idr-structure-loops, once every call has its final
// effects and before bufferization, turns each op whose region only
// computes, over arrays of words, into linalg, keeping its parallel
// dimensions parallel; every other op stays as it is, through
// bufferization and counting, as an op on buffers. idr-ordered-loops,
// right before the lowering, makes each op left its loops through
// upstream's lowerToLoopsUsingSCFForOp, from the op's own tiling methods,
// in row-major order. Which form an op takes reads the op alone.
//
//===----------------------------------------------------------------------===//

#ifndef IDR_TRANSFORMS_STRUCTURELOOPS_H
#define IDR_TRANSFORMS_STRUCTURELOOPS_H

#include "idr/IR/Arrays.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/Linalg/IR/Linalg.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/IR/AffineMap.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/DestinationStyleOpInterface.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/SmallVector.h"

namespace idr {
#define GEN_PASS_DECL_IDRSTRUCTURELOOPS
#define GEN_PASS_DECL_IDRORDEREDLOOPS
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

namespace idr::structure {

// What an op of the generating set becomes in idr-structure-loops.
enum class Form {
  // One linalg op over the domain, every dimension parallel: a tabulation.
  Parallel,
  // One linalg op whose last dimension is a reduction: a fold whose every
  // next accumulator is one associative and commutative integer op of its
  // accumulator, which may then be combined in any order.
  Reduction,
  // The ordered dimension as an scf.for around one linalg op over the
  // frame's parallel dimensions: a fold or a scan over words whose
  // combiner is kept in index order, its frame computed on lanes.
  Interchange,
  // The op as it is, made its loops by idr-ordered-loops.
  Ordered,
};

// The form `op`, of the generating set, takes. A call does what its own
// effects say.
Form formOf(mlir::Operation *op);

// A read of an array of words from outside an op, directly in its region,
// at distinct indices of the op's domain, each as large as the dimension
// of the domain it is read at: an input of the linalg op, at `map` from the
// linalg op's dimensions.
struct Read {
  mlir::tensor::ExtractOp op;
  mlir::AffineMap map;
};

// The reads of `op`'s region that become inputs of a linalg op whose
// dimensions are the domain's first `dims`.
llvm::SmallVector<Read> readsOf(mlir::Operation *op, unsigned dims);

// The forms that make linalg, each replacing its op.
void lowerParallel(mlir::RewriterBase &rewriter, ArrayTabulateOp op);
void lowerReduction(mlir::RewriterBase &rewriter, ArrayFoldLastOp op);
template <typename Op>
void lowerInterchange(mlir::RewriterBase &rewriter, Op op);

// The region of `op` moved before the rewriter's insertion point, its
// arguments `args`, the insertion point left after it: what its yield
// gives, values of the types `given`, or, where it ends in a terminator
// that never returns, poison of them, which no path reaches. The
// terminator is erased.
llvm::SmallVector<mlir::Value> inlineRegion(mlir::RewriterBase &rewriter, mlir::Operation *op,
                                            mlir::ValueRange args, mlir::TypeRange given);

// The sizes of the first `dims` dimensions of the domain of `op`.
llvm::SmallVector<mlir::OpFoldResult> extentsOf(mlir::OpBuilder &b,
                                                mlir::DestinationStyleOpInterface op,
                                                unsigned dims);

// What `array` holds at `indices` of its leading dimensions, of type
// `cell`: the element, or the cell of the dimensions after them (at no
// index, the array itself).
mlir::Value readCell(mlir::OpBuilder &b, mlir::Location loc, mlir::Value array,
                     mlir::ValueRange indices, mlir::Type cell);

// `array` with `cell`, an element or a cell, at `indices` of its leading
// dimensions (at no index, the cell itself).
mlir::Value writeCell(mlir::OpBuilder &b, mlir::Location loc, mlir::Value cell, mlir::Value array,
                      mlir::ValueRange indices);

} // namespace idr::structure

#endif // IDR_TRANSFORMS_STRUCTURELOOPS_H
