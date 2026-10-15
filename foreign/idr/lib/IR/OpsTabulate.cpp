// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The tabulations, idr.tabulate and idr.tabulate_io: a new array made of
// what a region gives at each index of a domain whose sizes the op's
// operands give, a cell's own dimensions the cells'; their rules, shapes,
// control flow and flow, and the tabulation in the world's order that
// orders nothing.

#include "idr/IR/Arrays.h"

#include "mlir/IR/PatternMatch.h"

using namespace mlir;
using namespace idr;
using namespace idr::arrays;

namespace {

// The region's terminator: what it yields, or nothing when it ends in
// ub.unreachable, never returning.
std::optional<ArrayYieldOp> yieldOf(Region &region) {
  Operation *end = region.front().getTerminator();
  if (auto yield = dyn_cast<ArrayYieldOp>(end))
    return yield;
  return std::nullopt;
}

// A tabulation's arrays: at least one, all sharing their `rank` leading
// dimensions, of which `sizes` gives the dynamic ones.
LogicalResult verifyTabulated(Operation *op, TypeRange arrays, unsigned rank, size_t sizes) {
  if (arrays.empty())
    return op->emitOpError("makes no array");
  auto first = cast<RankedTensorType>(arrays.front());
  for (Type type : arrays)
    if (!sameLead(first, cast<RankedTensorType>(type), rank))
      return op->emitOpError("makes ") << type << ", whose leading " << rank
                                       << " dimensions are not those of " << first;
  auto dynamic = static_cast<size_t>(llvm::count_if(first.getShape().take_front(rank),
                                                    ShapedType::isDynamic));
  if (sizes != dynamic)
    return op->emitOpError("takes ") << sizes << " sizes for " << dynamic
                                     << " dynamic dimensions of its domain";
  return success();
}

// The size of dimension `dim` of a domain whose sizes a tabulation's
// arrays and size operands give.
// The size operand of dynamic dimension `dim`: the one after those of the
// dynamic dimensions before it.
Value sizeOperand(RankedTensorType array, ValueRange sizes, unsigned dim) {
  auto before = llvm::count_if(array.getShape().take_front(dim), ShapedType::isDynamic);
  return sizes[static_cast<size_t>(before)];
}

OpFoldResult tabulatedExtent(OpBuilder &b, RankedTensorType array, ValueRange sizes, unsigned dim) {
  if (!array.isDynamicDim(dim))
    return b.getIndexAttr(array.getDimSize(dim));
  return sizeOperand(array, sizes, dim);
}

// The same, as an expression of the constraint set.
AffineExpr tabulatedExpr(ValueBoundsConstraintSet &cstr, RankedTensorType array, ValueRange sizes,
                         unsigned dim) {
  if (!array.isDynamicDim(dim))
    return cstr.getExpr(array.getDimSize(dim));
  return cstr.getExpr(sizeOperand(array, sizes, dim));
}

// A tabulation's shapes: the domain's sizes, then each cell's dimension
// where its type fixes it; a dynamic one is the cells' own, which no
// operand gives.
LogicalResult reifyTabulated(OpBuilder &b, TypeRange arrays, ValueRange sizes, unsigned rank,
                             ReifiedRankedShapedTypeDims &shapes) {
  for (Type type : arrays) {
    auto array = cast<RankedTensorType>(type);
    SmallVector<OpFoldResult> dims;
    for (unsigned d = 0, e = static_cast<unsigned>(array.getRank()); d < e; ++d)
      dims.push_back(d < rank ? tabulatedExtent(b, array, sizes, d)
                     : array.isDynamicDim(d) ? OpFoldResult()
                                             : OpFoldResult(b.getIndexAttr(array.getDimSize(d))));
    shapes.push_back(std::move(dims));
  }
  return success();
}

FailureOr<OpFoldResult> reifiedDim(FailureOr<SmallVector<OpFoldResult>> shape, int dim) {
  if (failed(shape) || dim < 0 || static_cast<size_t>(dim) >= shape->size() ||
      !(*shape)[static_cast<size_t>(dim)])
    return failure();
  return (*shape)[static_cast<size_t>(dim)];
}

// A cell's dimension `dim` of a tabulation's array, where its type fixes
// it.
void boundTabulated(Value value, int64_t dim, unsigned rank, ValueRange sizes,
                    ValueBoundsConstraintSet &cstr) {
  auto array = cast<RankedTensorType>(value.getType());
  auto at = static_cast<unsigned>(dim);
  if (at < rank)
    cstr.bound(value)[dim] == tabulatedExpr(cstr, array, sizes, at);
  else if (!array.isDynamicDim(at))
    cstr.bound(value)[dim] == array.getDimSize(at);
}

} // namespace

