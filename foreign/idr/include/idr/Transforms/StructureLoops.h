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
// An op whose region holds a call on its function's own cycle is made its
// loops on the counted program, before the frames are made, as join points
// from the same tiling methods, and an element's update holding one a take
// and a put-back around its region's code (joinCycles): frames split a
// join region and straight code, and no other region of these ops.
//
//===----------------------------------------------------------------------===//

#ifndef IDR_TRANSFORMS_STRUCTURELOOPS_H
#define IDR_TRANSFORMS_STRUCTURELOOPS_H

#include "idr/IR/Arrays.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Footprint.h"

#include "mlir/Dialect/Linalg/IR/Linalg.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/IR/AffineMap.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/DestinationStyleOpInterface.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <concepts>

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

// What `array` holds at `indices` of its leading dimensions, of type
// `cell`: the element, or the cell of the dimensions after them (at no
// index, the array itself).
mlir::Value readCell(mlir::OpBuilder &b, mlir::Location loc, mlir::Value array,
                     mlir::ValueRange indices, mlir::Type cell);

// `array` with `cell`, an element or a cell, at `indices` of its leading
// dimensions (at no index, the cell itself).
mlir::Value writeCell(mlir::OpBuilder &b, mlir::Location loc, mlir::Value cell, mlir::Value array,
                      mlir::ValueRange indices);

// `op`, an op of the generating set on buffers, made its loops as join
// points: one idr.loop per dimension of its domain, in row-major order,
// each entered at 0 and turning while its index is below its dimension's
// size, the step its own tiling method makes at the indices. The calls the
// step moves are decided again where they now stand.
mlir::LogicalResult joinLoops(mlir::RewriterBase &rewriter, mlir::DestinationStyleOpInterface op);

// `update`, whose region holds a call on its function's own cycle, split
// where frames can take it apart: its element taken out of its place, its
// region's code inline, the rebuilt element put back. The calls it moves
// are decided again where they now stand.
void splitUpdate(mlir::RewriterBase &rewriter, ArrayUpdateOp update);

// Every op in `fn` whose region holds a call that `onCycle` says runs a
// function of `fn`'s own cycle, made what frames can split: each element's
// update split around its code, then each op of the generating set made
// its join-point loops. Run where the program is counted and before its
// frames are made. An update holds no op of the generating set, which
// writes memory an update's region may not touch, so the updates go first;
// an op of the generating set inside another is made its loops first, so
// the outer op's step clones loops already, and no op is visited twice.
template <typename OnCycle>
  requires std::predicate<OnCycle &, CallOp>
mlir::LogicalResult joinCycles(mlir::RewriterBase &rewriter, FuncOp fn, OnCycle &&onCycle) {
  auto holds = [&](mlir::Operation *op) {
    return op
        ->walk([&](CallOp call) {
          return onCycle(call) ? mlir::WalkResult::interrupt() : mlir::WalkResult::advance();
        })
        .wasInterrupted();
  };
  footprint::Vector<ArrayUpdateOp> updates;
  fn.walk([&](ArrayUpdateOp update) {
    if (holds(update))
      updates.push_back(update);
  });
  // The last first: a region that never returns ends its block, and what
  // followed it, a later update among it, goes.
  for (ArrayUpdateOp update : llvm::reverse(updates))
    splitUpdate(rewriter, update);
  footprint::Vector<mlir::DestinationStyleOpInterface> holding;
  fn->walk<mlir::WalkOrder::PostOrder>([&](mlir::Operation *op) {
    if (arrays::isGenerating(op) && holds(op))
      holding.push_back(llvm::cast<mlir::DestinationStyleOpInterface>(op));
  });
  for (mlir::DestinationStyleOpInterface op : holding)
    if (mlir::failed(joinLoops(rewriter, op)))
      return mlir::failure();
  return mlir::success();
}

} // namespace idr::structure

#endif // IDR_TRANSFORMS_STRUCTURELOOPS_H
