// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The forms that keep a parallel dimension parallel: one linalg op whose
// body is the op's region, moved. Each index of the region is the linalg
// op's index along its dimension (linalg.index), or an outer loop's
// induction variable where the dimension is ordered; an accumulator is the
// output's element; a read of an array from outside at the op's own
// indices is an input at that map, its element in the body.

#include "idr/Transforms/StructureLoops.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Utils/IndexingUtils.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::structure {

namespace {

// The inputs of a linalg op: one per distinct array read at a map, so an
// array read twice at one map is one input, and for each read the input
// it is.
struct Inputs {
  SmallVector<Value> arrays;
  SmallVector<AffineMap> maps;
  SmallVector<unsigned> of;
};

Inputs inputsOf(ArrayRef<Read> reads) {
  Inputs inputs;
  DenseMap<std::pair<Value, AffineMap>, unsigned> numbered;
  for (Read read : reads) {
    auto [at, fresh] = numbered.try_emplace({read.op.getTensor(), read.map},
                                            static_cast<unsigned>(inputs.arrays.size()));
    inputs.of.push_back(at->second);
    if (fresh) {
      inputs.arrays.push_back(read.op.getTensor());
      inputs.maps.push_back(read.map);
    }
  }
  return inputs;
}

Type elementOf(Value array) { return cast<RankedTensorType>(array.getType()).getElementType(); }

// The region's arguments, given the linalg op's body and the number of its
// inputs; the values the linalg op yields, given what the region yields.
using Bind = function_ref<SmallVector<Value>(OpBuilder &, Block *, unsigned)>;
using Yield = function_ref<SmallVector<Value>(ArrayRef<Value>)>;

// The linalg op over the first `dims` dimensions of `op`'s domain, whose
// body is `op`'s region, moved, which gives values of the types `given`:
// its inputs the region's reads, its outputs `outputs` at `outputMaps`. The
// rewriter's insertion point is kept, after the op made.
linalg::GenericOp genericOf(RewriterBase &rewriter, Operation *op, unsigned dims,
                            TypeRange results, ValueRange outputs, ArrayRef<AffineMap> outputMaps,
                            ArrayRef<utils::IteratorType> iterators, TypeRange given, Bind bind,
                            Yield yielded) {
  Location loc = op->getLoc();
  SmallVector<Read> reads = readsOf(op, dims);
  Inputs inputs = inputsOf(reads);
  SmallVector<AffineMap> maps(inputs.maps);
  llvm::append_range(maps, outputMaps);
  auto generic =
      linalg::GenericOp::create(rewriter, loc, results, inputs.arrays, outputs, maps, iterators);
  OpBuilder::InsertionGuard guard(rewriter);
  SmallVector<Type> types = llvm::map_to_vector(inputs.arrays, elementOf);
  llvm::append_range(types, llvm::map_range(outputs, elementOf));
  SmallVector<Location> locs(types.size(), loc);
  Block *body = rewriter.createBlock(&generic.getRegion(), generic.getRegion().end(), types, locs);
  SmallVector<Value> args = bind(rewriter, body, static_cast<unsigned>(inputs.arrays.size()));
  linalg::YieldOp::create(rewriter, loc, yielded(inlineRegion(rewriter, op, args, given)));
  for (auto [read, input] : llvm::zip_equal(reads, inputs.of))
    rewriter.replaceOp(read.op, body->getArgument(input));
  // An index the body does not read is none of its work.
  for (Operation &inner : llvm::make_early_inc_range(*body))
    if (isa<linalg::IndexOp>(inner) && inner.use_empty())
      rewriter.eraseOp(&inner);
  return generic;
}

// The linalg op's index along each of its first `count` dimensions, made
// first in its body.
SmallVector<Value> indicesOf(OpBuilder &b, Location loc, unsigned count) {
  SmallVector<Value> indices;
  for (unsigned d = 0; d < count; ++d)
    indices.push_back(linalg::IndexOp::create(b, loc, d));
  return indices;
}

SmallVector<Value> same(ArrayRef<Value> given) { return SmallVector<Value>(given); }

// The map from `dims` dimensions to the first `count` of them.
AffineMap leading(unsigned dims, unsigned count, MLIRContext *ctx) {
  SmallVector<AffineExpr> exprs;
  for (unsigned d = 0; d < count; ++d)
    exprs.push_back(getAffineDimExpr(d, ctx));
  return AffineMap::get(dims, 0, exprs, ctx);
}

} // namespace

void lowerParallel(RewriterBase &rewriter, Operation *op) {
  Location loc = op->getLoc();
  rewriter.setInsertionPoint(op);
  if (auto transpose = dyn_cast<TransposeOp>(op)) {
    SmallVector<OpFoldResult> dims = applyPermutation(
        tensor::getMixedSizes(rewriter, loc, transpose.getInput()), transpose.getPermutation());
    Value init = emptyOf(rewriter, loc, transpose.getType(), dims);
    auto made = linalg::TransposeOp::create(rewriter, loc, transpose.getInput(), init,
                                            transpose.getPermutation());
    rewriter.replaceOp(op, made->getResult(0));
    return;
  }
  auto tabulate = cast<TabulateOp>(op);
  unsigned rank = tabulate.getRank();
  SmallVector<OpFoldResult> dims = extentsOf(rewriter, op, rank);
  SmallVector<Value> outputs;
  for (Type type : tabulate.getArrays().getTypes())
    outputs.push_back(emptyOf(rewriter, loc, cast<RankedTensorType>(type), dims));
  SmallVector<AffineMap> maps(outputs.size(),
                              AffineMap::getMultiDimIdentityMap(rank, op->getContext()));
  SmallVector<Type> cells = tabulate.getCellTypes();
  linalg::GenericOp generic = genericOf(
      rewriter, op, rank, tabulate.getArrays().getTypes(), outputs, maps,
      SmallVector<utils::IteratorType>(rank, utils::IteratorType::parallel), cells,
      [&](OpBuilder &b, Block *, unsigned) { return indicesOf(b, loc, rank); }, same);
  rewriter.replaceOp(op, generic.getResults());
}

