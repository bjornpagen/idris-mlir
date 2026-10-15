// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The ordered form: an scf.for nest in the op's row-major order (the last
// dimension fastest), its region the innermost body, each array carried
// through the nest and written at each index. A region that never returns
// ends the step in its crash, and the step yields poison, which no path
// reaches. A cell whose dimensions its type leaves to the cells is made at
// the domain's first index before the array, which then has its size, and
// that first cell is the first written: the region still runs once per
// index, in order.

#include "idr/Transforms/StructureLoops.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Arith/Utils/Utils.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/TypeSwitch.h"

using namespace mlir;

namespace idr::structure {

namespace {

// Poison of each type: the values of a step that never ends.
SmallVector<Value> poisonOf(OpBuilder &b, Location loc, TypeRange types) {
  return llvm::map_to_vector(types, [&](Type type) -> Value {
    return ub::PoisonOp::create(b, loc, type);
  });
}

// What the region gave, or poison of `types` where it never returns.
SmallVector<Value> orPoison(OpBuilder &b, Location loc, std::optional<SmallVector<Value>> given,
                            TypeRange types) {
  return given ? *given : poisonOf(b, loc, types);
}

SmallVector<Value> constants(OpBuilder &b, Location loc, unsigned count, int64_t value) {
  return SmallVector<Value>(count, arith::ConstantIndexOp::create(b, loc, value));
}

// A tabulation in order: one loop per dimension of its domain, carrying
// the arrays and, in the world's order, the world. `world` is the world
// it starts from, or null.
void tabulated(RewriterBase &rewriter, Operation *op, unsigned rank, TypeRange arrays,
               ArrayRef<Type> cells, Value world) {
  Location loc = op->getLoc();
  rewriter.setInsertionPoint(op);
  auto withWorld = [&](ValueRange values, Value next) {
    SmallVector<Value> all(values);
    if (world)
      all.push_back(next);
    return all;
  };
  SmallVector<Type> given(cells);
  if (world)
    given.push_back(world.getType());
  // No dimension: the region runs once, and what it gives is the array.
  if (rank == 0) {
    std::optional<SmallVector<Value>> made = inlineRegion(rewriter, op, withWorld({}, world));
    SmallVector<Value> values = orPoison(rewriter, loc, made, given);
    SmallVector<Value> results;
    for (auto [type, value] : llvm::zip(arrays, values))
      results.push_back(isa<RankedTensorType>(value.getType())
                            ? value
                            : tensor::FromElementsOp::create(rewriter, loc, type, value));
    if (world)
      results.push_back(values.back());
    rewriter.replaceOp(op, results);
    return;
  }
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
  // Writes what a step gave at its indices.
  auto write = [&](OpBuilder &b, Location l, ArrayRef<Value> values, ValueRange carried,
                   ValueRange ivs) {
    SmallVector<Value> next;
    for (unsigned j = 0, e = static_cast<unsigned>(arrays.size()); j < e; ++j)
      next.push_back(writeCell(b, l, values[j], carried[j], ivs));
    if (world)
      next.push_back(values.back());
    return next;
  };
  bool cellsKnown = llvm::all_of(arrays, [&](Type type) {
    auto array = cast<RankedTensorType>(type);
    return llvm::none_of(array.getShape().drop_front(rank), ShapedType::isDynamic);
  });
  if (cellsKnown) {
    SmallVector<Value> empties;
    for (Type type : arrays) {
      auto array = cast<RankedTensorType>(type);
      empties.push_back(emptyOf(rewriter, loc, array, dimsOf(array, [](unsigned) {
                                  return OpFoldResult();
                                })));
    }
    scf::LoopNest nest = scf::buildLoopNest(
        rewriter, loc, zeros, extents, ones, withWorld(empties, world),
        [&](OpBuilder &b, Location l, ValueRange ivs, ValueRange carried) -> scf::ValueVector {
          SmallVector<Value> args(ivs);
          if (world)
            args.push_back(carried.back());
          std::optional<SmallVector<Value>> made = inlineRegion(rewriter, op, args);
          if (!made)
            return poisonOf(b, l, ValueRange(carried).getTypes());
          return write(b, l, *made, carried, ivs);
        });
    rewriter.replaceOp(op, nest.results);
    return;
  }
  // The cells' dimensions are the first cell's: made before the arrays,
  // when the domain has an index, and then reused at that index.
  Value count = extents.front();
  for (Value extent : ArrayRef(extents).drop_front())
    count = arith::MulIOp::create(rewriter, loc, count, extent);
  Value any = arith::CmpIOp::create(rewriter, loc, arith::CmpIPredicate::ne, count, zeros.front());
  SmallVector<Type> results(arrays);
  if (world)
    results.push_back(world.getType());
  auto choice = scf::IfOp::create(
      rewriter, loc, any,
      [&](OpBuilder &b, Location l) {
        std::optional<SmallVector<Value>> first = cloneRegion(b, op, withWorld(zeros, world));
        if (!first) {
          scf::YieldOp::create(b, l, poisonOf(b, l, results));
          return;
        }
        SmallVector<Value> empties;
        for (auto [type, cell] : llvm::zip(arrays, *first)) {
          auto array = cast<RankedTensorType>(type);
          empties.push_back(emptyOf(b, l, array, dimsOf(array, [&](unsigned d) {
                                      return tensor::getMixedSize(b, l, cell, d);
                                    })));
        }
        scf::LoopNest nest = scf::buildLoopNest(
            b, l, zeros, extents, ones, withWorld(empties, first->back()),
            [&](OpBuilder &nb, Location nl, ValueRange ivs,
                ValueRange carried) -> scf::ValueVector {
              Value atFirst = arith::ConstantIntOp::create(nb, nl, 1, 1);
              for (Value iv : ivs)
                atFirst = arith::AndIOp::create(
                    nb, nl, atFirst,
                    arith::CmpIOp::create(nb, nl, arith::CmpIPredicate::eq, iv, zeros.front()));
              auto step = scf::IfOp::create(
                  nb, nl, atFirst,
                  [&](OpBuilder &tb, Location tl) {
                    SmallVector<Value> values(ArrayRef(*first).take_front(arrays.size()));
                    Value next = world ? carried.back() : Value();
                    scf::YieldOp::create(tb, tl, withWorld(values, next));
                  },
                  [&](OpBuilder &eb, Location el) {
                    SmallVector<Value> args(ivs);
                    if (world)
                      args.push_back(carried.back());
                    std::optional<SmallVector<Value>> made = cloneRegion(eb, op, args);
                    scf::YieldOp::create(eb, el, orPoison(eb, el, made, given));
                  });
              SmallVector<Value> values(step.getResults());
              return write(nb, nl, values, carried, ivs);
            });
        scf::YieldOp::create(b, l, nest.results);
      },
      [&](OpBuilder &b, Location l) {
        SmallVector<Value> empties;
        for (Type type : arrays) {
          auto array = cast<RankedTensorType>(type);
          empties.push_back(emptyOf(b, l, array, dimsOf(array, [&](unsigned) {
                                      return OpFoldResult(b.getIndexAttr(0));
                                    })));
        }
        scf::YieldOp::create(b, l, withWorld(empties, world));
      });
  rewriter.replaceOp(op, choice.getResults());
}

// A fold in order: the frame's loops carrying the inits, and in each the
// fold's loop carrying the accumulators read from them there, written back
// after it. A scan carries its results through both and writes each step's
// accumulators at that step.
template <typename OpT>
void folded(RewriterBase &rewriter, OpT op, bool scan) {
  Location loc = op.getLoc();
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
  if (scan) {
    ReifiedRankedShapedTypeDims shapes;
    (void)op.reifyResultShapes(rewriter, shapes);
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
              std::optional<SmallVector<Value>> made = inlineRegion(rewriter, op, args);
              if (!made) {
                scf::YieldOp::create(fb, fl, poisonOf(fb, fl, state.getTypes()));
                return;
              }
              SmallVector<Value> next(*made);
              if (scan) {
                SmallVector<Value> indices(ivs);
                indices.push_back(at);
                for (auto [value, result] : llvm::zip_equal(*made, state.drop_front(count)))
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
  auto rank = static_cast<unsigned>(permutation.size());
  rewriter.setInsertionPoint(op);
  SmallVector<OpFoldResult> dims;
  for (int64_t from : permutation)
    dims.push_back(tensor::getMixedSize(rewriter, loc, op.getInput(), from));
  Value empty = emptyOf(rewriter, loc, op.getType(), dims);
  scf::LoopNest nest = scf::buildLoopNest(
      rewriter, loc, constants(rewriter, loc, rank, 0), valuesOf(rewriter, loc, dims),
      constants(rewriter, loc, rank, 1), ValueRange{empty},
      [&](OpBuilder &b, Location l, ValueRange ivs, ValueRange carried) -> scf::ValueVector {
        SmallVector<Value> at(rank);
        for (auto [d, from] : llvm::enumerate(permutation))
          at[static_cast<size_t>(from)] = ivs[d];
        Value element = tensor::ExtractOp::create(b, l, op.getInput(), at);
        return {tensor::InsertOp::create(b, l, element, carried.front(), ivs).getResult()};
      });
  rewriter.replaceOp(op, nest.results);
}

} // namespace

void lowerOrdered(RewriterBase &rewriter, Operation *op) {
  TypeSwitch<Operation *>(op)
      .Case([&](TabulateOp t) {
        tabulated(rewriter, t, t.getRank(), t.getArrays().getTypes(), t.getCellTypes(), {});
      })
      .Case([&](TabulateIOOp t) {
        tabulated(rewriter, t, t.getRank(), t.getArrays().getTypes(), t.getCellTypes(),
                  t.getWorld());
      })
      .Case([&](FoldLastOp f) { folded(rewriter, f, false); })
      .Case([&](ScanLastOp s) { folded(rewriter, s, true); })
      .Case([&](TransposeOp t) { transposed(rewriter, t); });
}

} // namespace idr::structure