//===----------------------------------------------------------------------===//
// idr.tabulate
//===----------------------------------------------------------------------===//

LogicalResult TabulateOp::verify() {
  if (failed(verifyIndices(*this, getRank())))
    return failure();
  return verifyTabulated(*this, getArrays().getTypes(), getRank(), getSizes().size());
}

SmallVector<Type> TabulateOp::getCellTypes() {
  return llvm::map_to_vector(getArrays().getTypes(), [&](Type array) {
    return cellOf(cast<RankedTensorType>(array), getRank());
  });
}

LogicalResult TabulateOp::verifyRegions() { return verifyEnd(*this, getCellTypes()); }

SmallVector<Iteration> TabulateOp::getIterations() {
  return SmallVector<Iteration>(getRank(), Iteration::Parallel);
}

OpFoldResult TabulateOp::getExtent(OpBuilder &b, unsigned dim) {
  return tabulatedExtent(b, cast<RankedTensorType>(getArrays().front().getType()), getSizes(), dim);
}

void TabulateOp::getSuccessorRegions(RegionBranchPoint, SmallVectorImpl<RegionSuccessor> &regions) {
  generatingSuccessors(*this, regions);
}

// A new array, each element moved in at its index by the yield.
void TabulateOp::getFlowEdges(FlowEdges &edges) {
  for (Value array : getArrays())
    edges.fresh(array);
}

LogicalResult TabulateOp::reifyResultShapes(OpBuilder &b, ReifiedRankedShapedTypeDims &shapes) {
  return reifyTabulated(b, getArrays().getTypes(), getSizes(), getRank(), shapes);
}

FailureOr<OpFoldResult> TabulateOp::reifyDimOfResult(OpBuilder &b, int result, int dim) {
  return reifiedDim(reifyShapeOfResult(b, result), dim);
}

void TabulateOp::populateBoundsForIndexValue(Value value, ValueBoundsConstraintSet &cstr) {
  auto first = cast<RankedTensorType>(getArrays().front().getType());
  boundIndex(value, getIndices(),
             [&](unsigned dim) { return tabulatedExpr(cstr, first, getSizes(), dim); }, cstr);
}

void TabulateOp::populateBoundsForShapedValueDim(Value value, int64_t dim,
                                                 ValueBoundsConstraintSet &cstr) {
  boundTabulated(value, dim, getRank(), getSizes(), cstr);
}

//===----------------------------------------------------------------------===//
// idr.tabulate_io
//===----------------------------------------------------------------------===//

LogicalResult TabulateIOOp::verify() {
  if (getBody()->getNumArguments() == 0 || !isWorld(getWorldArgument().getType()))
    return emitOpError("binds no world after its indices");
  if (failed(verifyIndices(*this, getRank())))
    return failure();
  return verifyTabulated(*this, getArrays().getTypes(), getRank(), getSizes().size());
}

SmallVector<Type> TabulateIOOp::getCellTypes() {
  return llvm::map_to_vector(getArrays().getTypes(), [&](Type array) {
    return cellOf(cast<RankedTensorType>(array), getRank());
  });
}

