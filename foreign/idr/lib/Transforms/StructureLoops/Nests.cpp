// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The ordered form: an scf.for nest in the op's row-major order (the last
// dimension fastest), its region the innermost body, each array carried
// through the nest and written at each index. A region that never returns
// ends the step in its crash, and the step gives poison, which no path
// reaches. A cell whose dimensions its type leaves to the cells is made at
// the domain's first index before the array, which then has its size, and
// that first cell is the first written; the rest of the domain is one loop
// over its linear index: the region still runs once per index, in order.

#include "idr/Transforms/StructureLoops.h"

#include "mlir/Dialect/Affine/IR/AffineOps.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Arith/Utils/Utils.h"
#include "mlir/Dialect/Utils/IndexingUtils.h"
#include "mlir/Interfaces/InferTypeOpInterface.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVectorExtras.h"
#include "llvm/ADT/TypeSwitch.h"

using namespace mlir;

namespace idr::structure {

namespace {

SmallVector<Value> constants(OpBuilder &b, Location loc, unsigned count, int64_t value) {
  return SmallVector<Value>(count, arith::ConstantIndexOp::create(b, loc, value));
}

// A tabulation in order: the domain's indices in row-major order, the
// arrays carried through and written at each index, and `state`, what the
// region threads besides (in the world's order, the world; else nothing),
// carried after them. A step's region binds the indices, then the state,
// and gives the cells, then the state.
void tabulated(RewriterBase &rewriter, Operation *op, unsigned rank, TypeRange arrays,
               ArrayRef<Type> cells, ValueRange state) {
  Location loc = op->getLoc();
  rewriter.setInsertionPoint(op);
  SmallVector<Type> given(cells);
  llvm::append_range(given, state.getTypes());
  SmallVector<OpFoldResult> frame = extentsOf(rewriter, op, rank);
  SmallVector<Value> extents = valuesOf(rewriter, loc, frame);
  SmallVector<Value> zeros = constants(rewriter, loc, rank, 0);
  SmallVector<Value> ones = constants(rewriter, loc, rank, 1);
  // The dimensions of each array: the domain's, then each cell's, from
  // `cellDim` where its type leaves it dynamic.
  auto dimsOf = [&](RankedTensorType array, function_ref<OpFoldResult(unsigned)> cellDim) {
    SmallVector<OpFoldResult> dims(frame);
    for (unsigned d = rank, e = static_cast<unsigned>(array.getRank()); d < e; ++d)
      dims.push_back(array.isDynamicDim(d)
                         ? cellDim(d - rank)
                         : OpFoldResult(rewriter.getIndexAttr(array.getDimSize(d))));
    return dims;
  };
  // The region's arguments at `ivs`: the indices, then the state carried.
  auto argsAt = [&](ValueRange ivs, ValueRange carried) {
    SmallVector<Value> args(ivs);
    llvm::append_range(args, carried.take_back(state.size()));
    return args;
  };
  // What a step that gave `values` at `ivs` carries on: each cell written
  // into its array, then the state it gave.
  auto write = [&](OpBuilder &b, Location l, ArrayRef<Value> values, ValueRange carried,
                   ValueRange ivs) {
    SmallVector<Value> next;
    for (auto [cell, array] : llvm::zip(values, carried.drop_back(state.size())))
      next.push_back(writeCell(b, l, cell, array, ivs));
    llvm::append_range(next, values.take_back(state.size()));
    return next;
  };
  bool cellsKnown = llvm::all_of(arrays, [&](Type type) {
    auto array = cast<RankedTensorType>(type);
    return llvm::none_of(array.getShape().drop_front(rank), ShapedType::isDynamic);
  });
  if (cellsKnown) {
    // No dimension after the domain's is dynamic: the arrays are made
    // first, and every step writes its cells. With no dimension the one
    // step is the region.
    SmallVector<Value> carried = llvm::map_to_vector(arrays, [&](Type type) {
      return emptyOf(rewriter, loc, cast<RankedTensorType>(type), frame);
    });
    llvm::append_range(carried, state);
    scf::LoopNest nest = scf::buildLoopNest(
        rewriter, loc, zeros, extents, ones, carried,
        [&](OpBuilder &b, Location l, ValueRange ivs, ValueRange at) -> scf::ValueVector {
          return write(b, l, inlineRegion(rewriter, op, argsAt(ivs, at), given), at, ivs);
        });
    rewriter.replaceOp(op, nest.results);
    return;
  }
  // The cells' dimensions are the first cell's, made at the domain's zero
  // index before the arrays, which then have their size; that first cell is
  // the first written. The domain's size is the product of its extents
  // (one for no dimension), and the rest of it, from 1, one loop over the
  // linear index, delinearized in row-major order. An empty domain has no
  // first cell, and its arrays no cell.
  Value one = arith::ConstantIndexOp::create(rewriter, loc, 1);
  Value count = one;
  for (Value extent : extents)
    count = arith::MulIOp::create(rewriter, loc, count, extent);
  Value zero = arith::ConstantIndexOp::create(rewriter, loc, 0);
  Value any = arith::CmpIOp::create(rewriter, loc, arith::CmpIPredicate::ne, count, zero);
  SmallVector<Type> results(arrays);
  llvm::append_range(results, state.getTypes());
  auto choice = scf::IfOp::create(
      rewriter, loc, any,
      [&](OpBuilder &b, Location l) {
        SmallVector<Value> first = cloneRegion(b, op, argsAt(zeros, state), given);
        // A domain of no dimension has one cell, the first: it is each
        // array, and the state it gave is the state.
        if (rank == 0) {
          scf::YieldOp::create(b, l, first);
          return;
        }
        SmallVector<Value> empties;
        for (auto [type, cell] : llvm::zip(arrays, first)) {
          auto array = cast<RankedTensorType>(type);
          empties.push_back(emptyOf(b, l, array, dimsOf(array, [&](unsigned d) {
                                      return tensor::getMixedSize(b, l, cell, d);
                                    })));
        }
        llvm::append_range(empties, state);
        SmallVector<Value> written = write(b, l, first, empties, zeros);
        auto rest = scf::ForOp::create(
            b, l, one, count, one, written,
            [&](OpBuilder &fb, Location fl, Value k, ValueRange carried) {
              // The basis stays dynamic: a dimension the code knows is zero
              // leaves this loop dead, where a static zero in the basis is
              // one the op's verifier refuses.
              auto ivs = affine::AffineDelinearizeIndexOp::create(
                  fb, fl, k, extents, SmallVector<int64_t>(rank, ShapedType::kDynamic));
              SmallVector<Value> made =
                  inlineRegion(rewriter, op, argsAt(ivs.getResults(), carried), given);
              scf::YieldOp::create(fb, fl, write(fb, fl, made, carried, ivs.getResults()));
            });
        scf::YieldOp::create(b, l, rest.getResults());
      },
      [&](OpBuilder &b, Location l) {
        SmallVector<Value> empties;
        for (Type type : arrays) {
          auto array = cast<RankedTensorType>(type);
          empties.push_back(emptyOf(b, l, array, dimsOf(array, [&](unsigned) {
                                      return OpFoldResult(b.getIndexAttr(0));
                                    })));
        }
        llvm::append_range(empties, state);
        scf::YieldOp::create(b, l, empties);
      });
  rewriter.replaceOp(op, choice.getResults());
}

// A fold in order: the frame's loops carrying the inits, and in each the
// fold's loop carrying the accumulators read from them there, written back
// after it. A scan carries its results through both and writes each step's
// accumulators at that step.
void folded(RewriterBase &rewriter, LastAxisFoldOpInterface op) {
  bool scan = isa<ScanLastOp>(op);
  Location loc = op->getLoc();
  unsigned frame = op.getFrameRank();
  auto count = static_cast<unsigned>(op.getInits().size());
  SmallVector<Type> accumulators(ValueRange(op.getAccumulators()).getTypes());
  rewriter.setInsertionPoint(op);
  SmallVector<Value> extents = valuesOf(rewriter, loc, extentsOf(rewriter, op, frame));
  SmallVector<Value> zeros = constants(rewriter, loc, frame, 0);
  SmallVector<Value> ones = constants(rewriter, loc, frame, 1);
  Value zero = arith::ConstantIndexOp::create(rewriter, loc, 0);
  Value one = arith::ConstantIndexOp::create(rewriter, loc, 1);
  SmallVector<Value> carried(op.getInits());
  // The scan's write of each step: it carries its results, made first.
  if (scan) {
    ReifiedRankedShapedTypeDims shapes;
    (void)reifyResultShapes(rewriter, op, shapes);
    carried.clear();
    for (auto [type, shape] : llvm::zip_equal(op->getResultTypes(), shapes))
      carried.push_back(emptyOf(rewriter, loc, cast<RankedTensorType>(type), shape));
  }
  scf::LoopNest nest = scf::buildLoopNest(
      rewriter, loc, zeros, extents, ones, carried,
      [&](OpBuilder &b, Location l, ValueRange ivs, ValueRange arrays) -> scf::ValueVector {
        SmallVector<Value> inits;
        for (auto [init, type] : llvm::zip_equal(scan ? ValueRange(op.getInits()) : arrays,
                                                 accumulators))
          inits.push_back(readCell(b, l, init, ivs, type));
        if (scan)
          llvm::append_range(inits, arrays);
        auto loop = scf::ForOp::create(
            b, l, zero, op.getLength(), one, inits,
            [&](OpBuilder &fb, Location fl, Value at, ValueRange state) {
              SmallVector<Value> args(ivs);
              args.push_back(at);
              llvm::append_range(args, state.take_front(count));
              SmallVector<Value> next = inlineRegion(rewriter, op, args, accumulators);
              if (scan) {
                SmallVector<Value> indices(ivs);
                indices.push_back(at);
                for (auto [value, result] :
                     llvm::zip_equal(ArrayRef(next).take_front(count), state.drop_front(count)))
                  next.push_back(writeCell(fb, fl, value, result, indices));
              }
              scf::YieldOp::create(fb, fl, next);
            });
        if (scan)
          return SmallVector<Value>(loop.getResults().drop_front(count));
        SmallVector<Value> written;
        for (auto [value, array] : llvm::zip_equal(loop.getResults(), arrays))
          written.push_back(writeCell(b, l, value, array, ivs));
        return written;
      });
  rewriter.replaceOp(op, nest.results);
}

// A transpose in order: one loop per dimension of the result, each element
// read at the permuted index.
void transposed(RewriterBase &rewriter, TransposeOp op) {
  Location loc = op.getLoc();
  ArrayRef<int64_t> permutation = op.getPermutation();
  SmallVector<int64_t> inverse = invertPermutationVector(permutation);
  auto rank = static_cast<unsigned>(permutation.size());
  rewriter.setInsertionPoint(op);
  SmallVector<OpFoldResult> dims =
      applyPermutation(tensor::getMixedSizes(rewriter, loc, op.getInput()), permutation);
  Value empty = emptyOf(rewriter, loc, op.getType(), dims);
  scf::LoopNest nest = scf::buildLoopNest(
      rewriter, loc, constants(rewriter, loc, rank, 0), valuesOf(rewriter, loc, dims),
      constants(rewriter, loc, rank, 1), ValueRange{empty},
      [&](OpBuilder &b, Location l, ValueRange ivs, ValueRange carried) -> scf::ValueVector {
        // The result's index d is the input's index permutation[d].
        SmallVector<Value> at = applyPermutation(SmallVector<Value>(ivs), inverse);
        Value element = tensor::ExtractOp::create(b, l, op.getInput(), at);
        return {tensor::InsertOp::create(b, l, element, carried.front(), ivs).getResult()};
      });
  rewriter.replaceOp(op, nest.results);
}

} // namespace

void lowerOrdered(RewriterBase &rewriter, Operation *op) {
  // A tabulation in the world's order threads the world through its steps.
  TypeSwitch<Operation *>(op)
      .Case([&](TabulateOp t) {
        tabulated(rewriter, t, t.getRank(), t.getArrays().getTypes(), t.getCellTypes(),
                  ValueRange());
      })
      .Case([&](TabulateIOOp t) {
        Value world = t.getWorld();
        tabulated(rewriter, t, t.getRank(), t.getArrays().getTypes(), t.getCellTypes(), world);
      })
      .Case([&](LastAxisFoldOpInterface f) { folded(rewriter, f); })
      .Case([&](TransposeOp t) { transposed(rewriter, t); })
      .DefaultUnreachable("idr-structure-loops lowers an op it does not structure");
}

} // namespace idr::structure