void lowerReduction(RewriterBase &rewriter, LastAxisFoldOpInterface op) {
  Location loc = op->getLoc();
  MLIRContext *ctx = op->getContext();
  unsigned frame = op.getFrameRank();
  rewriter.setInsertionPoint(op);
  SmallVector<AffineMap> maps(op.getInits().size(), leading(frame + 1, frame, ctx));
  SmallVector<utils::IteratorType> iterators(frame, utils::IteratorType::parallel);
  iterators.push_back(utils::IteratorType::reduction);
  // Held apart from the region, which the linalg op takes.
  SmallVector<Type> accumulators(ValueRange(op.getAccumulators()).getTypes());
  linalg::GenericOp generic = genericOf(
      rewriter, op, frame + 1, op->getResultTypes(), op.getInits(), maps, iterators, accumulators,
      [&](OpBuilder &b, Block *body, unsigned inputs) {
        SmallVector<Value> args = indicesOf(b, loc, frame + 1);
        llvm::append_range(args, body->getArguments().drop_front(inputs));
        return args;
      },
      same);
  rewriter.replaceOp(op, generic.getResults());
}

void lowerInterchange(RewriterBase &rewriter, LastAxisFoldOpInterface op) {
  Location loc = op->getLoc();
  MLIRContext *ctx = op->getContext();
  bool scan = isa<ScanLastOp>(op);
  ValueRange inits = op.getInits();
  Value length = op.getLength();
  unsigned frame = op.getFrameRank();
  auto count = static_cast<unsigned>(inits.size());
  rewriter.setInsertionPoint(op);
  SmallVector<OpFoldResult> extents = extentsOf(rewriter, op, frame + 1);
  // A scan writes each step's accumulators into its results at that step.
  SmallVector<Value> carried(inits);
  if (scan)
    for (Type type : op->getResultTypes())
      carried.push_back(emptyOf(rewriter, loc, cast<RankedTensorType>(type), extents));
  Value zero = arith::ConstantIndexOp::create(rewriter, loc, 0);
  Value one = arith::ConstantIndexOp::create(rewriter, loc, 1);
  auto loop = scf::ForOp::create(rewriter, loc, zero, length, one, carried);
  Block *step = loop.getBody();
  rewriter.setInsertionPointToStart(step);
  ValueRange accumulators = loop.getRegionIterArgs().take_front(count);
  ValueRange results = loop.getRegionIterArgs().drop_front(count);
  // Each result's slice at the step: the frame, the step's one index.
  auto sliceAt = [&](Value result) {
    SmallVector<OpFoldResult> sizes = tensor::getMixedSizes(rewriter, loc, result);
    sizes[frame] = rewriter.getIndexAttr(1);
    SmallVector<OpFoldResult> offsets(frame + 1, rewriter.getIndexAttr(0));
    offsets[frame] = loop.getInductionVar();
    SmallVector<OpFoldResult> strides(frame + 1, rewriter.getIndexAttr(1));
    return std::tuple(offsets, sizes, strides);
  };
  SmallVector<Value> outputs(accumulators);
  // A fold carries its accumulators alone; a scan also its results, each
  // written at the step as its init's slice.
  if (scan)
    for (auto [result, init] : llvm::zip_equal(results, inits)) {
      auto [offsets, sizes, strides] = sliceAt(result);
      outputs.push_back(tensor::ExtractSliceOp::create(
          rewriter, loc, cast<RankedTensorType>(init.getType()), result, offsets, sizes, strides));
    }
  SmallVector<AffineMap> maps(outputs.size(), AffineMap::getMultiDimIdentityMap(frame, ctx));
  // Held apart from the region, which the linalg op takes.
  SmallVector<Type> stepTypes(ValueRange(op.getAccumulators()).getTypes());
  linalg::GenericOp generic = genericOf(
      rewriter, op, frame, ValueRange(outputs).getTypes(), outputs, maps,
      SmallVector<utils::IteratorType>(frame, utils::IteratorType::parallel), stepTypes,
      [&](OpBuilder &b, Block *body, unsigned inputs) {
        SmallVector<Value> args = indicesOf(b, loc, frame);
        args.push_back(loop.getInductionVar());
        llvm::append_range(args, body->getArguments().drop_front(inputs).take_front(count));
        return args;
      },
      [&](ArrayRef<Value> given) {
        SmallVector<Value> yielded(given);
        if (scan)
          llvm::append_range(yielded, given);
        return yielded;
      });
  SmallVector<Value> next(generic.getResults().take_front(count));
  for (auto [result, written] : llvm::zip_equal(results, generic.getResults().drop_front(count))) {
    auto [offsets, sizes, strides] = sliceAt(result);
    next.push_back(
        tensor::InsertSliceOp::create(rewriter, loc, written, result, offsets, sizes, strides));
  }
  scf::YieldOp::create(rewriter, loc, next);
  rewriter.replaceOp(op, scan ? loop.getResults().drop_front(count) : loop.getResults());
}

} // namespace idr::structure