LogicalResult TabulateIOOp::verifyRegions() {
  SmallVector<Type> given = getCellTypes();
  given.push_back(getWorldArgument().getType());
  return verifyEnd(*this, given);
}

SmallVector<Iteration> TabulateIOOp::getIterations() {
  return SmallVector<Iteration>(getRank(), Iteration::Ordered);
}

OpFoldResult TabulateIOOp::getExtent(OpBuilder &b, unsigned dim) {
  return tabulatedExtent(b, cast<RankedTensorType>(getArrays().front().getType()), getSizes(), dim);
}

void TabulateIOOp::getSuccessorRegions(RegionBranchPoint,
                                       SmallVectorImpl<RegionSuccessor> &regions) {
  generatingSuccessors(*this, regions);
}

// The world goes in from the op, wherever control goes first.
OperandRange TabulateIOOp::getEntrySuccessorOperands(RegionSuccessor) { return getODSOperands(1); }

ValueRange TabulateIOOp::getSuccessorInputs(RegionSuccessor successor) {
  if (successor.isOperation())
    return getODSResults(1);
  return getBody()->getArguments().take_back();
}

void TabulateIOOp::getFlowEdges(FlowEdges &edges) {
  for (Value array : getArrays())
    edges.fresh(array);
}

LogicalResult TabulateIOOp::reifyResultShapes(OpBuilder &b, ReifiedRankedShapedTypeDims &shapes) {
  return reifyTabulated(b, getArrays().getTypes(), getSizes(), getRank(), shapes);
}

FailureOr<OpFoldResult> TabulateIOOp::reifyDimOfResult(OpBuilder &b, int result, int dim) {
  return reifiedDim(reifyShapeOfResult(b, result), dim);
}

void TabulateIOOp::populateBoundsForIndexValue(Value value, ValueBoundsConstraintSet &cstr) {
  auto first = cast<RankedTensorType>(getArrays().front().getType());
  boundIndex(value, getIndices(),
             [&](unsigned dim) { return tabulatedExpr(cstr, first, getSizes(), dim); }, cstr);
}

void TabulateIOOp::populateBoundsForShapedValueDim(Value value, int64_t dim,
                                                   ValueBoundsConstraintSet &cstr) {
  boundTabulated(value, dim, getRank(), getSizes(), cstr);
}

namespace {

// A tabulation in the world's order whose region does nothing with the
// world but give it back, or never returns and does nothing with it, is a
// tabulation: no step of it is ordered by the world, and what else it may
// do (crash) its effects keep in order.
struct WorldUnused : OpRewritePattern<TabulateIOOp> {
  using OpRewritePattern::OpRewritePattern;
  LogicalResult matchAndRewrite(TabulateIOOp op, PatternRewriter &rewriter) const override {
    BlockArgument world = op.getWorldArgument();
    std::optional<ArrayYieldOp> yield = yieldOf(op.getRegion());
    bool passed = yield && world.hasOneUse() && yield->getValues().back() == world;
    if (!passed && !(!yield && world.use_empty()))
      return failure();
    auto made = TabulateOp::create(rewriter, op.getLoc(), op.getArrays().getTypes(), op.getSizes());
    rewriter.inlineRegionBefore(op.getRegion(), made.getRegion(), made.getRegion().end());
    if (yield) {
      rewriter.setInsertionPoint(*yield);
      rewriter.replaceOpWithNewOp<ArrayYieldOp>(*yield, yield->getValues().drop_back());
    }
    rewriter.modifyOpInPlace(made, [&] {
      made.getBody()->eraseArgument(made.getBody()->getNumArguments() - 1);
    });
    SmallVector<Value> replacements(made.getResults());
    replacements.push_back(op.getWorld());
    rewriter.replaceOp(op, replacements);
    return success();
  }
};

} // namespace

void TabulateIOOp::getCanonicalizationPatterns(RewritePatternSet &results, MLIRContext *context) {
  results.add<WorldUnused>(context);
}
